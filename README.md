# 42 Live-Estimate Counter & Brave Extension

Live active session timer, lock-time tracker, and 1337 Attendo / 42 Intra progress tracker for 42 workstations.

It combines:
- **`live-estimate` CLI & systemd recorder** (`~/.local/bin/live_estimate.py`): tracks active X11 workstation sessions and subtracts `ft_lock` intervals read from `/run/42-lock/seat0.json` into `~/.local/share/live_estimate/sessions.json`.
- **42 Chrono Brave Extension + Native Messaging Host** (`~/.local/share/live-estimate-brave-ext` & `~/.local/bin/live_estimate_nm_host.py`): blends local live session tracking with official **1337 Attendo** period data and **42 Intra** location stats, with daily pace ETA, `+35m` rounding preview, session/lock logs, Carbon/Paper themes, and EN/FR/AR support.

---

## Quick Install

Run from the repository root:

```bash
make install
```

This sets up the `live-estimate` CLI, enables the background `systemd` user timer/logout service, deploys the Brave extension and Native Messaging host (`com.mrbib.live_estimate`), backs up any existing `sessions.json` ledger, and prints the Brave extension Add/Update steps.

---

## Add or Update the Brave Extension

### First-time setup (Add extension)
1. Open `brave://extensions` in Brave.
2. Enable **Developer mode** (top-right toggle).
3. Click **Load unpacked** and select:
   ```text
   ~/.local/share/live-estimate-brave-ext
   ```
4. Pin **42 Live-Estimate Counter** from the Extensions toolbar puzzle icon.

### Updating after changes (Update extension)
1. Deploy updated extension files (or run full `make install`):
   ```bash
   make update-ext
   ```
2. Open `brave://extensions` and click the reload icon (`↻`) on **42 Live-Estimate Counter**.

> Existing logs in `~/.local/share/live_estimate/sessions.json` are preserved and backed up to `~/.local/share/live_estimate/backups/sessions.YYYYMMDD-HHMMSS.json` before deployment.

---

## Extension Usage

Open **42 Live-Estimate Counter** from Brave's toolbar. The top navigation strip switches between three views:

### 1. `Today`
- **Chronograph Gauge:** Shows today's effective active time (`hh:mm:ss`), percentage toward today's daily pace target, and the expected rounded Attendo hours (`+35m` rule).
- **Pace Goal & Telemetry:** Displays estimated completion time (`ETA` in `Africa/Casablanca` timezone), current session net time, today's gross time, and locked duration.
- **Day Cadence:** Timeline bar visualizing active and locked intervals across the day.
- **Attendo Period & Campus Dock:** Shows the current official 1337 Attendo period (or Thu–Wed fallback), remaining hours toward the weekly quota, the 7-day progress matrix, and live **42 Intra** / **1337 Attendo** link status.

### 2. `Logs`
- **Week & Month KPIs:** Total net time for the current week and month.
- **Sub-tabs:**
  - **Sessions:** Recent recorded local X11 workstation sessions.
  - **Attendo Days:** Per-day official breakdown when linked to 1337 Attendo.
  - **Lock Events:** Lock intervals recorded for today.

### 3. `Setup`
- **Appearance:** Switch between **Carbon** (dark matte + copper) and **Paper** (light) themes (or use the sun icon in the header).
- **Language:** Switch between **EN**, **FR**, and **AR** (with RTL layout).
- **Campus Linking & Cookie Source:**
  - Log into `https://profile.intra.42.fr/` and `https://attendo.1337.ma/students/login` in your browser, then click **Sync Now** (or select your browser cookie source: `Auto`, `Brave`, `Firefox`, `Chrome`).
  - Optionally set your **42 Login**, customize the **Target (h)** (default `30`), or paste a manual Attendo `student_token`.
  - Click **Save Changes** to persist settings in extension storage.

---

## CLI Usage (`live-estimate`)

After installation, reload your shell (`source ~/.bashrc` or `source ~/.zshrc`) if `~/.local/bin` was just added to `PATH`, then use:

| Command | Description |
| :--- | :--- |
| `live-estimate` | Print full terminal summary dashboard (current session, today, Thu–Wed period, week, month) |
| `live-estimate -w` | Watch mode: live 1-second refreshing dashboard (`Ctrl+C` to exit) |
| `live-estimate -s` | Compact single-line status (`ACTIVE` / `LOCKED` / `NO SESSION`, session, today, locked) |
| `live-estimate -a` | Audit mode: show detailed sessions and lock intervals |
| `live-estimate --json` | Output structured JSON summary |
| `live-estimate --seed-today HH:MM` | Seed pre-tracker active time for today (e.g. `02:00`) |
| `live-estimate --calibrate-live HH:MM` | Calibrate today's pre-tracker offset against Attendo Live time (e.g. `02:58`) |
| `live-estimate --seed-period HH:MM` | Seed prior completed days in the current period (e.g. `11:00`) |
| `live-estimate --clear-baselines` | Clear all seeded baseline adjustments |

---

## Installed Files & Services

| Path / Unit | Purpose |
| :--- | :--- |
| `~/.local/bin/live_estimate.py` (`live-estimate`) | Core CLI and session/lock tracker |
| `~/.local/bin/live_estimate_nm_host.py` | Native Messaging bridge (`com.mrbib.live_estimate`) for Brave |
| `~/.local/share/live-estimate-brave-ext/` | Unpacked Manifest V3 Brave extension files (`manifest.json`, `popup.html`, `popup.css`, `popup.js`) |
| `~/.local/share/live_estimate/sessions.json` | Persistent session and baseline ledger |
| `~/.local/share/live_estimate/backups/` | Automatic timestamped ledger backups created during `update_live_estimate_ext.sh` |
| `~/.local/share/live_estimate/accounts_cache.json` | Short-lived cache for 42 Intra / 1337 Attendo sync |
| `~/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts/com.mrbib.live_estimate.json` | Brave Native Messaging host registration |
| `live-estimate.timer` / `live-estimate-logout.service` | User systemd units recording active/locked time every 30s and on logout |
