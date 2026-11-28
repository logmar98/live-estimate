#!/usr/bin/env bash
set -euo pipefail

EXT_DIR="$HOME/.local/share/live-estimate-brave-ext"
BIN_DIR="$HOME/.local/bin"
HOST_BIN="$BIN_DIR/live_estimate_nm_host.py"
HOST_NAME="com.mrbib.live_estimate"
BRAVE_NM_DIR="$HOME/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts"

mkdir -p "$EXT_DIR" "$BIN_DIR" "$BRAVE_NM_DIR"

EXT_ID=$(python3 -c '
import hashlib, sys
digest = hashlib.sha256(sys.argv[1].encode("utf-8")).hexdigest()[:32]
print("".join(chr(ord("a") + int(c, 16)) for c in digest))
' "$EXT_DIR")

# 1. manifest.json
cat > "$EXT_DIR/manifest.json" << 'EOF'
{
  "manifest_version": 3,
  "name": "42 Live-Estimate Counter",
  "version": "1.1.0",
  "description": "Displays live Today logtime and Attendo period progress from live-estimate.",
  "permissions": ["nativeMessaging"],
  "action": {
    "default_popup": "popup.html",
    "default_title": "42 Live-Estimate"
  }
}
EOF

# 2. popup.html
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
    <!-- Top Bar -->
    <header class="header">
      <div class="title-group">
        <span class="badge-42">42</span>
        <div>
          <h1>Logtime</h1>
          <span id="host-meta" class="host-meta">connecting...</span>
        </div>
      </div>
      <div class="header-actions">
        <span id="session-pill" class="status-pill status-offline">
          <span class="dot"></span>
          <span id="session-status-text">--</span>
        </span>
        <button id="refresh-btn" title="Sync now" aria-label="Refresh">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
            <path d="M21 12a9 9 0 0 0-9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/>
            <path d="M3 3v5h5"/>
            <path d="M3 12a9 9 0 0 0 9 9 9.75 9.75 0 0 0 6.74-2.74L21 16"/>
            <path d="M16 16h5v5"/>
          </svg>
        </button>
      </div>
    </header>

    <div id="error-box" class="error-box hidden"></div>

    <!-- Hero Card: TODAY -->
    <section class="hero-card">
      <div class="hero-top">
        <span class="section-label">Today's Active Time</span>
        <span id="today-decimal" class="decimal-badge">0.00h</span>
      </div>

      <div class="hero-clock-row">
        <span id="today-net" class="hero-clock">00:00:00</span>
      </div>

      <div class="hero-divider"></div>

      <div class="hero-stats-grid">
        <div class="stat-item">
          <span class="stat-label">Current Sess</span>
          <span id="cur-sess-net" class="stat-val accent-green">00:00:00</span>
        </div>
        <div class="stat-item">
          <span class="stat-label">Gross Today</span>
          <span id="today-gross" class="stat-val">00:00:00</span>
        </div>
        <div class="stat-item">
          <span class="stat-label">Locked</span>
          <span id="today-locked" class="stat-val accent-amber">00:00:00</span>
        </div>
      </div>
    </section>

    <!-- Attendo Period Card -->
    <section class="card">
      <div class="row-between">
        <span class="section-label">Attendo Period <span id="period-dates" class="muted-date"></span></span>
        <span id="period-pct" class="pct-pill">0%</span>
      </div>

      <div class="progress-track">
        <div id="period-bar" class="progress-fill" style="width: 0%"></div>
      </div>

      <div class="row-between period-footer">
        <span><strong id="period-net">00:00:00</strong> <span class="muted">(<span id="period-hours">0.00h</span> / 30h)</span></span>
        <span class="muted"><strong id="period-left" class="text-soft">30.00h</strong> left</span>
      </div>
    </section>

    <!-- Footer Summary Row: Week & Month -->
    <section class="grid-2">
      <div class="mini-card">
        <div class="row-between">
          <span class="mini-label">This Week</span>
          <span id="week-hours" class="mini-hours">0.00h</span>
        </div>
        <span id="week-net" class="mini-clock">00:00:00</span>
      </div>
      <div class="mini-card">
        <div class="row-between">
          <span class="mini-label">This Month</span>
          <span id="month-hours" class="mini-hours">0.00h</span>
        </div>
        <span id="month-net" class="mini-clock">00:00:00</span>
      </div>
    </section>
  </div>

  <script src="popup.js"></script>
</body>
</html>
EOF

# 3. popup.css
cat > "$EXT_DIR/popup.css" << 'EOF'
:root {
  --bg: #090c10;
  --surface: #11161d;
  --surface-elevated: #161d26;
  --border: rgba(255, 255, 255, 0.08);
  --border-highlight: rgba(56, 189, 248, 0.25);
  --text: #f0f6fc;
  --text-soft: #c9d1d9;
  --muted: #7d8590;
  --green: #3fb950;
  --green-bg: rgba(63, 185, 80, 0.12);
  --amber: #d29922;
  --red: #f85149;
  --red-bg: rgba(248, 81, 73, 0.12);
  --cyan: #38bdf8;
  --indigo: #818cf8;
}

* {
  box-sizing: border-box;
  margin: 0;
  padding: 0;
}

body {
  width: 350px;
  background: radial-gradient(circle at top right, #131c2e 0%, var(--bg) 65%);
  color: var(--text);
  font-family: -apple-system, BlinkMacSystemFont, "Inter", "Segoe UI", Roboto, sans-serif;
  font-size: 13px;
  padding: 15px;
  -webkit-font-smoothing: antialiased;
}

.container {
  display: flex;
  flex-direction: column;
  gap: 11px;
}

/* Header */
.header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.title-group {
  display: flex;
  align-items: center;
  gap: 9px;
}

.badge-42 {
  background: linear-gradient(135deg, #ffffff 0%, #cbd5e1 100%);
  color: #090c10;
  font-weight: 900;
  font-size: 12px;
  padding: 4px 6px;
  border-radius: 6px;
  letter-spacing: -0.5px;
  box-shadow: 0 2px 8px rgba(255, 255, 255, 0.12);
}

h1 {
  font-size: 14px;
  font-weight: 700;
  line-height: 1.1;
  letter-spacing: -0.2px;
}

.host-meta {
  display: block;
  font-size: 10.5px;
  color: var(--muted);
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  margin-top: 2px;
}

.header-actions {
  display: flex;
  align-items: center;
  gap: 7px;
}

.status-pill {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.4px;
  padding: 3px 8px;
  border-radius: 999px;
  border: 1px solid transparent;
}

.dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: currentColor;
}

.status-active {
  background: var(--green-bg);
  color: var(--green);
  border-color: rgba(63, 185, 80, 0.25);
}

.status-active .dot {
  animation: pulse 1.8s infinite ease-in-out;
}

.status-locked, .status-offline {
  background: var(--red-bg);
  color: var(--red);
  border-color: rgba(248, 81, 73, 0.25);
}

@keyframes pulse {
  0%, 100% { opacity: 1; transform: scale(1); }
  50% { opacity: 0.4; transform: scale(0.85); }
}

#refresh-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  background: var(--surface);
  color: var(--text-soft);
  border: 1px solid var(--border);
  border-radius: 7px;
  width: 28px;
  height: 28px;
  cursor: pointer;
  transition: all 0.15s ease;
}

#refresh-btn:hover {
  border-color: var(--cyan);
  color: var(--cyan);
  background: var(--surface-elevated);
}

