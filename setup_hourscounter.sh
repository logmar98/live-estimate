#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="$HOME/.local/bin"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
SCRIPT_PATH="$BIN_DIR/live_estimate.py"

mkdir -p "$BIN_DIR" "$SYSTEMD_USER_DIR"

cat > "$SCRIPT_PATH" << 'PYEOF'
#!/usr/bin/env python3
"""Live-estimate active session & logtime counter (gross minus ft_lock time)."""

from __future__ import annotations

import argparse
from datetime import datetime, timedelta
import fcntl
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import time
from typing import Any


DATA_DIR = Path.home() / ".local" / "share" / "live_estimate"
LEDGER_PATH = DATA_DIR / "sessions.json"
LOCK_FILE_PATH = DATA_DIR / "sessions.lock"
SEAT0_STATE_PATH = Path("/run/42-lock/seat0.json")

STALE_SESSION_TIMEOUT_SEC = 90.0


def parse_loginctl_timestamp(raw: str) -> float:
    """Parse loginctl Timestamp strings like 'Tue 2026-11-17 09:45:30 +00'."""
    text = raw.strip()
    match = re.match(r"^(.+?)\s+([+-]\d{2})(?::?(\d{2}))?$", text)
    if match:
        base, tz_h, tz_m = match.groups()
        tz_norm = f"{tz_h}{tz_m or '00'}"
        try:
            dt = datetime.strptime(f"{base} {tz_norm}", "%a %Y-%m-%d %H:%M:%S %z")
            return dt.timestamp()
        except ValueError:
            pass
    res = subprocess.run(
        ["date", "-d", text, "+%s"],
        capture_output=True,
        text=True,
        timeout=5,
        check=True,
    )
    return float(res.stdout.strip())


def _query_session_props(sid: str) -> dict[str, str]:
    res = subprocess.run(
        [
            "loginctl",
            "show-session",
            sid,
            "-p",
            "Id",
            "-p",
            "Name",
            "-p",
            "User",
            "-p",
            "Class",
            "-p",
            "Type",
            "-p",
            "State",
            "-p",
            "Active",
            "-p",
            "Timestamp",
            "-p",
            "Seat",
            "-p",
            "LockedHint",
        ],
        capture_output=True,
        text=True,
        timeout=5,
    )
    if res.returncode != 0:
        return {}
    return dict(line.split("=", 1) for line in res.stdout.splitlines() if "=" in line)


def get_current_session() -> dict[str, Any] | None:
    """Return the active local graphical X11 session for the current user."""
    username = os.environ.get("USER") or subprocess.check_output(["whoami"], text=True).strip()
    uid = os.getuid()

    candidates: list[str] = []
    seat_res = subprocess.run(
        ["loginctl", "show-seat", "seat0", "-p", "ActiveSession", "--value"],
        capture_output=True,
        text=True,
        timeout=5,
    )
    if seat_res.returncode == 0 and seat_res.stdout.strip():
        candidates.append(seat_res.stdout.strip())

    list_res = subprocess.run(
        ["loginctl", "list-sessions", "--no-legend"],
        capture_output=True,
        text=True,
        timeout=5,
    )
    if list_res.returncode == 0:
        for line in list_res.stdout.splitlines():
            parts = line.split()
            if len(parts) >= 3 and parts[2] == username and parts[0] not in candidates:
                candidates.append(parts[0])

    for sid in candidates:
        props = _query_session_props(sid)
        if not props:
            continue
        if (
            props.get("Name") == username
            and props.get("User") == str(uid)
            and props.get("Class") == "user"
            and props.get("Type") == "x11"
            and props.get("State") in ("active", "online", "closing")
            and props.get("Timestamp")
        ):
            start_ts = parse_loginctl_timestamp(props["Timestamp"])
            return {
                "host": socket.gethostname(),
                "session_id": props.get("Id", sid),
                "username": username,
                "uid": uid,
                "start_ts": start_ts,
                "state": props.get("State", "active"),
            }
    return None


