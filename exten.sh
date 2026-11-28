#!/usr/bin/env bash
set -euo pipefail

EXT_DIR="$HOME/.local/share/live-estimate-brave-ext"
BIN_DIR="$HOME/.local/bin"
HOST_BIN="$BIN_DIR/live_estimate_nm_host.py"
HOST_NAME="com.mrbib.live_estimate"
BRAVE_NM_DIR="$HOME/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts"

mkdir -p "$EXT_DIR" "$BIN_DIR" "$BRAVE_NM_DIR"

# 1. Pre-calculate deterministic Chromium/Brave unpacked extension ID from EXT_DIR path
EXT_ID=$(python3 -c '
import hashlib, sys
digest = hashlib.sha256(sys.argv[1].encode("utf-8")).hexdigest()[:32]
print("".join(chr(ord("a") + int(c, 16)) for c in digest))
' "$EXT_DIR")

# 2. Write manifest.json
cat > "$EXT_DIR/manifest.json" << 'EOF'
{
  "manifest_version": 3,
  "name": "42 Live-Estimate Counter",
  "version": "1.0.0",
  "description": "Displays live active session and Attendo period hours from live-estimate.",
  "permissions": ["nativeMessaging"],
  "action": {
    "default_popup": "popup.html",
    "default_title": "42 Live-Estimate"
  }
}
EOF

# 3. Write popup.html
cat > "$EXT_DIR/popup.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>42 Live-Estimate</title>
  <link rel="stylesheet" href="popup.css" />
</head>
<body>
  <div class="container">
    <header class="header">
      <div class="title-group">
        <span class="badge-42">42</span>
        <h1>Live-Estimate</h1>
      </div>
      <button id="refresh-btn" title="Refresh">↻</button>
    </header>

    <div id="error-box" class="error-box hidden"></div>

    <section class="card session-card">
      <div class="row-between">
        <span class="label">Current Session</span>
        <span id="session-status" class="status-pill">--</span>
      </div>
      <div id="session-host" class="sub-meta">--</div>
      <div class="hero-metric" id="session-net">00:00:00</div>
      <div class="sub-row">
        <span>Gross: <strong id="session-gross">00:00:00</strong></span>
        <span>Locked: <strong id="session-locked">00:00:00</strong></span>
      </div>
    </section>

    <section class="card period-card">
      <div class="row-between">
        <span class="label">Attendo Period <span id="period-dates" class="muted"></span></span>
        <span id="period-pct" class="accent-text">0%</span>
      </div>
      <div class="progress-track">
        <div id="period-bar" class="progress-fill" style="width: 0%"></div>
      </div>
      <div class="row-between period-stats">
        <span>Net: <strong id="period-net">00:00:00</strong> (<span id="period-hours">0.00h</span>)</span>
        <span class="muted"><span id="period-left">30.00h</span> left</span>
      </div>
    </section>

    <section class="grid-3">
      <div class="mini-card">
        <span class="mini-label">Today</span>
        <span class="mini-val" id="today-net">00:00:00</span>
        <span class="mini-sub" id="today-hours">0.00h</span>
      </div>
      <div class="mini-card">
        <span class="mini-label">Week</span>
        <span class="mini-val" id="week-net">00:00:00</span>
        <span class="mini-sub" id="week-hours">0.00h</span>
      </div>
      <div class="mini-card">
        <span class="mini-label">Month</span>
        <span class="mini-val" id="month-net">00:00:00</span>
        <span class="mini-sub" id="month-hours">0.00h</span>
      </div>
    </section>
  </div>

  <script src="popup.js"></script>
</body>
</html>
EOF

# 4. Write popup.css
cat > "$EXT_DIR/popup.css" << 'EOF'
:root {
  --bg: #0d1117;
  --surface: #161b22;
  --border: #262c36;
  --text: #e6edf3;
  --muted: #8b949e;
  --green: #3fb950;
  --green-dim: rgba(63, 185, 80, 0.15);
  --red: #f85149;
  --red-dim: rgba(248, 81, 73, 0.15);
  --cyan: #58a6ff;
}

* {
  box-sizing: border-box;
  margin: 0;
  padding: 0;
}

body {
  width: 340px;
  background-color: var(--bg);
  color: var(--text);
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  font-size: 13px;
  padding: 14px;
}

.container {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.title-group {
  display: flex;
  align-items: center;
  gap: 8px;
}

.badge-42 {
  background: var(--text);
  color: var(--bg);
  font-weight: 800;
  font-size: 11px;
  padding: 2px 5px;
  border-radius: 4px;
}

h1 {
  font-size: 15px;
  font-weight: 600;
  letter-spacing: -0.2px;
}

#refresh-btn {
  background: var(--surface);
  color: var(--text);
  border: 1px solid var(--border);
  border-radius: 6px;
  width: 28px;
  height: 28px;
  cursor: pointer;
  font-size: 15px;
  transition: border-color 0.15s;
}

#refresh-btn:hover {
  border-color: var(--cyan);
}