#refresh-btn.spinning svg {
  animation: spin 0.5s linear;
}

@keyframes spin {
  from { transform: rotate(0deg); }
  to { transform: rotate(360deg); }
}

/* Hero Card (Today) */
.hero-card {
  background: linear-gradient(180deg, rgba(22, 29, 38, 0.95) 0%, rgba(15, 20, 27, 0.98) 100%);
  border: 1px solid var(--border-highlight);
  border-radius: 12px;
  padding: 14px;
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.35), inset 0 1px 0 rgba(255, 255, 255, 0.06);
}

.hero-top {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.section-label {
  font-size: 10.5px;
  text-transform: uppercase;
  letter-spacing: 0.6px;
  color: var(--muted);
  font-weight: 700;
}

.decimal-badge {
  background: rgba(56, 189, 248, 0.12);
  color: var(--cyan);
  border: 1px solid rgba(56, 189, 248, 0.25);
  font-size: 11px;
  font-weight: 700;
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  padding: 2px 7px;
  border-radius: 6px;
}

.hero-clock-row {
  margin: 8px 0 10px;
}

.hero-clock {
  font-size: 34px;
  font-weight: 800;
  letter-spacing: -0.5px;
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  background: linear-gradient(180deg, #ffffff 20%, #a5f3fc 100%);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  line-height: 1.05;
}

.hero-divider {
  height: 1px;
  background: var(--border);
  margin-bottom: 10px;
}

.hero-stats-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 8px;
}

.stat-item {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.stat-label {
  font-size: 10px;
  color: var(--muted);
}

.stat-val {
  font-size: 12px;
  font-weight: 600;
  color: var(--text-soft);
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
}

.accent-green { color: var(--green); }
.accent-amber { color: var(--amber); }

/* Standard Card */
.card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 10px;
  padding: 12px;
}

.row-between {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.muted-date {
  font-weight: 500;
  text-transform: none;
  letter-spacing: 0;
  color: var(--muted);
}

.pct-pill {
  font-size: 11px;
  font-weight: 700;
  color: var(--cyan);
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
}

.progress-track {
  width: 100%;
  height: 7px;
  background: #080a0e;
  border-radius: 999px;
  overflow: hidden;
  margin: 8px 0;
  border: 1px solid rgba(255, 255, 255, 0.04);
}

.progress-fill {
  height: 100%;
  background: linear-gradient(90deg, var(--cyan) 0%, var(--indigo) 100%);
  border-radius: 999px;
  transition: width 0.4s cubic-bezier(0.22, 1, 0.36, 1);
}

.progress-fill.complete {
  background: linear-gradient(90deg, #2ea043 0%, #3fb950 100%);
}

.period-footer {
  font-size: 11px;
}

.period-footer strong {
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
}

.muted { color: var(--muted); }
.text-soft { color: var(--text-soft); }

/* Bottom 2-col Grid */
.grid-2 {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 9px;
}

.mini-card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 10px;
  padding: 10px 12px;
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.mini-label {
  font-size: 10px;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  color: var(--muted);
  font-weight: 700;
}

.mini-hours {
  font-size: 11px;
  font-weight: 700;
  color: var(--cyan);
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
}

.mini-clock {
  font-size: 14px;
  font-weight: 700;
  color: var(--text);
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
}

.error-box {
  background: var(--red-bg);
  border: 1px solid rgba(248, 81, 73, 0.4);
  color: var(--red);
  padding: 8px 10px;
  border-radius: 8px;
  font-size: 11px;
  line-height: 1.4;
}

.hidden {
  display: none;
}
EOF

# 4. popup.js (includes live 1-second tick while popup is open)
cat > "$EXT_DIR/popup.js" << 'EOF'
const HOST_NAME = "com.mrbib.live_estimate";

let lastPayload = null;
let fetchedAtMs = 0;
let tickTimer = null;

function fmtHms(totalSec) {
  const secs = Math.max(0, Math.floor(totalSec || 0));
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

function renderData() {
  if (!lastPayload) return;
  clearError();

  const data = lastPayload;
  const cur = data.current_session;
  const isCounting = Boolean(cur && cur.live && !cur.locked_now);
  const elapsed = isCounting ? (Date.now() - fetchedAtMs) / 1000 : 0;

  // Header status & host
  const pill = document.getElementById("session-pill");
  const statusText = document.getElementById("session-status-text");
  const hostMeta = document.getElementById("host-meta");

  if (cur) {
    const shortHost = cur.host.split(".")[0];
    hostMeta.textContent = `${shortHost} • ${cur.session_id}`;
    if (cur.locked_now) {
      pill.className = "status-pill status-locked";
      statusText.textContent = "LOCKED";
    } else {
      pill.className = "status-pill status-active";
      statusText.textContent = "ACTIVE";
    }
  } else {
    hostMeta.textContent = "no x11 session";
    pill.className = "status-pill status-offline";
    statusText.textContent = "OFFLINE";
  }

  // Hero: Today
  const today = data.today || {};
  const todayNet = (today.net_seconds || 0) + elapsed;
  const todayGross = (today.gross_seconds || 0) + (cur && cur.live ? elapsed : 0);
  const todayLocked = (today.locked_seconds || 0) + (cur && cur.locked_now ? (Date.now() - fetchedAtMs) / 1000 : 0);
  const curNet = cur ? (cur.net_sec || 0) + elapsed : 0;

  document.getElementById("today-net").textContent = fmtHms(todayNet);
  document.getElementById("today-decimal").textContent = fmtHours(todayNet);
  document.getElementById("cur-sess-net").textContent = fmtHms(curNet);
  document.getElementById("today-gross").textContent = fmtHms(todayGross);
  document.getElementById("today-locked").textContent = fmtHms(todayLocked);

  // Period (30h quota)
  const p = data.period || {};
  const pNet = (p.net_seconds || 0) + elapsed;
  const pHours = pNet / 3600;
  const pct = Math.min(100, (pHours / 30) * 100);
  const left = Math.max(0, 30 - pHours);

  document.getElementById("period-dates").textContent =
    p.start && p.end ? `${p.start.slice(5)} → ${p.end.slice(5)}` : "";
  document.getElementById("period-pct").textContent = `${pct.toFixed(0)}%`;
  const bar = document.getElementById("period-bar");
  bar.style.width = `${pct}%`;
  bar.classList.toggle("complete", pHours >= 30);

  document.getElementById("period-net").textContent = fmtHms(pNet);
  document.getElementById("period-hours").textContent = `${pHours.toFixed(2)}h`;
  document.getElementById("period-left").textContent = `${left.toFixed(2)}h`;

  // Week & Month
  for (const key of ["week", "month"]) {
    const sec = (data[key]?.net_seconds || 0) + elapsed;
    document.getElementById(`${key}-net`).textContent = fmtHms(sec);
    document.getElementById(`${key}-hours`).textContent = fmtHours(sec);
  }
}

function fetchStats() {
  const btn = document.getElementById("refresh-btn");
  btn.classList.add("spinning");
  setTimeout(() => btn.classList.remove("spinning"), 500);

  chrome.runtime.sendNativeMessage(HOST_NAME, { cmd: "status" }, (response) => {
    if (chrome.runtime.lastError) {
      showError(`Native host error: ${chrome.runtime.lastError.message}`);
      return;
    }
    if (!response || response.error) {
      showError(response?.error || "Empty response from live-estimate.");
      return;
    }
    lastPayload = response;
    fetchedAtMs = Date.now();
    renderData();
  });
}

document.getElementById("refresh-btn").addEventListener("click", fetchStats);
document.addEventListener("DOMContentLoaded", () => {
  fetchStats();
  tickTimer = setInterval(renderData, 1000);
});
window.addEventListener("unload", () => {
  if (tickTimer) clearInterval(tickTimer);
});
EOF

# 5. Native Messaging host
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

echo "Updated! Go to brave://extensions and click the reload icon (↻) on '42 Live-Estimate Counter'."