def read_seat0_lock_state(username: str, uid: int, session_id: str) -> tuple[bool, list[list[float | None]]]:
    """Read lock state and raw intervals from /run/42-lock/seat0.json if owned by this session."""
    if not SEAT0_STATE_PATH.exists():
        return False, []
    try:
        data = json.loads(SEAT0_STATE_PATH.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return False, []

    if data.get("username") != username or data.get("uid") != uid:
        return False, []
    # Require matching session when inspecting current lock state.
    if data.get("session") != session_id:
        return False, []

    raw_intervals = data.get("intervals") or []
    cleaned: list[list[float | None]] = []
    for item in raw_intervals:
        if isinstance(item, list) and len(item) == 2 and item[0] is not None:
            start = float(item[0])
            end = float(item[1]) if item[1] is not None else None
            cleaned.append([start, end])
    return bool(data.get("locked")), cleaned


def merge_session_intervals(
    existing: list[list[float | None]],
    incoming: list[list[float | None]],
    session_start: float,
    now_ts: float,
) -> list[list[float | None]]:
    """Merge lock intervals belonging to this session without losing history."""
    merged = [[float(iv[0]), (float(iv[1]) if iv[1] is not None else None)] for iv in existing]

    for s, e in incoming:
        # Ignore intervals from earlier sessions on the same post.
        if e is not None and e <= session_start:
            continue
        clipped_s = max(s, session_start)
        clipped_e = min(e, now_ts) if e is not None else None
        if clipped_e is not None and clipped_e <= clipped_s:
            continue

        matched = False
        for idx, (es, ee) in enumerate(merged):
            if abs(es - clipped_s) <= 1.5:
                if clipped_e is not None:
                    merged[idx][1] = max(ee, clipped_e) if ee is not None else clipped_e
                matched = True
                break
        if not matched:
            merged.append([clipped_s, clipped_e])

    merged.sort(key=lambda iv: iv[0])
    return merged


def normalize_and_sum_locks(
    intervals: list[list[float | None]],
    win_start: float,
    win_end: float,
    open_fallback_end: float,
) -> tuple[float, int]:
    """Merge overlapping lock intervals and return (locked_seconds, count) inside [win_start, win_end]."""
    clipped: list[tuple[float, float]] = []
    for s, e in intervals:
        eff_end = e if e is not None else open_fallback_end
        a = max(float(s), win_start)
        b = min(float(eff_end), win_end)
        if b > a:
            clipped.append((a, b))

    if not clipped:
        return 0.0, 0

    clipped.sort(key=lambda pair: pair[0])
    merged: list[list[float]] = [[clipped[0][0], clipped[0][1]]]
    for a, b in clipped[1:]:
        if a <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], b)
        else:
            merged.append([a, b])

    total_locked = sum(b - a for a, b in merged)
    return total_locked, len(merged)


def load_ledger_locked() -> dict[str, Any]:
    if not LEDGER_PATH.exists():
        return {"version": 1, "sessions": {}}
    try:
        data = json.loads(LEDGER_PATH.read_text(encoding="utf-8"))
        if isinstance(data, dict) and isinstance(data.get("sessions"), dict):
            return data
    except (OSError, ValueError):
        pass
    return {"version": 1, "sessions": {}}


def save_ledger_atomic(data: dict[str, Any]) -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    tmp = LEDGER_PATH.with_suffix(".tmp")
    with open(tmp, "w", encoding="utf-8") as stream:
        json.dump(data, stream, indent=2, sort_keys=True)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(tmp, LEDGER_PATH)


def finalize_session(rec: dict[str, Any], end_ts: float) -> None:
    """Mark a session closed at end_ts and close any unclosed trailing lock interval."""
    rec["closed"] = True
    rec["last_seen"] = max(float(rec.get("last_seen", end_ts)), end_ts)
    rec["end_ts"] = rec["last_seen"]
    intervals = rec.get("intervals", [])
    for iv in intervals:
        if iv[1] is None:
            iv[1] = rec["end_ts"]
    rec["locked"] = False