.card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 12px;
}

.row-between {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.label {
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  color: var(--muted);
  font-weight: 600;
}

.status-pill {
  font-size: 10px;
  font-weight: 700;
  padding: 2px 7px;
  border-radius: 999px;
}

.status-active {
  background: var(--green-dim);
  color: var(--green);
}

.status-locked {
  background: var(--red-dim);
  color: var(--red);
}

.sub-meta {
  font-size: 11px;
  color: var(--muted);
  margin-top: 2px;
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
}

.hero-metric {
  font-size: 26px;
  font-weight: 700;
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  color: var(--green);
  margin: 6px 0;
}

.sub-row {
  display: flex;
  justify-content: space-between;
  font-size: 11px;
  color: var(--muted);
}

.sub-row strong {
  color: var(--text);
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
}

.progress-track {
  width: 100%;
  height: 6px;
  background: var(--bg);
  border-radius: 999px;
  overflow: hidden;
  margin: 8px 0;
}

.progress-fill {
  height: 100%;
  background: var(--cyan);
  border-radius: 999px;
  transition: width 0.3s ease;
}

.period-stats {
  font-size: 11px;
}

.accent-text {
  color: var(--cyan);
  font-weight: 700;
  font-size: 12px;
}

.muted {
  color: var(--muted);
}

.grid-3 {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 8px;
}

.mini-card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 9px 8px;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 3px;
}

.mini-label {
  font-size: 10px;
  text-transform: uppercase;
  color: var(--muted);
  font-weight: 600;
}

.mini-val {
  font-size: 12px;
  font-weight: 700;
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
}

.mini-sub {
  font-size: 11px;
  color: var(--cyan);
}

.error-box {
  background: var(--red-dim);
  border: 1px solid var(--red);
  color: var(--red);
  padding: 8px 10px;
  border-radius: 6px;
  font-size: 11px;
  line-height: 1.4;
}

.hidden {
  display: none;
}
EOF

# 5. Write popup.js
cat > "$EXT_DIR/popup.js" << 'EOF'
const HOST_NAME = "com.mrbib.live_estimate";

function fmtHms(totalSec) {
  const secs = Math.max(0, Math.round(totalSec || 0));
  const h = Math.floor(secs / 3600);
  const m = Math.floor((secs % 3600) / 60);
  const s = secs % 60;
  return [h, m, s].map((v) => String(v).padStart(2, "0")).join(":");
}

function fmtHours(totalSec) {
  return `${((totalSec || 0) / 3600).toFixed(2)}h`;
}

function showError(msg) {
  const box = document.getElementById("error-box");
  box.textContent = msg;
  box.classList.remove("hidden");
}

function clearError() {
  const box = document.getElementById("error-box");
  box.textContent = "";
  box.classList.add("hidden");
}