def update_ledger(closing: bool = False) -> tuple[dict[str, Any], str | None]:
    """Update the persistent session ledger with current session & lock state."""
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    now_ts = time.time()
    current = get_current_session()
    current_key: str | None = None

    with open(LOCK_FILE_PATH, "w", encoding="utf-8") as lock_fh:
        fcntl.flock(lock_fh, fcntl.LOCK_EX)
        try:
            ledger = load_ledger_locked()
            sessions: dict[str, Any] = ledger["sessions"]

            if current is not None:
                current_key = f"{current['host']}|{current['session_id']}|{int(current['start_ts'])}"

            # Finalize older sessions on the same host or stale sessions from crashed posts.
            for key, rec in list(sessions.items()):
                if key == current_key or rec.get("closed"):
                    continue
                same_host = current is not None and rec.get("host") == current["host"]
                stale = (now_ts - float(rec.get("last_seen", now_ts))) > STALE_SESSION_TIMEOUT_SEC
                if same_host or stale:
                    finalize_session(rec, float(rec.get("last_seen", now_ts)))

            if current is not None and current_key is not None:
                rec = sessions.setdefault(
                    current_key,
                    {
                        "host": current["host"],
                        "session_id": current["session_id"],
                        "username": current["username"],
                        "uid": current["uid"],
                        "start_ts": current["start_ts"],
                        "last_seen": now_ts,
                        "end_ts": None,
                        "closed": False,
                        "locked": False,
                        "intervals": [],
                    },
                )
                is_locked, raw_intervals = read_seat0_lock_state(
                    current["username"], current["uid"], current["session_id"]
                )
                rec["intervals"] = merge_session_intervals(
                    rec.get("intervals", []), raw_intervals, float(rec["start_ts"]), now_ts
                )
                # Close previously open interval if seat0 reports unlocked without the final end_ts yet.
                if not is_locked:
                    for iv in rec["intervals"]:
                        if iv[1] is None:
                            iv[1] = now_ts
                rec["locked"] = is_locked
                rec["last_seen"] = now_ts
                if closing or current["state"] == "closing":
                    finalize_session(rec, now_ts)

            save_ledger_atomic(ledger)
            return ledger, current_key
        finally:
            fcntl.flock(lock_fh, fcntl.LOCK_UN)


def parse_duration_arg(value: str) -> float:
    """Parse durations like '02:58', '1:30:00', or decimal hours like '2' or '1.5' into seconds."""
    text = value.strip()
    if ":" in text:
        parts = text.split(":")
        if len(parts) == 2:
            h, m = int(parts[0]), int(parts[1])
            return max(0.0, h * 3600.0 + m * 60.0)
        if len(parts) == 3:
            h, m, s = int(parts[0]), int(parts[1]), int(parts[2])
            return max(0.0, h * 3600.0 + m * 60.0 + s)
    return max(0.0, float(text) * 3600.0)


def attendo_period_bounds(now_dt: datetime) -> tuple[datetime, datetime]:
    """Return (start_dt, end_dt) for the 7-day Thu-Wed Attendo period containing now_dt."""
    days_since_thu = (now_dt.weekday() - 3) % 7
    p_start = (now_dt - timedelta(days=days_since_thu)).replace(
        hour=0, minute=0, second=0, microsecond=0
    )
    p_end = p_start + timedelta(days=6)
    return p_start, p_end


def compute_window_totals(
    sessions: dict[str, Any],
    current_key: str | None,
    win_start: float,
    win_end: float,
    now_ts: float,
    baselines: dict[str, Any] | None = None,
) -> tuple[float, float, float, int]:
    """Return (net_sec, locked_sec, gross_sec, session_count) overlapping [win_start, win_end]."""
    total_gross = 0.0
    total_locked = 0.0
    count = 0

    for key, rec in sessions.items():
        s_start = float(rec["start_ts"])
        if key == current_key and not rec.get("closed"):
            s_end = now_ts
        else:
            s_end = float(rec.get("end_ts") or rec.get("last_seen") or s_start)

        a = max(s_start, win_start)
        b = min(s_end, win_end)
        if b <= a:
            continue

        count += 1
        gross = b - a
        locked, _ = normalize_and_sum_locks(rec.get("intervals", []), a, b, s_end)
        total_gross += gross
        total_locked += min(locked, gross)

    base_sec = 0.0
    if baselines:
        for entry in baselines.values():
            b_ts = float(entry.get("ts", 0.0))
            if win_start <= b_ts <= win_end:
                base_sec += float(entry.get("net_sec", 0.0))

    total_net = max(0.0, total_gross - total_locked) + base_sec
    return total_net, total_locked, total_gross + base_sec, count


def compute_session_stats(rec: dict[str, Any], is_current: bool, now_ts: float) -> dict[str, Any]:
    start_ts = float(rec["start_ts"])
    end_ts = now_ts if (is_current and not rec.get("closed")) else float(
        rec.get("end_ts") or rec.get("last_seen") or start_ts
    )
    gross = max(0.0, end_ts - start_ts)
    locked, lock_count = normalize_and_sum_locks(rec.get("intervals", []), start_ts, end_ts, end_ts)
    locked = min(locked, gross)
    net = max(0.0, gross - locked)
    return {
        "host": rec["host"],
        "session_id": rec["session_id"],
        "start_ts": start_ts,
        "end_ts": end_ts,
        "live": bool(is_current and not rec.get("closed")),
        "locked_now": bool(is_current and rec.get("locked") and not rec.get("closed")),
        "gross_sec": gross,
        "locked_sec": locked,
        "net_sec": net,
        "lock_count": lock_count,
        "intervals": rec.get("intervals", []),
    }


def fmt_hms(seconds: float) -> str:
    secs = max(0, int(round(seconds)))
    h, rem = divmod(secs, 3600)
    m, s = divmod(rem, 60)
    return f"{h:02d}:{m:02d}:{s:02d}"


def fmt_dec_hours(seconds: float) -> str:
    return f"{seconds / 3600.0:.2f}h"


def fmt_dt(ts: float) -> str:
    return datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M:%S")


def fmt_time(ts: float) -> str:
    return datetime.fromtimestamp(ts).strftime("%H:%M:%S")


def set_baselines(
    seed_today: str | None = None,
    calibrate_live: str | None = None,
    seed_period: str | None = None,
    clear_baselines: bool = False,
) -> None:
    """Persist optional pre-install Attendo baseline offsets inside sessions.json."""
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    now_ts = time.time()
    now_dt = datetime.fromtimestamp(now_ts).astimezone()
    day_start = now_dt.replace(hour=0, minute=0, second=0, microsecond=0).timestamp()
    period_start_dt, _ = attendo_period_bounds(now_dt)
    day_key = f"day:{now_dt.strftime('%Y-%m-%d')}"
    period_key = f"period_prior:{period_start_dt.strftime('%Y-%m-%d')}"

    with open(LOCK_FILE_PATH, "w", encoding="utf-8") as lock_fh:
        fcntl.flock(lock_fh, fcntl.LOCK_EX)
        try:
            ledger = load_ledger_locked()
            baselines: dict[str, Any] = ledger.setdefault("baselines", {})
            if clear_baselines:
                ledger["baselines"] = {}
            else:
                if seed_today is not None:
                    baselines[day_key] = {
                        "ts": day_start + 1.0,
                        "net_sec": parse_duration_arg(seed_today),
                        "note": f"Seeded earlier-today hours ({seed_today})",
                    }
                if calibrate_live is not None:
                    target_sec = parse_duration_arg(calibrate_live)
                    other_bases = {k: v for k, v in baselines.items() if k != day_key}
                    _, current_key = update_ledger_preview(ledger, now_ts)
                    tracked_net, _, _, _ = compute_window_totals(
                        ledger.get("sessions", {}),
                        current_key,
                        day_start,
                        now_ts,
                        now_ts,
                        other_bases,
                    )
                    offset = max(0.0, target_sec - tracked_net)
                    baselines[day_key] = {
                        "ts": day_start + 1.0,
                        "net_sec": offset,
                        "note": f"Calibrated from Attendo live {calibrate_live}",
                    }
                if seed_period is not None:
                    baselines[period_key] = {
                        "ts": period_start_dt.timestamp() + 1.0,
                        "net_sec": parse_duration_arg(seed_period),
                        "note": f"Seeded prior-days period hours ({seed_period})",
                    }
            save_ledger_atomic(ledger)
        finally:
            fcntl.flock(lock_fh, fcntl.LOCK_UN)


def update_ledger_preview(ledger: dict[str, Any], now_ts: float) -> tuple[dict[str, Any], str | None]:
    """Identify the active session key in an already-loaded ledger."""
    current = get_current_session()
    if current is None:
        return ledger, None
    key = f"{current['host']}|{current['session_id']}|{int(current['start_ts'])}"
    return ledger, key if key in ledger.get("sessions", {}) else None