function renderData(data) {
  clearError();

  const cur = data.current_session;
  const statusEl = document.getElementById("session-status");
  if (cur) {
    statusEl.textContent = cur.locked_now ? "LOCKED" : "ACTIVE";
    statusEl.className = `status-pill ${cur.locked_now ? "status-locked" : "status-active"}`;
    document.getElementById("session-host").textContent = `${cur.host} [${cur.session_id}]`;
    document.getElementById("session-net").textContent = fmtHms(cur.net_sec);
    document.getElementById("session-gross").textContent = fmtHms(cur.gross_sec);
    document.getElementById("session-locked").textContent = fmtHms(cur.locked_sec);
  } else {
    statusEl.textContent = "OFFLINE";
    statusEl.className = "status-pill status-locked";
    document.getElementById("session-host").textContent = "No active X11 session";
    document.getElementById("session-net").textContent = "00:00:00";
  }

  const p = data.period || {};
  const pNet = p.net_seconds || 0;
  const pHours = pNet / 3600;
  const pct = Math.min(100, (pHours / 30) * 100);
  const left = Math.max(0, 30 - pHours);

  document.getElementById("period-dates").textContent =
    p.start && p.end ? `(${p.start.slice(5)} → ${p.end.slice(5)})` : "";
  document.getElementById("period-pct").textContent = `${pct.toFixed(0)}%`;
  document.getElementById("period-bar").style.width = `${pct}%`;
  document.getElementById("period-net").textContent = fmtHms(pNet);
  document.getElementById("period-hours").textContent = `${pHours.toFixed(2)}h`;
  document.getElementById("period-left").textContent = `${left.toFixed(2)}h`;

  for (const key of ["today", "week", "month"]) {
    const sec = data[key]?.net_seconds || 0;
    document.getElementById(`${key}-net`).textContent = fmtHms(sec);
    document.getElementById(`${key}-hours`).textContent = fmtHours(sec);
  }
}

function fetchStats() {
  chrome.runtime.sendNativeMessage(HOST_NAME, { cmd: "status" }, (response) => {
    if (chrome.runtime.lastError) {
      showError(`Native host error: ${chrome.runtime.lastError.message}`);
      return;
    }
    if (!response || response.error) {
      showError(response?.error || "Empty response from live-estimate.");
      return;
    }
    renderData(response);
  });
}

document.getElementById("refresh-btn").addEventListener("click", fetchStats);
document.addEventListener("DOMContentLoaded", fetchStats);
EOF

# 6. Install Python Native Messaging host
cat > "$HOST_BIN" << 'PYEOF'
#!/usr/bin/env python3
import json
import struct
import subprocess
import sys
from pathlib import Path

def read_message():
    raw_len = sys.stdin.buffer.read(4)
    if not raw_len:
        return None
    msg_len = struct.unpack("<I", raw_len)[0]
    data = sys.stdin.buffer.read(msg_len).decode("utf-8")
    return json.loads(data)

def send_message(payload):
    encoded = json.dumps(payload).encode("utf-8")
    sys.stdout.buffer.write(struct.pack("<I", len(encoded)))
    sys.stdout.buffer.write(encoded)
    sys.stdout.buffer.flush()

def main():
    _ = read_message()
    script = Path.home() / ".local" / "bin" / "live_estimate.py"
    try:
        res = subprocess.run(
            ["/usr/bin/python3", str(script), "--json"],
            capture_output=True,
            text=True,
            timeout=5,
            check=True,
        )
        send_message(json.loads(res.stdout))
    except Exception as exc:
        send_message({"error": str(exc)})

if __name__ == "__main__":
    main()
PYEOF

chmod +x "$HOST_BIN"

# 7. Register Native Messaging manifest with Brave
cat > "$BRAVE_NM_DIR/$HOST_NAME.json" << EOF
{
  "name": "$HOST_NAME",
  "description": "Native messaging bridge for 42 live-estimate",
  "path": "$HOST_BIN",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://$EXT_ID/"
  ]
}
EOF

echo "========================================================"
echo "Extension created at : $EXT_DIR"
echo "Pre-registered ID    : $EXT_ID"
echo "========================================================"
echo "Next step (one-time in Brave):"
echo "  1. Open brave://extensions"
echo "  2. Enable 'Developer mode' (top-right)"
echo "  3. Click 'Load unpacked' and select: $EXT_DIR"
echo "  4. Pin '42 Live-Estimate Counter' to your toolbar"