def render_dashboard(ledger: dict[str, Any], current_key: str | None, audit: bool = False) -> str:
    now_ts = time.time()
    now_dt = datetime.fromtimestamp(now_ts).astimezone()
    day_start = now_dt.replace(hour=0, minute=0, second=0, microsecond=0).timestamp()
    period_start_dt, period_end_dt = attendo_period_bounds(now_dt)
    period_start = period_start_dt.timestamp()
    week_start = (now_dt - timedelta(days=now_dt.weekday())).replace(
        hour=0, minute=0, second=0, microsecond=0
    ).timestamp()
    month_start = now_dt.replace(day=1, hour=0, minute=0, second=0, microsecond=0).timestamp()

    sessions = ledger.get("sessions", {})
    baselines = ledger.get("baselines", {})

    c_reset = "\033[0m"
    c_bold = "\033[1m"
    c_cyan = "\033[1;36m"
    c_green = "\033[1;32m"
    c_yellow = "\033[1;33m"
    c_red = "\033[1;31m"
    c_dim = "\033[2m"

    lines: list[str] = []
    lines.append(f"{c_cyan}{c_bold}42 LIVE-ESTIMATE COUNTER{c_reset}  {c_dim}({now_dt.strftime('%Y-%m-%d %H:%M:%S %Z')}){c_reset}")
    lines.append("=" * 68)

    if current_key and current_key in sessions:
        cur = compute_session_stats(sessions[current_key], True, now_ts)
        status = f"{c_red}LOCKED (paused){c_reset}" if cur["locked_now"] else f"{c_green}ACTIVE (counting){c_reset}"
        lines.append(
            f"{c_bold}Current Session:{c_reset} {cur['host']} [{cur['session_id']}]  •  Status: {status}"
        )
        lines.append(
            f"  Login:  {fmt_dt(cur['start_ts'])}"
        )
        lines.append(
            f"  {c_green}{c_bold}Net Active:{c_reset} {c_green}{c_bold}{fmt_hms(cur['net_sec'])}{c_reset} ({fmt_dec_hours(cur['net_sec'])})"
            f"  |  Gross: {fmt_hms(cur['gross_sec'])}"
            f"  |  {c_yellow}Locked: {fmt_hms(cur['locked_sec'])}{c_reset} ({cur['lock_count']}x)"
        )
    else:
        lines.append(f"{c_yellow}Current Session: No active graphical X11 session detected.{c_reset}")

    lines.append("-" * 68)
    period_label = f"Period ({period_start_dt.strftime('%b %d')}-{period_end_dt.strftime('%b %d')})"
    for label, w_start in (
        ("Today              ", day_start),
        (f"{period_label:<19}", period_start),
        ("This Week (Mon-Sun)", week_start),
        ("This Month         ", month_start),
    ):
        net_s, lock_s, gross_s, cnt = compute_window_totals(
            sessions, current_key, w_start, now_ts, now_ts, baselines
        )
        extra = ""
        if w_start == period_start:
            rem_h = max(0.0, 30.0 - net_s / 3600.0)
            extra = f"  {c_dim}({rem_h:.2f}h left of 30h){c_reset}"
        else:
            extra = f"  {c_dim}({cnt} sess){c_reset}"
        lines.append(
            f"{c_bold}{label}:{c_reset} {c_green}{fmt_hms(net_s)}{c_reset} ({fmt_dec_hours(net_s):>6})"
            f"  |  Gross: {fmt_hms(gross_s)}"
            f"  |  Locked: {c_yellow}{fmt_hms(lock_s)}{c_reset}"
            f"{extra}"
        )

    ordered = sorted(sessions.items(), key=lambda kv: float(kv[1]["start_ts"]), reverse=True)
    if ordered:
        lines.append("-" * 68)
        limit = len(ordered) if audit else 8
        title = "All Recorded Sessions (Audit)" if audit else f"Recent Sessions (last {min(limit, len(ordered))})"
        lines.append(f"{c_bold}{title}:{c_reset}")
        lines.append(f"  {'Date':<10} {'Host':<16} {'Start':<8} {'End':<8} {'Net':>8} {'Locked':>8} {'Gross':>8}")
        for key, rec in ordered[:limit]:
            st = compute_session_stats(rec, key == current_key, now_ts)
            date_str = datetime.fromtimestamp(st["start_ts"]).strftime("%Y-%m-%d")
            end_str = "LIVE" if st["live"] else fmt_time(st["end_ts"])
            host_short = st["host"].split(".")[0]
            lines.append(
                f"  {date_str:<10} {host_short:<16} {fmt_time(st['start_ts']):<8} {end_str:<8} "
                f"{fmt_hms(st['net_sec']):>8} {fmt_hms(st['locked_sec']):>8} {fmt_hms(st['gross_sec']):>8}"
            )
            if audit and st["intervals"]:
                for iv_s, iv_e in st["intervals"]:
                    eff_e = iv_e if iv_e is not None else st["end_ts"]
                    dur = max(0.0, eff_e - iv_s)
                    tag = "OPEN" if iv_e is None else fmt_time(eff_e)
                    lines.append(f"      lock: {fmt_time(iv_s)} -> {tag} ({fmt_hms(dur)})")

    if baselines:
        lines.append("-" * 68)
        lines.append(f"{c_dim}Seeded pre-tracker baselines:{c_reset}")
        for b_key, b_val in sorted(baselines.items()):
            lines.append(f"  {c_dim}{b_key}: +{fmt_hms(float(b_val.get('net_sec', 0.0)))} ({b_val.get('note', '')}){c_reset}")

    if ordered:
        first_ts = float(ordered[-1][1]["start_ts"])
        lines.append(f"\n{c_dim}Tracked in {LEDGER_PATH} since {fmt_dt(first_ts)}{c_reset}")
    return "\n".join(lines)


def build_json_summary(ledger: dict[str, Any], current_key: str | None) -> dict[str, Any]:
    now_ts = time.time()
    now_dt = datetime.fromtimestamp(now_ts).astimezone()
    day_start = now_dt.replace(hour=0, minute=0, second=0, microsecond=0).timestamp()
    period_start_dt, period_end_dt = attendo_period_bounds(now_dt)
    period_start = period_start_dt.timestamp()
    week_start = (now_dt - timedelta(days=now_dt.weekday())).replace(
        hour=0, minute=0, second=0, microsecond=0
    ).timestamp()
    month_start = now_dt.replace(day=1, hour=0, minute=0, second=0, microsecond=0).timestamp()
    sessions = ledger.get("sessions", {})
    baselines = ledger.get("baselines", {})

    cur_stats = None
    if current_key and current_key in sessions:
        cur_stats = compute_session_stats(sessions[current_key], True, now_ts)

    def pack(w_start: float) -> dict[str, Any]:
        net_s, lock_s, gross_s, cnt = compute_window_totals(
            sessions, current_key, w_start, now_ts, now_ts, baselines
        )
        return {
            "net_seconds": round(net_s, 2),
            "net_hours": round(net_s / 3600.0, 4),
            "locked_seconds": round(lock_s, 2),
            "gross_seconds": round(gross_s, 2),
            "sessions": cnt,
        }

    return {
        "now": now_ts,
        "current_session": cur_stats,
        "today": pack(day_start),
        "period": {
            "start": period_start_dt.strftime("%Y-%m-%d"),
            "end": period_end_dt.strftime("%Y-%m-%d"),
            **pack(period_start),
        },
        "week": pack(week_start),
        "month": pack(month_start),
        "baselines": baselines,
        "ledger_path": str(LEDGER_PATH),
    }


def watch_loop() -> None:
    """Live 1-second refreshing terminal counter."""
    last_poll = 0.0
    ledger: dict[str, Any] = {"sessions": {}}
    current_key: str | None = None
    try:
        sys.stdout.write("\033[?1049h\033[?25l")
        sys.stdout.flush()
        while True:
            now_m = time.monotonic()
            if now_m - last_poll >= 2.0:
                ledger, current_key = update_ledger(closing=False)
                last_poll = now_m
            output = render_dashboard(ledger, current_key, audit=False)
            sys.stdout.write("\033[H\033[J" + output + "\n\n\033[2mLive updating (Ctrl+C to exit)...\033[0m\n")
            sys.stdout.flush()
            time.sleep(1.0)
    except KeyboardInterrupt:
        pass
    finally:
        sys.stdout.write("\033[?25h\033[?1049l")
        sys.stdout.flush()


def main() -> int:
    parser = argparse.ArgumentParser(description="Live-estimate 42 active hours counter.")
    parser.add_argument("--record", action="store_true", help="Update ledger silently and exit.")
    parser.add_argument("--closing", action="store_true", help="Mark current session closed at logout.")
    parser.add_argument("-w", "--watch", action="store_true", help="Run live 1-second ticking counter.")
    parser.add_argument("-a", "--audit", action="store_true", help="Show all sessions and lock intervals.")
    parser.add_argument("-s", "--short", action="store_true", help="Print compact one-line status.")
    parser.add_argument("--json", action="store_true", help="Print JSON summary.")
    parser.add_argument("--seed-today", metavar="HH:MM", help="Add earlier pre-tracker net hours for today (e.g. 02:00).")
    parser.add_argument("--calibrate-live", metavar="HH:MM", help="Compute today's pre-tracker offset from Attendo Live estimate (e.g. 02:58).")
    parser.add_argument("--seed-period", metavar="HH:MM", help="Add prior completed days in current 7-day period (e.g. 11:00).")
    parser.add_argument("--clear-baselines", action="store_true", help="Remove all seeded baselines.")
    args = parser.parse_args()

    ledger, current_key = update_ledger(closing=args.closing)
    if any(x is not None for x in (args.seed_today, args.calibrate_live, args.seed_period)) or args.clear_baselines:
        set_baselines(
            seed_today=args.seed_today,
            calibrate_live=args.calibrate_live,
            seed_period=args.seed_period,
            clear_baselines=args.clear_baselines,
        )
        ledger, current_key = update_ledger(closing=False)

    if args.record:
        return 0
    if args.watch:
        watch_loop()
        return 0
    if args.json:
        print(json.dumps(build_json_summary(ledger, current_key), indent=2))
        return 0
    if args.short:
        now_ts = time.time()
        day_start = datetime.fromtimestamp(now_ts).astimezone().replace(
            hour=0, minute=0, second=0, microsecond=0
        ).timestamp()
        day_net, day_lock, _, _ = compute_window_totals(
            ledger.get("sessions", {}),
            current_key,
            day_start,
            now_ts,
            now_ts,
            ledger.get("baselines", {}),
        )
        if current_key and current_key in ledger["sessions"]:
            cur = compute_session_stats(ledger["sessions"][current_key], True, now_ts)
            state = "LOCKED" if cur["locked_now"] else "ACTIVE"
            print(
                f"[{state}] session={fmt_hms(cur['net_sec'])} ({fmt_dec_hours(cur['net_sec'])}) "
                f"| today={fmt_hms(day_net)} ({fmt_dec_hours(day_net)}) | locked={fmt_hms(day_lock)}"
            )
        else:
            print(f"[NO SESSION] today={fmt_hms(day_net)} ({fmt_dec_hours(day_net)}) | locked={fmt_hms(day_lock)}")
        return 0

    print(render_dashboard(ledger, current_key, audit=args.audit))
    return 0


if __name__ == "__main__":
    sys.exit(main())
PYEOF

chmod +x "$SCRIPT_PATH"
ln -sf live_estimate.py "$BIN_DIR/live-estimate"

cat > "$SYSTEMD_USER_DIR/live-estimate.service" << 'EOF'
[Unit]
Description=42 Live-Estimate Active Time Recorder

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 %h/.local/bin/live_estimate.py --record
EOF

cat > "$SYSTEMD_USER_DIR/live-estimate.timer" << 'EOF'
[Unit]
Description=42 Live-Estimate Active Time Recorder Timer

[Timer]
OnStartupSec=5s
OnUnitActiveSec=30s
AccuracySec=5s
Unit=live-estimate.service

[Install]
WantedBy=timers.target
EOF

cat > "$SYSTEMD_USER_DIR/live-estimate-logout.service" << 'EOF'
[Unit]
Description=42 Live-Estimate Session End Recorder

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/python3 %h/.local/bin/live_estimate.py --record
ExecStop=/usr/bin/python3 %h/.local/bin/live_estimate.py --record --closing

[Install]
WantedBy=default.target
EOF

for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$rc" ] || [ "$rc" = "$HOME/.bashrc" ] || [[ "${SHELL:-}" == *zsh ]]; then
        touch "$rc"
        if ! grep -qF '# >>> live-estimate-path >>>' "$rc"; then
            cat >> "$rc" << 'EOF'
# >>> live-estimate-path >>>
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
# <<< live-estimate-path <<<
EOF
        fi
    fi
done

if command -v fish >/dev/null 2>&1 || [ -d "$HOME/.config/fish" ]; then
    fish -c 'fish_add_path -g ~/.local/bin' >/dev/null 2>&1 || true
fi

systemctl --user daemon-reload
systemctl --user enable --now live-estimate.timer live-estimate-logout.service

"$BIN_DIR/live-estimate"
echo
echo "Installed! Reload your shell (source ~/.zshrc or ~/.bashrc) then run: live-estimate -w"
