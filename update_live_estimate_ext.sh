#!/usr/bin/env bash
set -euo pipefail

# 42 Live-Estimate Brave Extension & Xattendo Fusion Deployment Script
# Idempotent installer/updater for Manifest V3 extension & Native Messaging host
# Guarantees zero data loss, ledger preservation, and automatic schema migration

EXT_DIR="$HOME/.local/share/live-estimate-brave-ext"
BIN_DIR="$HOME/.local/bin"
HOST_BIN="$BIN_DIR/live_estimate_nm_host.py"
HOST_NAME="com.mrbib.live_estimate"
BRAVE_NM_DIR="$HOME/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts"
BRAVE_SNAP_NM_DIR="$HOME/snap/brave/current/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts"
CHROME_NM_DIR="$HOME/.config/google-chrome/NativeMessagingHosts"

DATA_DIR="$HOME/.local/share/live_estimate"
LEDGER_FILE="$DATA_DIR/sessions.json"
BACKUP_DIR="$DATA_DIR/backups"

mkdir -p "$EXT_DIR" "$BIN_DIR" "$BRAVE_NM_DIR" "$DATA_DIR"
if [ -d "$HOME/snap/brave" ]; then
    mkdir -p "$BRAVE_SNAP_NM_DIR"
fi
if [ -d "$HOME/.config/google-chrome" ]; then
    mkdir -p "$CHROME_NM_DIR"
fi

# 1. Zero Data Loss: Backup and verify existing ledger
if [ -f "$LEDGER_FILE" ]; then
    mkdir -p "$BACKUP_DIR"
    TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
    BACKUP_FILE="$BACKUP_DIR/sessions.$TIMESTAMP.json"
    cp -a "$LEDGER_FILE" "$BACKUP_FILE"
    
    SESSION_COUNT=$(python3 -c '
import json, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        data = json.load(f)
    print(len(data.get("sessions", {})))
except Exception:
    print(0)
' "$LEDGER_FILE")
    
    echo "==> Safe Upgrade: Preserved $SESSION_COUNT existing session(s) in sessions.json"
    echo "    Timestamped backup created at: $BACKUP_FILE"
else
    echo "==> Initial Setup: No pre-existing sessions.json ledger detected."
fi

# 2. Deterministic Chromium/Brave unpacked extension ID from EXT_DIR path
EXT_ID=$(python3 -c '
import hashlib, sys
digest = hashlib.sha256(sys.argv[1].encode("utf-8")).hexdigest()[:32]
print("".join(chr(ord("a") + int(c, 16)) for c in digest))
' "$EXT_DIR")

echo "==> Configuring 42 Live-Estimate Brave Extension + Xattendo Fusion..."
echo "    Extension Dir: $EXT_DIR"
echo "    Extension ID : $EXT_ID"
echo "    Host Binary  : $HOST_BIN"

# 3. Write manifest.json
cat > "$EXT_DIR/manifest.json" << 'EOF'
{
  "manifest_version": 3,
  "name": "42 Live-Estimate Counter",
  "version": "3.0.0",
  "description": "42 Logtime & 1337 Attendo live tracker combining local session/lock monitoring with official 42 Intra and Attendo period progress.",
  "permissions": ["nativeMessaging", "storage", "cookies"],
  "host_permissions": [
    "https://*.42.fr/*",
    "https://*.1337.ma/*"
  ],
  "action": {
    "default_popup": "popup.html",
    "default_title": "42 Live-Estimate"
  }
}
EOF

# 4. Write popup.html
cat > "$EXT_DIR/popup.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>42 Chrono · Live-Estimate</title>
  <link rel="stylesheet" href="popup.css" />
</head>
<body data-theme="carbon">
  <div class="atelier-shell">
    <!-- Top Integrated Command Strip -->
    <header class="cmd-bar">
      <div class="cmd-identity">
        <span id="live-beacon" class="beacon idle" aria-hidden="true"></span>
        <div class="id-stack">
          <div class="id-top-row">
            <span id="user-handle" class="user-handle ltr">MRBIB</span>
            <span id="host-chip" class="host-chip ltr">x11</span>
          </div>
          <span id="status-word" class="status-word">IDLE</span>
        </div>
      </div>

      <!-- Top Segmented Navigation (Replaces bottom bar) -->
      <nav class="top-nav" role="tablist" aria-label="Views">
        <button type="button" id="nav-btn-overview" class="top-nav-btn" role="tab" aria-selected="false">
          <span id="nav-lbl-overview">Today</span>
        </button>
        <button type="button" id="nav-btn-sessions" class="top-nav-btn" role="tab" aria-selected="false">
          <span id="nav-lbl-sessions">Logs</span>
        </button>
        <button type="button" id="nav-btn-settings" class="top-nav-btn" role="tab" aria-selected="false">
          <span id="nav-lbl-settings">Setup</span>
        </button>
      </nav>

      <div class="cmd-tools">
        <button type="button" id="theme-quick-btn" class="tool-btn" title="Switch Carbon / Paper Theme" aria-label="Toggle theme">
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <circle cx="12" cy="12" r="4"/>
            <path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M6.34 17.66l-1.41 1.41M19.07 4.93l-1.41 1.41"/>
          </svg>
        </button>
        <button type="button" id="refresh-btn" class="tool-btn" title="Sync now" aria-label="Refresh">
          <svg id="refresh-icon" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round">
            <path d="M21 12a9 9 0 0 0-9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/>
            <path d="M3 3v5h5"/>
            <path d="M3 12a9 9 0 0 0 9 9 9.75 9.75 0 0 0 6.74-2.74L21 16"/>
            <path d="M16 16h5v5"/>
          </svg>
        </button>
      </div>
    </header>

    <main class="stage">
      <div id="error-box" class="alert-banner hidden" role="alert"></div>

      <!-- ================================================================= -->
      <!-- VIEW 1: TODAY (Asymmetric Split Chronograph + Horizon Matrix)     -->
      <!-- ================================================================= -->
      <section id="page-overview" class="view-panel hidden" role="tabpanel">
        <!-- Split Asymmetric Hero Deck -->
        <div class="hero-deck" id="hero-panel">
          <!-- Left: Circular Precision Chronograph Gauge -->
          <div class="chrono-dial-card">
            <div class="dial-wrapper ltr" id="hero-ring-wrap">
              <svg class="chrono-svg" viewBox="0 0 140 140" aria-hidden="true">
                <!-- Outer tick track -->
                <circle class="dial-ticks" cx="70" cy="70" r="62" />
                <circle class="dial-track" cx="70" cy="70" r="54" />
                <circle id="hero-ring-arc" class="dial-arc" cx="70" cy="70" r="54" stroke-dasharray="339.29" stroke-dashoffset="339.29" />
              </svg>
              <div class="dial-center">
                <span class="dial-kicker" id="lbl-hero-title">ACTIVE</span>
                <span id="hero-clock" class="dial-time tabular">00:00:00</span>
                <div class="dial-badges">
                  <span id="hero-ring-pct" class="dial-pct tabular">0%</span>
                  <span id="hero-rounding-chip" class="dial-round-tag tabular hidden" title="Expected recorded hours (+35m rule)">0h</span>
                </div>
              </div>
            </div>
          </div>

          <!-- Right: ETA Pace & Live Breakdown Ledger -->
          <div class="telemetry-col">
            <div class="eta-box">
              <div class="row-between">
                <span class="micro-kicker" id="lbl-daily-pace">PACE GOAL</span>
                <span id="hero-ratio-lbl" class="ratio-tag ltr tabular hidden"></span>
              </div>
              <div id="eta-headline" class="eta-headline ltr tabular">--:--</div>
              <p id="pace-lbl" class="pace-sub">Calculating pace...</p>
            </div>

            <div class="breakdown-table">
              <div class="bt-row">
                <span class="bt-key"><i class="dot-ind green"></i><span id="lbl-cur-sess">Session</span></span>
                <span id="val-cur-sess" class="bt-val val-green ltr tabular">00:00:00</span>
              </div>
              <div class="bt-row">
                <span class="bt-key"><i class="dot-ind neutral"></i><span id="lbl-gross-today">Gross</span></span>
                <span id="val-gross-today" class="bt-val ltr tabular">00:00:00</span>
              </div>
              <div class="bt-row">
                <span class="bt-key"><i class="dot-ind amber"></i><span id="lbl-locked-today">Locked</span></span>
                <span id="val-locked-today" class="bt-val val-amber ltr tabular">00:00:00</span>
              </div>
            </div>
          </div>
        </div>

        <!-- Workstation Cadence Strip (Segmented Block Timeline) -->
        <div class="cadence-card">
          <div class="row-between cadence-head">
            <span class="micro-kicker" id="lbl-cadence">DAY CADENCE</span>
            <span id="cadence-span-lbl" class="cadence-span ltr tabular">08:00 — 20:00</span>
          </div>
          <canvas id="timeline-canvas" class="cadence-canvas" width="372" height="32"></canvas>
        </div>

        <!-- Attendo 7-Day Horizon Matrix + Campus Integration Strip -->
        <div class="horizon-card">
          <div class="row-between horizon-head">
            <div class="horizon-title-col">
              <span id="period-range-lbl" class="micro-kicker">ATTENDO PERIOD · —</span>
              <span id="period-net-lbl" class="horizon-total ltr tabular">0m / 30h</span>
            </div>
            <div class="horizon-right-col">
              <span id="period-status-lbl" class="volt-pill ltr tabular">0%</span>
              <span id="period-left-lbl" class="left-caption ltr tabular">30h left</span>
            </div>
          </div>

          <!-- 7-Day Vertical Bar Matrix (Read-only official Attendo / Thu-Wed schedule) -->
          <div id="attendo-bar-matrix" class="bar-matrix" role="region" aria-label="7-Day Attendo Progress Matrix"></div>

          <!-- Unified Single-Row Campus Dock (Intra | Attendo) -->
          <div class="campus-dock">
            <div class="dock-cell">
              <div class="dock-label-row">
                <span id="intra-conn-dot" class="dock-dot offline"></span>
                <span class="dock-name" id="lbl-intra-title">42 Intra</span>
                <a id="intra-link-btn" href="https://profile.intra.42.fr/" target="_blank" rel="noopener noreferrer" class="dock-link">Link ↗</a>
              </div>
              <div class="dock-val-row">
                <span id="intra-val-lbl" class="dock-metric ltr tabular">—</span>
                <span id="intra-sub-lbl" class="dock-sub">Not linked</span>
              </div>
            </div>

            <div class="dock-divider" aria-hidden="true"></div>

            <div class="dock-cell">
              <div class="dock-label-row">
                <span id="attendo-conn-dot" class="dock-dot offline"></span>
                <span class="dock-name" id="lbl-attendo-title">1337 Attendo</span>
                <a id="attendo-link-btn" href="https://attendo.1337.ma/students/login" target="_blank" rel="noopener noreferrer" class="dock-link">Link ↗</a>
              </div>
              <div class="dock-val-row">
                <span id="attendo-val-lbl" class="dock-metric ltr tabular">—</span>
                <span id="attendo-days-lbl" class="dock-sub">Not linked</span>
              </div>
            </div>
          </div>
        </div>
      </section>

      <!-- ================================================================= -->
      <!-- VIEW 2: LOGS (Week/Month Strip + Clean Hairline Ledger Table)     -->
      <!-- ================================================================= -->
      <section id="page-sessions" class="view-panel hidden" role="tabpanel">
        <div class="kpi-strip">
          <div class="kpi-block">
            <span class="micro-kicker" id="lbl-this-week">THIS WEEK</span>
            <div class="kpi-nums">
              <span id="val-week-clock" class="kpi-clock ltr tabular">00:00:00</span>
              <span id="val-week-hours" class="kpi-chip ltr tabular">0m</span>
            </div>
          </div>
          <div class="kpi-sep" aria-hidden="true"></div>
          <div class="kpi-block">
            <span class="micro-kicker" id="lbl-this-month">THIS MONTH</span>
            <div class="kpi-nums">
              <span id="val-month-clock" class="kpi-clock ltr tabular">00:00:00</span>
              <span id="val-month-hours" class="kpi-chip ltr tabular">0m</span>
            </div>
          </div>
        </div>

        <div class="ledger-tabs" role="tablist">
          <button type="button" id="htab-sessions" class="ledger-tab" role="tab" aria-selected="false">Sessions</button>
          <button type="button" id="htab-periods" class="ledger-tab" role="tab" aria-selected="false">Attendo Days</button>
          <button type="button" id="htab-locks" class="ledger-tab" role="tab" aria-selected="false">Lock Events</button>
        </div>

        <div class="ledger-summary">
          <div class="row-between">
            <span id="history-summary-title" class="micro-kicker">SESSIONS</span>
            <span id="history-summary-detail" class="cadence-span">0 session(s)</span>
          </div>
          <div id="history-summary-progress-wrap" class="flat-track hidden" aria-hidden="true">
            <div id="history-summary-progress" class="flat-fill" style="width: 0%"></div>
          </div>
        </div>

        <div id="history-rows-box" class="ledger-list">
          <div class="empty-msg">No local X11 sessions recorded yet.</div>
        </div>
      </section>

      <!-- ================================================================= -->
      <!-- VIEW 3: SETUP (Clean Inspector List — Not nested boxes)           -->
      <!-- ================================================================= -->
      <section id="page-settings" class="view-panel hidden" role="tabpanel">
        <div class="inspector-list">
          <!-- Appearance / Theme -->
          <div class="insp-row">
            <span class="insp-label" id="lbl-theme-field">Appearance</span>
            <div class="insp-pills">
              <button type="button" class="theme-btn" data-theme-choice="carbon" id="btn-theme-carbon">Carbon</button>
              <button type="button" class="theme-btn" data-theme-choice="paper" id="btn-theme-paper">Paper</button>
            </div>
          </div>

          <!-- Language -->
          <div class="insp-row">
            <span class="insp-label" id="lbl-lang-field">Language</span>
            <div class="insp-pills">
              <button type="button" class="lang-btn" data-lang="en">EN</button>
              <button type="button" class="lang-btn" data-lang="fr">FR</button>
              <button type="button" class="lang-btn" data-lang="ar">AR</button>
            </div>
          </div>

          <!-- Linked Status & Quick Actions -->
          <div class="insp-block">
            <div class="row-between">
              <span class="micro-kicker" id="lbl-sec-accounts">CAMPUS LINKING</span>
              <span id="acc-status-lbl" class="cadence-span">Intra: — · Attendo: —</span>
            </div>
            <div class="insp-action-grid">
              <a id="open-intra-btn" href="https://profile.intra.42.fr/" target="_blank" rel="noopener noreferrer" class="insp-link">42 Intra ↗</a>
              <a id="open-attendo-btn" href="https://attendo.1337.ma/students/login" target="_blank" rel="noopener noreferrer" class="insp-link">Attendo ↗</a>
              <button type="button" id="sync-now-btn" class="insp-accent-btn">Sync Now</button>
            </div>
          </div>

          <!-- Browser Cookie Source -->
          <div class="insp-block">
            <span class="insp-label" id="lbl-browser-reader">Cookie Source Browser</span>
            <div class="insp-pills-4 ltr">
              <button type="button" class="browser-btn" data-browser="auto">Auto</button>
              <button type="button" class="browser-btn" data-browser="brave">Brave</button>
              <button type="button" class="browser-btn" data-browser="firefox">Firefox</button>
              <button type="button" class="browser-btn" data-browser="chrome">Chrome</button>
            </div>
          </div>

          <!-- Login & Token & Target -->
          <div class="insp-row-split">
            <div class="insp-field grow">
              <label for="setting-intra-login" class="insp-sub" id="lbl-intra-login">42 Login</label>
              <input type="text" id="setting-intra-login" class="insp-input ltr" placeholder="auto-detected" />
            </div>
            <div class="insp-field target-col">
              <label for="setting-target-hours" class="insp-sub" id="lbl-period-target">Target (h)</label>
              <input type="number" id="setting-target-hours" class="insp-input ltr center" min="1" max="200" step="1" value="30" />
            </div>
          </div>

          <div class="insp-field">
            <label for="setting-attendo-token" class="insp-sub" id="lbl-attendo-token">Manual Attendo student_token (optional)</label>
            <input type="password" id="setting-attendo-token" class="insp-input ltr" placeholder="Leave blank for automatic browser cookie" />
          </div>
        </div>

        <div class="setup-footer">
          <button type="button" id="cancel-settings-btn" class="insp-ghost-btn">Cancel</button>
          <button type="button" id="save-settings-btn" class="insp-primary-btn">Save Changes</button>
        </div>
      </section>
    </main>
  </div>

  <script src="popup.js"></script>
</body>
</html>
EOF

# 5. Write popup.css
cat > "$EXT_DIR/popup.css" << 'EOF'
/* ============================================================================
   42 Chrono · Warm Matte Carbon & Signal Copper (+ Daylight Paper Theme)
   ============================================================================ */

:root,
body[data-theme="carbon"] {
  --bg: #0f0f11;
  --surface: #17171a;
  --surface-2: #1f1f24;
  --surface-inset: #121215;
  --border: #28282f;
  --border-strong: #383842;
  --text: #fafafa;
  --text-soft: #d4d4d8;
  --muted: #888891;
  --accent: #f97316;
  --accent-hi: #fb923c;
  --accent-soft: rgba(249, 115, 22, 0.14);
  --accent-border: rgba(249, 115, 22, 0.38);
  --green: #22c55e;
  --green-soft: rgba(34, 197, 94, 0.14);
  --amber: #eab308;
  --amber-soft: rgba(234, 179, 8, 0.14);
  --red: #ef4444;
  --red-soft: rgba(239, 68, 68, 0.13);
  --dial-track: #26262c;
  --dial-tick: #3a3a44;
  --shadow: 0 2px 10px rgba(0, 0, 0, 0.35);
}

body[data-theme="paper"] {
  --bg: #f3f1eb;
  --surface: #ffffff;
  --surface-2: #eae7df;
  --surface-inset: #f7f5f0;
  --border: #dedad0;
  --border-strong: #c9c4b8;
  --text: #141416;
  --text-soft: #3f3f46;
  --muted: #71717a;
  --accent: #ea580c;
  --accent-hi: #f97316;
  --accent-soft: rgba(234, 88, 12, 0.1);
  --accent-border: rgba(234, 88, 12, 0.35);
  --green: #16a34a;
  --green-soft: rgba(22, 163, 74, 0.12);
  --amber: #ca8a04;
  --amber-soft: rgba(202, 138, 4, 0.12);
  --red: #dc2626;
  --red-soft: rgba(220, 38, 38, 0.1);
  --dial-track: #e6e3da;
  --dial-tick: #cbc6b8;
  --shadow: 0 1px 4px rgba(20, 20, 22, 0.06);
}

* {
  box-sizing: border-box;
  margin: 0;
  padding: 0;
  font-family: "Inter", "Ubuntu", "Noto Sans Arabic", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
}

body {
  width: 400px;
  min-width: 400px;
  max-width: 400px;
  background-color: var(--bg);
  color: var(--text);
  font-size: 12.5px;
  overflow-x: hidden;
  -webkit-font-smoothing: antialiased;
}

body::-webkit-scrollbar {
  width: 4px;
}

body::-webkit-scrollbar-thumb {
  background: var(--border-strong);
  border-radius: 999px;
}

.tabular {
  font-family: "JetBrains Mono", "Ubuntu Mono", "DejaVu Sans Mono", ui-monospace, monospace !important;
  font-variant-numeric: tabular-nums;
}

.ltr {
  direction: ltr;
  unicode-bidi: isolate;
}

.hidden {
  display: none !important;
}

.row-between {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 8px;
}

.atelier-shell {
  display: flex;
  flex-direction: column;
}

/* ============================================================================
   TOP INTEGRATED COMMAND STRIP
   ============================================================================ */

.cmd-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  padding: 10px 12px;
  background: var(--surface);
  border-bottom: 1px solid var(--border);
  position: sticky;
  top: 0;
  z-index: 20;
}

.cmd-identity {
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
}

.beacon {
  width: 9px;
  height: 9px;
  border-radius: 2px;
  transform: rotate(45deg);
  flex-shrink: 0;
  background: var(--muted);
  transition: background-color 0.2s, box-shadow 0.2s;
}

.beacon.active {
  background: var(--green);
  box-shadow: 0 0 8px rgba(34, 197, 94, 0.7);
}

.beacon.locked {
  background: var(--amber);
  box-shadow: 0 0 6px rgba(234, 179, 8, 0.55);
}

.id-stack {
  display: flex;
  flex-direction: column;
  line-height: 1.15;
  min-width: 0;
}

.id-top-row {
  display: flex;
  align-items: center;
  gap: 5px;
}

.user-handle {
  font-family: "JetBrains Mono", ui-monospace, monospace;
  font-size: 11.5px;
  font-weight: 800;
  letter-spacing: 0.4px;
  color: var(--text);
}

.host-chip {
  font-family: "JetBrains Mono", ui-monospace, monospace;
  font-size: 9px;
  font-weight: 600;
  color: var(--muted);
  background: var(--surface-2);
  border: 1px solid var(--border);
  border-radius: 4px;
  padding: 1px 4px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 68px;
}

.status-word {
  font-size: 9px;
  font-weight: 700;
  letter-spacing: 0.7px;
  color: var(--muted);
  margin-top: 1px;
}

.status-word.active { color: var(--green); }
.status-word.locked { color: var(--amber); }

/* Top Pill Nav */
.top-nav {
  display: flex;
  background: var(--surface-inset);
  border: 1px solid var(--border);
  border-radius: 999px;
  padding: 2px;
  gap: 2px;
}

.top-nav-btn {
  background: transparent;
  color: var(--muted);
  border: none;
  border-radius: 999px;
  padding: 4px 11px;
  font-size: 11px;
  font-weight: 600;
  cursor: pointer;
  transition: background-color 0.14s, color 0.14s;
}

.top-nav-btn:hover {
  color: var(--text);
}

.top-nav-btn.active {
  background: var(--accent);
  color: #ffffff;
  font-weight: 700;
  box-shadow: 0 1px 6px rgba(249, 115, 22, 0.35);
}

.cmd-tools {
  display: flex;
  align-items: center;
  gap: 4px;
}

.tool-btn {
  width: 26px;
  height: 26px;
  border-radius: 7px;
  border: 1px solid var(--border);
  background: var(--surface-inset);
  color: var(--muted);
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  transition: border-color 0.15s, color 0.15s, background-color 0.15s;
}

.tool-btn:hover {
  border-color: var(--accent-border);
  color: var(--accent);
  background: var(--accent-soft);
}

.tool-btn.spinning svg {
  animation: spin 0.75s linear infinite;
}

@keyframes spin {
  from { transform: rotate(0deg); }
  to { transform: rotate(360deg); }
}

/* Stage */
.stage {
  padding: 10px 12px 12px 12px;
  display: flex;
  flex-direction: column;
  gap: 9px;
}

.view-panel {
  display: flex;
  flex-direction: column;
  gap: 9px;
}

.alert-banner {
  background: var(--red-soft);
  border: 1px solid rgba(239, 68, 68, 0.35);
  color: var(--red);
  font-size: 11px;
  padding: 6px 10px;
  border-radius: 8px;
}

.micro-kicker {
  font-size: 9.5px;
  font-weight: 700;
  letter-spacing: 0.75px;
  color: var(--muted);
  text-transform: uppercase;
}

/* ============================================================================
   VIEW 1: SPLIT ASYMMETRIC HERO DECK
   ============================================================================ */

.hero-deck {
  display: grid;
  grid-template-columns: 150px 1fr;
  gap: 9px;
  align-items: stretch;
}

.chrono-dial-card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 14px;
  padding: 8px;
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: var(--shadow);
  transition: border-color 0.25s;
}

.hero-deck.goal-reached .chrono-dial-card {
  border-color: rgba(34, 197, 94, 0.45);
}

.hero-deck.locked-mode .chrono-dial-card {
  border-color: rgba(234, 179, 8, 0.45);
}

.dial-wrapper {
  position: relative;
  width: 132px;
  height: 132px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.chrono-svg {
  width: 132px;
  height: 132px;
  transform: rotate(-90deg);
}

.dial-ticks {
  fill: none;
  stroke: var(--dial-tick);
  stroke-width: 2;
  stroke-dasharray: 2 5.4;
}

.dial-track {
  fill: none;
  stroke: var(--dial-track);
  stroke-width: 7.5;
}

.dial-arc {
  fill: none;
  stroke: var(--accent);
  stroke-width: 7.5;
  stroke-linecap: round;
  transition: stroke-dashoffset 0.4s cubic-bezier(0.22, 1, 0.36, 1), stroke 0.2s;
}

.dial-wrapper.done .dial-arc { stroke: var(--green); }
.dial-wrapper.locked .dial-arc { stroke: var(--amber); }

.dial-center {
  position: absolute;
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
  gap: 2px;
}

.dial-kicker {
  font-size: 8.5px;
  font-weight: 800;
  letter-spacing: 0.9px;
  color: var(--muted);
  text-transform: uppercase;
}

.dial-time {
  font-size: 18.5px;
  font-weight: 800;
  color: var(--text);
  letter-spacing: -0.04em;
  line-height: 1.05;
}

.dial-badges {
  display: flex;
  align-items: center;
  gap: 4px;
  margin-top: 2px;
}

.dial-pct {
  font-size: 9.5px;
  font-weight: 700;
  color: var(--accent);
}

.dial-wrapper.done .dial-pct { color: var(--green); }

.dial-round-tag {
  font-size: 9px;
  font-weight: 700;
  color: var(--text-soft);
  background: var(--surface-2);
  border: 1px solid var(--border);
  border-radius: 4px;
  padding: 0 4px;
}

/* Right Telemetry Column */
.telemetry-col {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.eta-box {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 12px;
  padding: 9px 11px;
  box-shadow: var(--shadow);
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.ratio-tag {
  font-size: 9.5px;
  font-weight: 600;
  color: var(--muted);
}

.eta-headline {
  font-size: 19px;
  font-weight: 800;
  color: var(--text);
  letter-spacing: -0.02em;
  line-height: 1.15;
}

.hero-deck.goal-reached .eta-headline {
  color: var(--green);
}

.hero-deck.locked-mode .eta-headline {
  color: var(--amber);
}

.pace-sub {
  font-size: 10px;
  color: var(--muted);
  line-height: 1.3;
}

.pace-sub b {
  color: var(--text-soft);
}

/* Horizontal Breakdown Table */
.breakdown-table {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 12px;
  padding: 5px 10px;
  box-shadow: var(--shadow);
  display: flex;
  flex-direction: column;
}

.bt-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 4.5px 0;
  border-bottom: 1px solid var(--border);
}

.bt-row:last-child {
  border-bottom: none;
}

.bt-key {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 10.5px;
  font-weight: 500;
  color: var(--muted);
}

.dot-ind {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  display: inline-block;
}

.dot-ind.green { background: var(--green); }
.dot-ind.amber { background: var(--amber); }
.dot-ind.neutral { background: var(--muted); }

.bt-val {
  font-size: 11px;
  font-weight: 700;
  color: var(--text);
}

.val-green { color: var(--green) !important; }
.val-amber { color: var(--amber) !important; }

/* ============================================================================
   CADENCE SEGMENTED STRIP
   ============================================================================ */

.cadence-card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 12px;
  padding: 8px 11px 7px 11px;
  box-shadow: var(--shadow);
  display: flex;
  flex-direction: column;
  gap: 5px;
}

.cadence-span {
  font-size: 10px;
  color: var(--muted);
}

.cadence-canvas {
  width: 100%;
  height: 32px;
  display: block;
}

/* ============================================================================
   7-DAY HORIZON MATRIX + UNIFIED CAMPUS DOCK
   ============================================================================ */

.horizon-card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 14px;
  padding: 10px 12px;
  box-shadow: var(--shadow);
  display: flex;
  flex-direction: column;
  gap: 9px;
}

.horizon-title-col {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.horizon-total {
  font-size: 15px;
  font-weight: 800;
  color: var(--text);
  letter-spacing: -0.02em;
}

.horizon-right-col {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 2px;
}

.volt-pill {
  font-size: 10.5px;
  font-weight: 800;
  color: var(--accent);
  background: var(--accent-soft);
  border: 1px solid var(--accent-border);
  border-radius: 6px;
  padding: 1px 7px;
}

.volt-pill.done {
  color: var(--green);
  background: var(--green-soft);
  border-color: rgba(34, 197, 94, 0.4);
}

.left-caption {
  font-size: 10px;
  color: var(--muted);
}

/* 7-Column Bar Chart Matrix */
.bar-matrix {
  display: flex;
  align-items: flex-end;
  gap: 6px;
  padding: 4px 0 2px 0;
}

.bar-col {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 4px;
  min-width: 0;
}

.bar-hrs {
  font-family: "JetBrains Mono", ui-monospace, monospace;
  font-size: 9px;
  font-weight: 600;
  color: var(--muted);
  height: 11px;
}

.bar-well {
  width: 100%;
  height: 36px;
  background: var(--surface-inset);
  border: 1px solid var(--border);
  border-radius: 6px;
  display: flex;
  align-items: flex-end;
  padding: 2px;
  overflow: hidden;
}

.bar-col.is-today .bar-well {
  border-color: var(--accent-border);
}

.bar-col.is-counted .bar-hrs {
  color: var(--text-soft);
}

.bar-fill {
  width: 100%;
  border-radius: 3.5px;
  background: var(--border-strong);
  transition: height 0.35s cubic-bezier(0.22, 1, 0.36, 1), background-color 0.2s;
}

.bar-col.is-counted .bar-fill {
  background: linear-gradient(180deg, var(--accent-hi) 0%, var(--accent) 100%);
}

.bar-col.is-today.is-counted .bar-fill {
  background: linear-gradient(180deg, #4ade80 0%, var(--green) 100%);
}

.bar-day-lbl {
  font-family: "JetBrains Mono", ui-monospace, monospace;
  font-size: 9px;
  font-weight: 600;
  color: var(--muted);
  text-transform: uppercase;
}

.bar-col.is-today .bar-day-lbl {
  color: var(--accent);
  font-weight: 800;
}

/* Unified Campus Dock Strip */
.campus-dock {
  display: flex;
  align-items: center;
  background: var(--surface-inset);
  border: 1px solid var(--border);
  border-radius: 10px;
  padding: 7px 10px;
  gap: 10px;
}

.dock-cell {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}

.dock-divider {
  width: 1px;
  height: 28px;
  background: var(--border);
  flex-shrink: 0;
}

.dock-label-row {
  display: flex;
  align-items: center;
  gap: 5px;
}

.dock-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  flex-shrink: 0;
}

.dock-dot.online { background: var(--green); }
.dock-dot.offline { background: var(--border-strong); }

.dock-name {
  font-size: 10px;
  font-weight: 700;
  color: var(--muted);
  flex: 1;
}

.dock-link {
  font-size: 9.5px;
  font-weight: 700;
  color: var(--accent);
  text-decoration: none;
  border: 1px solid var(--accent-border);
  background: var(--accent-soft);
  padding: 1px 6px;
  border-radius: 4px;
}

.dock-link:hover {
  background: var(--accent);
  color: #ffffff;
}

.dock-val-row {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 6px;
}

.dock-metric {
  font-size: 13.5px;
  font-weight: 800;
  color: var(--text);
}

.dock-sub {
  font-size: 10px;
  color: var(--muted);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

/* ============================================================================
   VIEW 2: LOGS (KPI Header + Underline Tabs + Hairline Ledger)
   ============================================================================ */

.kpi-strip {
  display: flex;
  align-items: center;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 12px;
  padding: 10px 12px;
  gap: 12px;
  box-shadow: var(--shadow);
}

.kpi-block {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 3px;
}

.kpi-sep {
  width: 1px;
  height: 30px;
  background: var(--border);
}

.kpi-nums {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 6px;
}

.kpi-clock {
  font-size: 15px;
  font-weight: 800;
  color: var(--text);
}

.kpi-chip {
  font-size: 10px;
  font-weight: 700;
  color: var(--accent);
}

.ledger-tabs {
  display: flex;
  border-bottom: 1px solid var(--border);
  gap: 14px;
  padding: 0 4px;
}

.ledger-tab {
  background: transparent;
  border: none;
  border-bottom: 2px solid transparent;
  color: var(--muted);
  font-size: 11px;
  font-weight: 600;
  padding: 6px 2px;
  cursor: pointer;
  transition: color 0.14s, border-color 0.14s;
}

.ledger-tab:hover {
  color: var(--text);
}

.ledger-tab.active {
  color: var(--accent);
  border-bottom-color: var(--accent);
  font-weight: 700;
}

.ledger-summary {
  display: flex;
  flex-direction: column;
  gap: 5px;
  padding: 2px 2px 0 2px;
}

.flat-track {
  height: 4px;
  background: var(--surface-2);
  border-radius: 999px;
  overflow: hidden;
}

.flat-fill {
  height: 100%;
  background: var(--accent);
  border-radius: 999px;
}

.flat-fill.complete { background: var(--green); }

.ledger-list {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 12px;
  max-height: 255px;
  overflow-y: auto;
  box-shadow: var(--shadow);
}

.ledger-list::-webkit-scrollbar {
  width: 4px;
}

.ledger-list::-webkit-scrollbar-thumb {
  background: var(--border-strong);
  border-radius: 999px;
}

.ledger-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 7px 11px;
  border-bottom: 1px solid var(--border);
  font-size: 11px;
}

.ledger-row:last-child {
  border-bottom: none;
}

.ledger-row.today-row {
  background: var(--accent-soft);
}

.ledger-row.live-row {
  background: var(--green-soft);
}

.ledger-left {
  display: flex;
  flex-direction: column;
  gap: 1px;
}

.ledger-title {
  font-weight: 600;
  color: var(--text);
}

.ledger-meta {
  font-size: 10px;
  color: var(--muted);
}

.ledger-right {
  display: flex;
  align-items: center;
  gap: 8px;
}

.ledger-dur {
  font-family: "JetBrains Mono", ui-monospace, monospace;
  font-weight: 700;
  font-size: 11.5px;
  color: var(--text);
}

.badge-state {
  font-size: 9.5px;
  font-weight: 700;
  padding: 1.5px 6px;
  border-radius: 4px;
  background: var(--surface-2);
  color: var(--muted);
}

.badge-state.ok { background: var(--green-soft); color: var(--green); }
.badge-state.warn { background: var(--amber-soft); color: var(--amber); }

.empty-msg {
  padding: 24px 12px;
  text-align: center;
  color: var(--muted);
  font-size: 11px;
  font-style: italic;
}

/* ============================================================================
   VIEW 3: SETUP (Hairline Inspector Rows)
   ============================================================================ */

.inspector-list {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 12px;
  padding: 4px 12px;
  box-shadow: var(--shadow);
  display: flex;
  flex-direction: column;
}

.insp-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 8px 0;
  border-bottom: 1px solid var(--border);
}

.insp-block {
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding: 8px 0;
  border-bottom: 1px solid var(--border);
}

.insp-row-split {
  display: flex;
  gap: 8px;
  padding: 8px 0;
  border-bottom: 1px solid var(--border);
}

.insp-field {
  display: flex;
  flex-direction: column;
  gap: 4px;
  padding: 8px 0;
}

.insp-row-split .insp-field {
  padding: 0;
}

.grow { flex: 1; }
.target-col { width: 82px; }

.insp-label {
  font-size: 11.5px;
  font-weight: 600;
  color: var(--text);
}

.insp-sub {
  font-size: 10px;
  font-weight: 600;
  color: var(--muted);
}

.insp-pills {
  display: flex;
  gap: 4px;
}

.insp-pills-4 {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 5px;
}

.theme-btn, .lang-btn, .browser-btn {
  background: var(--surface-inset);
  color: var(--text-soft);
  border: 1px solid var(--border);
  border-radius: 6px;
  padding: 4px 9px;
  font-size: 10.5px;
  font-weight: 600;
  cursor: pointer;
  transition: background-color 0.12s, color 0.12s, border-color 0.12s;
}

.theme-btn.active, .lang-btn.active, .browser-btn.active {
  background: var(--accent);
  color: #ffffff;
  border-color: var(--accent);
  font-weight: 700;
}

.insp-action-grid {
  display: grid;
  grid-template-columns: 1fr 1fr 1fr;
  gap: 6px;
}

.insp-link, .insp-accent-btn, .insp-ghost-btn, .insp-primary-btn {
  border-radius: 7px;
  padding: 6px 10px;
  font-size: 11px;
  font-weight: 600;
  cursor: pointer;
  text-align: center;
  text-decoration: none;
  transition: opacity 0.14s, background-color 0.14s;
}

.insp-link, .insp-ghost-btn {
  background: var(--surface-inset);
  color: var(--text);
  border: 1px solid var(--border);
}

.insp-link:hover, .insp-ghost-btn:hover {
  border-color: var(--accent-border);
  color: var(--accent);
}

.insp-accent-btn {
  background: var(--accent-soft);
  color: var(--accent);
  border: 1px solid var(--accent-border);
  font-weight: 700;
}

.insp-accent-btn:hover {
  background: var(--accent);
  color: #ffffff;
}

.insp-input {
  background: var(--surface-inset);
  color: var(--text);
  border: 1px solid var(--border);
  border-radius: 7px;
  padding: 5px 8px;
  font-size: 11px;
  outline: none;
  width: 100%;
}

.insp-input.center { text-align: center; }

.insp-input:focus {
  border-color: var(--accent);
}

.setup-footer {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
}

.insp-primary-btn {
  background: var(--accent);
  color: #ffffff;
  border: 1px solid var(--accent);
  font-weight: 700;
  padding: 6px 14px;
}

.insp-primary-btn:hover {
  background: var(--accent-hi);
}

[dir="rtl"] .eta-headline,
[dir="rtl"] .horizon-right-col {
  text-align: left;
}
EOF

# 6. Write popup.js
cat > "$EXT_DIR/popup.js" << 'EOF'
const HOST_NAME = "com.mrbib.live_estimate";
const DIAL_CIRCUMFERENCE = 2 * Math.PI * 54; // r=54 -> 339.292

const STRINGS = {
  en: {
    status_active: "ACTIVE",
    status_locked: "LOCKED",
    status_idle: "IDLE",
    todays_active_time: "ACTIVE",
    pace_goal_label: "PACE GOAL",
    cadence_label: "DAY CADENCE",
    eta_done: "DONE ✓",
    eta_paused: "PAUSED",
    eta_prefix: "ETA {eta}",
    pace_remaining: "<b>{left}</b> remaining today",
    pace_done_sub: "Daily target met",
    pace_locked_sub: "<b>{left}</b> left when unlocked",
    active_of_target: "{logged} / {target}",
    current_sess: "Session",
    gross_today: "Gross",
    locked_label: "Locked",
    attendo_period_prefix: "ATTENDO · {start} → {end}",
    goal_reached_text: "Goal met",
    period_left: "left",
    intra_label: "42 Intra",
    attendo_label: "1337 Attendo",
    link_btn: "Link ↗",
    linked_badge: "Linked",
    not_linked_badge: "Not linked",
    today_lower: "today",
    days_of_seven: "{counted}/7d",
    this_week: "THIS WEEK",
    this_month: "THIS MONTH",
    tab_overview: "Today",
    tab_sessions: "Logs",
    tab_periods: "Attendo Days",
    tab_locks: "Lock Events",
    tab_settings: "Setup",
    status_live: "LIVE",
    status_counted: "Counted",
    status_not_counted: "Not counted",
    status_ongoing: "Ongoing",
    status_completed: "Completed",
    current_period_card: "ATTENDO PERIOD",
    period_summary_fmt: "{total} / {target} · {counted}/7d",
    sessions_summary_fmt: "{count} session(s) · {locked} locked",
    lock_summary_fmt: "{count} lock(s) · {total} total",
    no_sessions_data: "No local X11 sessions recorded yet.",
    no_periods_data: "Link 1337 Attendo to view official per-day history.",
    no_locks_day: "No lock intervals recorded today.",
    theme_label: "Appearance",
    theme_carbon: "Carbon",
    theme_paper: "Paper",
    language_label: "Language",
    sec_accounts: "CAMPUS LINKING",
    open_intra_btn: "42 Intra ↗",
    open_attendo_btn: "Attendo ↗",
    sync_now_btn: "Sync Now",
    browser_pref_label: "Cookie Source Browser",
    intra_login_label: "42 Login",
    attendo_token_label: "Manual Attendo student_token (optional)",
    period_target_label: "Target (h)",
    cancel: "Cancel",
    save: "Save Changes",
  },
  fr: {
    status_active: "ACTIF",
    status_locked: "VERROUILLÉ",
    status_idle: "INACTIF",
    todays_active_time: "ACTIF",
    pace_goal_label: "OBJECTIF",
    cadence_label: "RYTHME JOUR",
    eta_done: "ATTEINT ✓",
    eta_paused: "EN PAUSE",
    eta_prefix: "FIN {eta}",
    pace_remaining: "<b>{left}</b> restant",
    pace_done_sub: "Objectif du jour atteint",
    pace_locked_sub: "<b>{left}</b> restant au déverrouillage",
    active_of_target: "{logged} / {target}",
    current_sess: "Session",
    gross_today: "Brut",
    locked_label: "Verrouillé",
    attendo_period_prefix: "ATTENDO · {start} → {end}",
    goal_reached_text: "Atteint",
    period_left: "restant",
    intra_label: "42 Intra",
    attendo_label: "1337 Attendo",
    link_btn: "Lier ↗",
    linked_badge: "Lié",
    not_linked_badge: "Non lié",
    today_lower: "auj.",
    days_of_seven: "{counted}/7j",
    this_week: "CETTE SEMAINE",
    this_month: "CE MOIS",
    tab_overview: "Auj.",
    tab_sessions: "Journal",
    tab_periods: "Jours Attendo",
    tab_locks: "Verrous",
    tab_settings: "Config",
    status_live: "DIRECT",
    status_counted: "Compté",
    status_not_counted: "Non compté",
    status_ongoing: "En cours",
    status_completed: "Terminé",
    current_period_card: "PÉRIODE ATTENDO",
    period_summary_fmt: "{total} / {target} · {counted}/7j",
    sessions_summary_fmt: "{count} session(s) · {locked} verrouillé",
    lock_summary_fmt: "{count} verrou(s) · {total}",
    no_sessions_data: "Aucune session X11 enregistrée.",
    no_periods_data: "Liez 1337 Attendo pour voir les jours officiels.",
    no_locks_day: "Aucun verrouillage aujourd’hui.",
    theme_label: "Apparence",
    theme_carbon: "Carbon",
    theme_paper: "Papier",
    language_label: "Langue",
    sec_accounts: "COMPTES CAMPUS",
    open_intra_btn: "42 Intra ↗",
    open_attendo_btn: "Attendo ↗",
    sync_now_btn: "Synchroniser",
    browser_pref_label: "Navigateur cookies",
    intra_login_label: "Login 42",
    attendo_token_label: "student_token Attendo (optionnel)",
    period_target_label: "Cible (h)",
    cancel: "Annuler",
    save: "Enregistrer",
  },
  ar: {
    status_active: "نشط",
    status_locked: "مقفل",
    status_idle: "خامل",
    todays_active_time: "النشاط",
    pace_goal_label: "الهدف اليومي",
    cadence_label: "إيقاع اليوم",
    eta_done: "مكتمل ✓",
    eta_paused: "متوقف",
    eta_prefix: "الانتهاء {eta}",
    pace_remaining: "متبقي <b>{left}</b> اليوم",
    pace_done_sub: "تم بلوغ هدف اليوم",
    pace_locked_sub: "متبقي <b>{left}</b> عند الفتح",
    active_of_target: "{logged} / {target}",
    current_sess: "الجلسة",
    gross_today: "الإجمالي",
    locked_label: "القفل",
    attendo_period_prefix: "أتندو · {start} → {end}",
    goal_reached_text: "مكتمل",
    period_left: "متبقي",
    intra_label: "42 Intra",
    attendo_label: "1337 Attendo",
    link_btn: "ربط ↗",
    linked_badge: "مرتبط",
    not_linked_badge: "غير مرتبط",
    today_lower: "اليوم",
    days_of_seven: "{counted}/7ي",
    this_week: "هذا الأسبوع",
    this_month: "هذا الشهر",
    tab_overview: "اليوم",
    tab_sessions: "السجل",
    tab_periods: "أيام أتندو",
    tab_locks: "الأقفال",
    tab_settings: "الإعداد",
    status_live: "مباشر",
    status_counted: "محتسب",
    status_not_counted: "غير محتسب",
    status_ongoing: "جاري",
    status_completed: "مكتمل",
    current_period_card: "فترة أتندو",
    period_summary_fmt: "{total} / {target} · {counted}/7ي",
    sessions_summary_fmt: "{count} جلسة · قفل {locked}",
    lock_summary_fmt: "{count} قفل · {total}",
    no_sessions_data: "لا توجد جلسات مسجلة بعد.",
    no_periods_data: "اربط حساب 1337 Attendo لعرض سجل الأيام.",
    no_locks_day: "لا توجد فترات قفل اليوم.",
    theme_label: "المظهر",
    theme_carbon: "داكن",
    theme_paper: "ورقي",
    language_label: "اللغة",
    sec_accounts: "حسابات الحرم الجامعي",
    open_intra_btn: "42 Intra ↗",
    open_attendo_btn: "Attendo ↗",
    sync_now_btn: "مزامنة",
    browser_pref_label: "متصفح الكوكيز",
    intra_login_label: "مستخدم 42",
    attendo_token_label: "رمز student_token (اختياري)",
    period_target_label: "الهدف (س)",
    cancel: "إلغاء",
    save: "حفظ",
  },
};

const DEFAULT_SETTINGS = {
  theme: "carbon",
  language: "en",
  browserPreference: "auto",
  intraLogin: "",
  attendoToken: "",
  periodTargetHours: 30,
  activeTab: "overview",
  historyTab: "sessions",
};

let settings = { ...DEFAULT_SETTINGS };
let draftBrowserPref = "auto";
let lastPayload = null;
let fetchedAtMs = 0;
let tickTimer = null;
let dom = {};

function initDomHandles() {
  dom = {
    liveBeacon: document.getElementById("live-beacon"),
    userHandle: document.getElementById("user-handle"),
    hostChip: document.getElementById("host-chip"),
    statusWord: document.getElementById("status-word"),
    themeQuickBtn: document.getElementById("theme-quick-btn"),
    refreshBtn: document.getElementById("refresh-btn"),
    errorBox: document.getElementById("error-box"),

    pageOverview: document.getElementById("page-overview"),
    pageSessions: document.getElementById("page-sessions"),
    pageSettings: document.getElementById("page-settings"),

    navBtnOverview: document.getElementById("nav-btn-overview"),
    navBtnSessions: document.getElementById("nav-btn-sessions"),
    navBtnSettings: document.getElementById("nav-btn-settings"),
    navLblOverview: document.getElementById("nav-lbl-overview"),
    navLblSessions: document.getElementById("nav-lbl-sessions"),
    navLblSettings: document.getElementById("nav-lbl-settings"),

    // Hero Split Deck
    heroPanel: document.getElementById("hero-panel"),
    lblHeroTitle: document.getElementById("lbl-hero-title"),
    heroRingWrap: document.getElementById("hero-ring-wrap"),
    heroRingArc: document.getElementById("hero-ring-arc"),
    heroClock: document.getElementById("hero-clock"),
    heroRingPct: document.getElementById("hero-ring-pct"),
    heroRoundingChip: document.getElementById("hero-rounding-chip"),

    lblDailyPace: document.getElementById("lbl-daily-pace"),
    heroRatioLbl: document.getElementById("hero-ratio-lbl"),
    etaHeadline: document.getElementById("eta-headline"),
    paceLbl: document.getElementById("pace-lbl"),

    lblCurSess: document.getElementById("lbl-cur-sess"),
    valCurSess: document.getElementById("val-cur-sess"),
    lblGrossToday: document.getElementById("lbl-gross-today"),
    valGrossToday: document.getElementById("val-gross-today"),
    lblLockedToday: document.getElementById("lbl-locked-today"),
    valLockedToday: document.getElementById("val-locked-today"),

    // Cadence Timeline
    lblCadence: document.getElementById("lbl-cadence"),
    cadenceSpanLbl: document.getElementById("cadence-span-lbl"),
    timelineCanvas: document.getElementById("timeline-canvas"),

    // Attendo Horizon Matrix & Campus Dock
    periodRangeLbl: document.getElementById("period-range-lbl"),
    periodNetLbl: document.getElementById("period-net-lbl"),
    periodStatusLbl: document.getElementById("period-status-lbl"),
    periodLeftLbl: document.getElementById("period-left-lbl"),
    attendoBarMatrix: document.getElementById("attendo-bar-matrix"),

    intraConnDot: document.getElementById("intra-conn-dot"),
    lblIntraTitle: document.getElementById("lbl-intra-title"),
    intraLinkBtn: document.getElementById("intra-link-btn"),
    intraValLbl: document.getElementById("intra-val-lbl"),
    intraSubLbl: document.getElementById("intra-sub-lbl"),

    attendoConnDot: document.getElementById("attendo-conn-dot"),
    lblAttendoTitle: document.getElementById("lbl-attendo-title"),
    attendoLinkBtn: document.getElementById("attendo-link-btn"),
    attendoValLbl: document.getElementById("attendo-val-lbl"),
    attendoDaysLbl: document.getElementById("attendo-days-lbl"),

    // Logs Page
    lblThisWeek: document.getElementById("lbl-this-week"),
    valWeekHours: document.getElementById("val-week-hours"),
    valWeekClock: document.getElementById("val-week-clock"),
    lblThisMonth: document.getElementById("lbl-this-month"),
    valMonthHours: document.getElementById("val-month-hours"),
    valMonthClock: document.getElementById("val-month-clock"),

    htabSessions: document.getElementById("htab-sessions"),
    htabPeriods: document.getElementById("htab-periods"),
    htabLocks: document.getElementById("htab-locks"),
    historySummaryTitle: document.getElementById("history-summary-title"),
    historySummaryDetail: document.getElementById("history-summary-detail"),
    historySummaryProgressWrap: document.getElementById("history-summary-progress-wrap"),
    historySummaryProgress: document.getElementById("history-summary-progress"),
    historyRowsBox: document.getElementById("history-rows-box"),

    // Setup Page
    lblThemeField: document.getElementById("lbl-theme-field"),
    btnThemeCarbon: document.getElementById("btn-theme-carbon"),
    btnThemePaper: document.getElementById("btn-theme-paper"),
    lblLangField: document.getElementById("lbl-lang-field"),
    lblSecAccounts: document.getElementById("lbl-sec-accounts"),
    accStatusLbl: document.getElementById("acc-status-lbl"),
    syncNowBtn: document.getElementById("sync-now-btn"),
    openIntraBtn: document.getElementById("open-intra-btn"),
    openAttendoBtn: document.getElementById("open-attendo-btn"),
    lblBrowserReader: document.getElementById("lbl-browser-reader"),
    lblIntraLogin: document.getElementById("lbl-intra-login"),
    settingIntraLogin: document.getElementById("setting-intra-login"),
    lblAttendoToken: document.getElementById("lbl-attendo-token"),
    settingAttendoToken: document.getElementById("setting-attendo-token"),
    lblPeriodTarget: document.getElementById("lbl-period-target"),
    settingTargetHours: document.getElementById("setting-target-hours"),
    cancelSettingsBtn: document.getElementById("cancel-settings-btn"),
    saveSettingsBtn: document.getElementById("save-settings-btn"),
  };
}

function escapeHtml(text) {
  return String(text ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function tr(key, vars = {}) {
  const lang = STRINGS[settings.language] ? settings.language : "en";
  let text = STRINGS[lang][key] || STRINGS.en[key] || key;
  for (const [k, v] of Object.entries(vars)) {
    text = text.replaceAll(`{${k}}`, String(v));
  }
  return text;
}

function fmtHms(seconds) {
  if (seconds === null || seconds === undefined) return "--:--:--";
  const val = Math.max(0, Math.floor(seconds));
  const h = Math.floor(val / 3600);
  const m = Math.floor((val % 3600) / 60);
  const s = val % 60;
  return [h, m, s].map((v) => String(v).padStart(2, "0")).join(":");
}

function fmtHm(seconds) {
  if (seconds === null || seconds === undefined) return "—";
  const val = Math.max(0, Math.floor(seconds));
  if (val < 3600) return `${Math.floor(val / 60)}m`;
  const h = Math.floor(val / 3600);
  const m = Math.floor((val % 3600) / 60);
  return `${h}h ${String(m).padStart(2, "0")}m`;
}

function fmtCompactHours(seconds) {
  if (seconds === null || seconds === undefined) return "—";
  const text = fmtHm(seconds);
  return text.endsWith(" 00m") ? text.slice(0, -4) : text;
}

function formatClockFromTs(tsSec) {
  try {
    return new Intl.DateTimeFormat("en-GB", {
      timeZone: "Africa/Casablanca",
      hour: "2-digit",
      minute: "2-digit",
      hour12: false,
    }).format(new Date(tsSec * 1000));
  } catch {
    const dt = new Date(tsSec * 1000);
    return `${String(dt.getHours()).padStart(2, "0")}:${String(dt.getMinutes()).padStart(2, "0")}`;
  }
}

function campusTodayIso(tsSec) {
  try {
    return new Intl.DateTimeFormat("en-CA", {
      timeZone: "Africa/Casablanca",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).format(new Date(tsSec * 1000));
  } catch {
    const dt = new Date(tsSec * 1000);
    const y = dt.getFullYear();
    const m = String(dt.getMonth() + 1).padStart(2, "0");
    const d = String(dt.getDate()).padStart(2, "0");
    return `${y}-${m}-${d}`;
  }
}

function addDaysIso(dateStr, deltaDays) {
  const [y, m, d] = dateStr.split("-").map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d + deltaDays));
  return dt.toISOString().slice(0, 10);
}

function setNodeText(el, text) {
  if (el && el.textContent !== text) {
    el.textContent = text;
  }
}

function showError(msg) {
  if (!dom.errorBox) return;
  dom.errorBox.textContent = msg;
  dom.errorBox.classList.remove("hidden");
}

function clearError() {
  if (!dom.errorBox) return;
  dom.errorBox.textContent = "";
  dom.errorBox.classList.add("hidden");
}

function applyTheme() {
  const theme = settings.theme === "paper" ? "paper" : "carbon";
  document.body.setAttribute("data-theme", theme);
  document.querySelectorAll(".theme-btn").forEach((btn) => {
    btn.classList.toggle("active", btn.getAttribute("data-theme-choice") === theme);
  });
}

function applyLanguage() {
  const lang = STRINGS[settings.language] ? settings.language : "en";
  document.body.dir = lang === "ar" ? "rtl" : "ltr";

  setNodeText(dom.lblHeroTitle, tr("todays_active_time"));
  setNodeText(dom.lblDailyPace, tr("pace_goal_label"));
  setNodeText(dom.lblCadence, tr("cadence_label"));
  setNodeText(dom.lblCurSess, tr("current_sess"));
  setNodeText(dom.lblGrossToday, tr("gross_today"));
  setNodeText(dom.lblLockedToday, tr("locked_label"));
  setNodeText(dom.lblIntraTitle, tr("intra_label"));
  setNodeText(dom.lblAttendoTitle, tr("attendo_label"));
  setNodeText(dom.intraLinkBtn, tr("link_btn"));
  setNodeText(dom.attendoLinkBtn, tr("link_btn"));

  setNodeText(dom.lblThisWeek, tr("this_week"));
  setNodeText(dom.lblThisMonth, tr("this_month"));
  setNodeText(dom.htabSessions, tr("tab_sessions"));
  setNodeText(dom.htabPeriods, tr("tab_periods"));
  setNodeText(dom.htabLocks, tr("tab_locks"));

  setNodeText(dom.navLblOverview, tr("tab_overview"));
  setNodeText(dom.navLblSessions, tr("tab_sessions"));
  setNodeText(dom.navLblSettings, tr("tab_settings"));

  setNodeText(dom.lblThemeField, tr("theme_label"));
  setNodeText(dom.btnThemeCarbon, tr("theme_carbon"));
  setNodeText(dom.btnThemePaper, tr("theme_paper"));
  setNodeText(dom.lblLangField, tr("language_label"));
  setNodeText(dom.lblSecAccounts, tr("sec_accounts"));
  setNodeText(dom.openIntraBtn, tr("open_intra_btn"));
  setNodeText(dom.openAttendoBtn, tr("open_attendo_btn"));
  setNodeText(dom.syncNowBtn, tr("sync_now_btn"));
  setNodeText(dom.lblBrowserReader, tr("browser_pref_label"));
  setNodeText(dom.lblIntraLogin, tr("intra_login_label"));
  setNodeText(dom.lblAttendoToken, tr("attendo_token_label"));
  setNodeText(dom.lblPeriodTarget, tr("period_target_label"));
  setNodeText(dom.cancelSettingsBtn, tr("cancel"));
  setNodeText(dom.saveSettingsBtn, tr("save"));

  document.querySelectorAll(".lang-btn").forEach((btn) => {
    btn.classList.toggle("active", btn.getAttribute("data-lang") === lang);
  });
}

function updateBrowserButtons(browserPref) {
  draftBrowserPref = browserPref || "auto";
  document.querySelectorAll(".browser-btn").forEach((btn) => {
    btn.classList.toggle("active", btn.getAttribute("data-browser") === draftBrowserPref);
  });
}

function syncSettingsFormFromState() {
  updateBrowserButtons(settings.browserPreference);
  if (dom.settingIntraLogin) dom.settingIntraLogin.value = settings.intraLogin || "";
  if (dom.settingAttendoToken) dom.settingAttendoToken.value = settings.attendoToken || "";
  if (dom.settingTargetHours) dom.settingTargetHours.value = String(settings.periodTargetHours || 30);
}

// =============================================================================
// Segmented Copper Cadence Timeline (Distinct visual language)
// =============================================================================

function drawCadenceTimeline(canvas, timelineData, nowTs, isLive, lockedNow, elapsed) {
  if (!canvas || !timelineData) return;
  const ctx = canvas.getContext("2d");
  if (!ctx) return;

  const isPaper = settings.theme === "paper";
  const trackFill = isPaper ? "#f7f5f0" : "#121215";
  const trackBorder = isPaper ? "#dedad0" : "#28282f";
  const tickColor = isPaper ? "#cbc6b8" : "#303038";
  const accentColor = isPaper ? "#ea580c" : "#f97316";
  const lockColor = isPaper ? "#ca8a04" : "#eab308";
  const playheadColor = isPaper ? "#16a34a" : "#22c55e";
  const textColor = isPaper ? "#71717a" : "#888891";

  const dpr = window.devicePixelRatio || 1;
  const w = canvas.clientWidth || 372;
  const h = canvas.clientHeight || 32;

  if (canvas.width !== Math.floor(w * dpr) || canvas.height !== Math.floor(h * dpr)) {
    canvas.width = Math.floor(w * dpr);
    canvas.height = Math.floor(h * dpr);
  }

  ctx.save();
  ctx.scale(dpr, dpr);
  ctx.clearRect(0, 0, w, h);

  const barY = 3;
  const barH = 15;
  const winStart = Number(timelineData.win_start || 0);
  const effectiveNow = nowTs + (isLive ? elapsed : 0);
  const winEnd = Math.max(winStart + 3600, Number(timelineData.win_end || winStart + 3600));
  const span = Math.max(1, winEnd - winStart);

  // Subtle architectural ruler track
  ctx.fillStyle = trackFill;
  ctx.beginPath();
  ctx.roundRect(0, barY, w, barH, 3);
  ctx.fill();
  ctx.strokeStyle = trackBorder;
  ctx.lineWidth = 1;
  ctx.stroke();

  // Hourly scale notch ticks along bottom edge of ruler
  ctx.fillStyle = tickColor;
  const numTicks = 12;
  for (let i = 1; i < numTicks; i++) {
    const tx = (i / numTicks) * w;
    ctx.fillRect(tx - 0.5, barY + barH - 4, 1, 3);
  }

  // Active workstation blocks (sharp geometric copper bars)
  const activeSegs = [...(timelineData.active_segments || [])];
  if (isLive && !lockedNow && elapsed > 0 && activeSegs.length > 0) {
    const last = activeSegs[activeSegs.length - 1];
    activeSegs[activeSegs.length - 1] = [last[0], Math.max(Number(last[1]), effectiveNow)];
  }
  ctx.fillStyle = accentColor;
  for (const seg of activeSegs) {
    const a = Math.max(winStart, Number(seg[0]));
    const b = Math.min(winEnd, Number(seg[1]));
    if (b > a) {
      const x1 = Math.max(1, Math.min(w - 1, ((a - winStart) / span) * w));
      const x2 = Math.max(1, Math.min(w - 1, ((b - winStart) / span) * w));
      const segW = Math.min(w - x1 - 1, Math.max(2, x2 - x1));
      ctx.fillRect(x1, barY + 2, segW, barH - 4);
    }
  }

  // Lock ticks (warm gold vertical stripes)
  const lockSegs = timelineData.lock_segments || [];
  ctx.fillStyle = lockColor;
  for (const seg of lockSegs) {
    const a = Math.max(winStart, Number(seg[0]));
    const b = Math.min(winEnd, Number(seg[1]));
    if (b > a) {
      const x1 = Math.max(1, Math.min(w - 1, ((a - winStart) / span) * w));
      const x2 = Math.max(1, Math.min(w - 1, ((b - winStart) / span) * w));
      const segW = Math.min(w - x1 - 1, Math.max(2, x2 - x1));
      ctx.fillRect(x1, barY + 2, segW, barH - 4);
    }
  }

  // Playhead cursor line with diamond tip
  if (effectiveNow >= winStart && effectiveNow <= winEnd) {
    const nx = Math.max(3, Math.min(w - 3, ((effectiveNow - winStart) / span) * w));
    ctx.fillStyle = isLive ? playheadColor : textColor;
    ctx.fillRect(nx - 0.75, barY - 2, 1.5, barH + 4);
    if (isLive) {
      ctx.beginPath();
      ctx.moveTo(nx, barY - 3);
      ctx.lineTo(nx + 3, barY);
      ctx.lineTo(nx, barY + 3);
      ctx.lineTo(nx - 3, barY);
      ctx.closePath();
      ctx.fill();
    }
  }

  // Ruler scale numbers
  ctx.fillStyle = textColor;
  ctx.font = "9px 'JetBrains Mono', ui-monospace, monospace";
  ctx.textBaseline = "top";
  for (let i = 0; i < 4; i++) {
    const frac = i / 3;
    const lbl = formatClockFromTs(winStart + frac * span);
    if (i === 0) {
      ctx.textAlign = "left";
      ctx.fillText(lbl, 0, barY + barH + 4);
    } else if (i === 3) {
      ctx.textAlign = "right";
      ctx.fillText(lbl, w, barY + barH + 4);
    } else {
      ctx.textAlign = "center";
      ctx.fillText(lbl, frac * w, barY + barH + 4);
    }
  }

  ctx.restore();
}

// =============================================================================
// 7-Day Attendo Horizon Vertical Bar Matrix (Read-only official Attendo view)
// =============================================================================

function renderAttendoBarMatrix(data, todayNet, pNet, targetH) {
  if (!dom.attendoBarMatrix) return;

  const linked = data.linked_accounts || {};
  const pp = data.period_progress || {};
  const todayIso = campusTodayIso(Number(data.now || Date.now() / 1000));
  const officialPeriod = linked.current_period || (linked.attendo_linked ? linked.previous_period : null);

  let cols = [];
  if (officialPeriod && Array.isArray(officialPeriod.days) && officialPeriod.days.length > 0) {
    const daysCopy = officialPeriod.days.map((d) => ({
      date: d.date,
      hours: d.date === todayIso ? Math.max(Number(d.hours || 0), todayNet / 3600) : Number(d.hours || 0),
      counted: Boolean(d.counted),
      isToday: d.date === todayIso,
      isPlaceholder: false,
    }));
    const countedCount = daysCopy.filter((d) => d.counted).length;
    const neededPlaceholders = Math.max(0, 7 - countedCount);
    let nextDate = daysCopy[daysCopy.length - 1]?.date || todayIso;
    cols = [...daysCopy];
    // Pad upcoming open slots so horizon stays balanced up to 7 columns minimum
    while (cols.length < 7 && cols.filter((c) => !c.isPlaceholder || true).length < daysCopy.length + neededPlaceholders) {
      nextDate = addDaysIso(nextDate, 1);
      cols.push({
        date: nextDate,
        hours: nextDate === todayIso ? todayNet / 3600 : 0,
        counted: nextDate === todayIso && todayNet > 0,
        isToday: nextDate === todayIso,
        isPlaceholder: true,
      });
    }
  } else if (pp.start) {
    for (let i = 0; i < 7; i++) {
      const dStr = addDaysIso(pp.start, i);
      const isToday = dStr === todayIso;
      const hrs = isToday ? todayNet / 3600 : 0;
      cols.push({
        date: dStr,
        hours: hrs,
        counted: isToday && hrs > 0,
        isToday,
        isPlaceholder: dStr > todayIso,
      });
    }
  }

  const maxHrs = Math.max(6, targetH / 7 * 1.4, ...cols.map((c) => c.hours));

  dom.attendoBarMatrix.innerHTML = cols
    .map((c) => {
      const pctH = c.hours > 0 ? Math.max(14, Math.min(100, (c.hours / maxHrs) * 100)) : 0;
      const dayNum = c.date.slice(8, 10);
      const hrsText = c.hours >= 0.1 ? `${c.hours.toFixed(1)}` : (c.isToday ? "0.0" : "·");
      const cls = [
        "bar-col",
        c.isToday ? "is-today" : "",
        c.counted ? "is-counted" : "",
      ]
        .filter(Boolean)
        .join(" ");
      const tip = c.isPlaceholder
        ? `${c.date}`
        : `${c.date} · ${fmtCompactHours(c.hours * 3600)} · ${tr(c.counted ? "status_counted" : "status_not_counted")}`;

      return `
        <div class="${cls}" title="${escapeHtml(tip)}">
          <span class="bar-hrs">${hrsText}</span>
          <div class="bar-well">
            <div class="bar-fill" style="height: ${pctH.toFixed(0)}%"></div>
          </div>
          <span class="bar-day-lbl">${dayNum}</span>
        </div>`;
    })
    .join("");
}

// =============================================================================
// Navigation
// =============================================================================

function switchTab(tabName) {
  settings.activeTab = tabName;
  chrome.storage.local.set({ activeTab: tabName });

  [
    { name: "overview", btn: dom.navBtnOverview, page: dom.pageOverview },
    { name: "sessions", btn: dom.navBtnSessions, page: dom.pageSessions },
    { name: "settings", btn: dom.navBtnSettings, page: dom.pageSettings },
  ].forEach((t) => {
    const isActive = t.name === tabName;
    t.btn?.classList.toggle("active", isActive);
    t.btn?.setAttribute("aria-selected", isActive ? "true" : "false");
    t.page?.classList.toggle("hidden", !isActive);
  });

  if (tabName === "settings") {
    syncSettingsFormFromState();
  } else if (tabName === "overview" && lastPayload) {
    requestAnimationFrame(() => updateUI(lastPayload));
  } else if (tabName === "sessions" && lastPayload) {
    renderHistorySubTab();
  }
}

function switchHistoryTab(subTab) {
  settings.historyTab = subTab;
  chrome.storage.local.set({ historyTab: subTab });
  renderHistorySubTab();
}

// =============================================================================
// UI Rendering
// =============================================================================

function updateUI(data) {
  if (!data) return;

  const nowMs = Date.now();
  const cur = data.current_session;
  const isLive = Boolean(cur && cur.live);
  const lockedNow = Boolean(isLive && cur.locked_now);
  const elapsed = isLive && fetchedAtMs > 0 ? Math.max(0, (nowMs - fetchedAtMs) / 1000) : 0;
  const addNet = lockedNow ? 0 : elapsed;
  const addLock = lockedNow ? elapsed : 0;

  // Identity header
  const linked = data.linked_accounts || {};
  const loginName = (linked.login || cur?.username || settings.intraLogin || "student").toUpperCase();
  setNodeText(dom.userHandle, loginName);
  setNodeText(dom.hostChip, cur && cur.host ? `${cur.host.split(".")[0]}:${cur.session_id || ""}` : "local");

  if (dom.liveBeacon && dom.statusWord) {
    dom.liveBeacon.className = "beacon";
    dom.statusWord.className = "status-word";
    if (isLive) {
      if (lockedNow) {
        dom.liveBeacon.classList.add("locked");
        dom.statusWord.classList.add("locked");
        setNodeText(dom.statusWord, tr("status_locked"));
      } else {
        dom.liveBeacon.classList.add("active");
        dom.statusWord.classList.add("active");
        setNodeText(dom.statusWord, tr("status_active"));
      }
    } else {
      setNodeText(dom.statusWord, tr("status_idle"));
    }
  }

  // Hero Today values
  const eff = data.effective_today || {};
  const todayNet = Number(eff.net_seconds ?? data.today?.net_seconds ?? 0) + addNet;
  const todayGross = Number(eff.gross_seconds ?? data.today?.gross_seconds ?? 0) + elapsed;
  const todayLocked = Number(eff.locked_seconds ?? data.today?.locked_seconds ?? 0) + addLock;
  const curSessNet = cur ? Number(cur.net_sec || 0) + addNet : 0;

  setNodeText(dom.heroClock, fmtHms(todayNet));
  setNodeText(dom.valCurSess, fmtHms(curSessNet));
  setNodeText(dom.valGrossToday, fmtHms(todayGross));
  setNodeText(dom.valLockedToday, fmtHms(todayLocked));

  const expHrs = Math.floor((todayNet + 1500) / 3600);
  if (dom.heroRoundingChip) {
    if (todayNet > 0) {
      setNodeText(dom.heroRoundingChip, `${expHrs}h`);
      dom.heroRoundingChip.classList.remove("hidden");
    } else {
      dom.heroRoundingChip.classList.add("hidden");
    }
  }

  // Daily Pace
  const dt = data.daily_target || {};
  const targetDailySec = Number(dt.daily_target_seconds || 0);
  const remPeriodHours = Number(dt.remaining_period_hours || 0);
  let remTodaySec = 0;
  let dailyFrac = 1.0;
  let dailyDone = true;

  if (remPeriodHours > 0 && targetDailySec > 0) {
    remTodaySec = Math.max(0, targetDailySec - todayNet);
    dailyDone = remTodaySec <= 0;
    dailyFrac = dailyDone ? 1.0 : Math.max(0, Math.min(1, todayNet / targetDailySec));
  }

  dom.heroPanel?.classList.toggle("goal-reached", dailyDone && !lockedNow);
  dom.heroPanel?.classList.toggle("locked-mode", lockedNow);

  if (dom.heroRingWrap && dom.heroRingArc && dom.heroRingPct) {
    dom.heroRingWrap.classList.toggle("done", dailyDone);
    dom.heroRingWrap.classList.toggle("locked", lockedNow && !dailyDone);
    const offset = DIAL_CIRCUMFERENCE * (1 - dailyFrac);
    dom.heroRingArc.style.strokeDashoffset = offset.toFixed(2);
    setNodeText(dom.heroRingPct, `${Math.round(dailyFrac * 100)}%`);
  }

  if (targetDailySec > 0 && dom.heroRatioLbl) {
    setNodeText(
      dom.heroRatioLbl,
      tr("active_of_target", {
        logged: fmtCompactHours(todayNet),
        target: fmtCompactHours(targetDailySec),
      })
    );
    dom.heroRatioLbl.classList.remove("hidden");
  } else if (dom.heroRatioLbl) {
    setNodeText(dom.heroRatioLbl, "");
    dom.heroRatioLbl.classList.add("hidden");
  }

  if (dailyDone) {
    setNodeText(dom.etaHeadline, tr("eta_done"));
    if (dom.paceLbl) dom.paceLbl.textContent = tr("pace_done_sub");
  } else if (lockedNow) {
    setNodeText(dom.etaHeadline, tr("eta_paused"));
    if (dom.paceLbl) {
      dom.paceLbl.innerHTML = tr("pace_locked_sub", { left: escapeHtml(fmtHm(remTodaySec)) });
    }
  } else {
    const nowSec = Number(data.now || nowMs / 1000) + elapsed;
    const etaStr = formatClockFromTs(nowSec + remTodaySec);
    setNodeText(dom.etaHeadline, tr("eta_prefix", { eta: etaStr }));
    if (dom.paceLbl) {
      dom.paceLbl.innerHTML = tr("pace_remaining", { left: escapeHtml(fmtHm(remTodaySec)) });
    }
  }

  // Cadence Canvas + Span label
  const tl = data.today_timeline;
  if (tl && dom.cadenceSpanLbl) {
    setNodeText(dom.cadenceSpanLbl, `${formatClockFromTs(tl.win_start)} — ${formatClockFromTs(tl.win_end)}`);
  }
  drawCadenceTimeline(dom.timelineCanvas, tl, Number(data.now || nowMs / 1000), isLive, lockedNow, elapsed);

  // Attendo Period + 7-Day Matrix
  const pp = data.period_progress || {};
  const targetH = Number(pp.target_hours || settings.periodTargetHours || 30);
  const pNet = Number(pp.net_seconds ?? data.period?.net_seconds ?? 0) + addNet;
  const pHours = pNet / 3600;
  const pPct = Math.min(100, (pHours / targetH) * 100);
  const leftHours = Math.max(0, targetH - pHours);

  const pStartStr = pp.start ? pp.start.slice(5, 10) : "—";
  const pEndStr = pp.end ? pp.end.slice(5, 10) : "—";
  setNodeText(dom.periodRangeLbl, tr("attendo_period_prefix", { start: pStartStr, end: pEndStr }));
  setNodeText(
    dom.periodNetLbl,
    tr("active_of_target", {
      logged: fmtCompactHours(pNet),
      target: fmtCompactHours(targetH * 3600),
    })
  );

  if (dom.periodStatusLbl) {
    dom.periodStatusLbl.classList.toggle("done", pHours >= targetH);
    setNodeText(dom.periodStatusLbl, pHours >= targetH ? tr("goal_reached_text") : `${Math.round(pPct)}%`);
  }

  if (dom.periodLeftLbl) {
    if (pHours >= targetH || leftHours <= 0) {
      setNodeText(dom.periodLeftLbl, "");
      dom.periodLeftLbl.classList.add("hidden");
    } else {
      setNodeText(dom.periodLeftLbl, `${fmtCompactHours(leftHours * 3600)} ${tr("period_left")}`);
      dom.periodLeftLbl.classList.remove("hidden");
    }
  }

  renderAttendoBarMatrix(data, todayNet, pNet, targetH);

  // Campus Dock
  if (dom.intraConnDot) {
    dom.intraConnDot.className = `dock-dot ${linked.intra_linked ? "online" : "offline"}`;
  }
  if (linked.intra_linked) {
    setNodeText(dom.intraValLbl, fmtCompactHours(Number(linked.intra_today_seconds || 0) + elapsed));
    setNodeText(dom.intraSubLbl, tr("today_lower"));
    dom.intraLinkBtn?.classList.add("hidden");
  } else {
    setNodeText(dom.intraValLbl, "—");
    setNodeText(dom.intraSubLbl, tr("not_linked_badge"));
    dom.intraLinkBtn?.classList.remove("hidden");
  }

  const displayAttendoPeriod = linked.current_period || (linked.attendo_linked ? linked.previous_period : null);
  if (dom.attendoConnDot) {
    dom.attendoConnDot.className = `dock-dot ${linked.attendo_linked ? "online" : "offline"}`;
  }
  if (linked.attendo_linked && displayAttendoPeriod) {
    setNodeText(dom.attendoValLbl, fmtCompactHours(Number(displayAttendoPeriod.total || 0) * 3600));
    setNodeText(dom.attendoDaysLbl, tr("days_of_seven", { counted: Number(displayAttendoPeriod.counted_days || 0) }));
    dom.attendoLinkBtn?.classList.add("hidden");
  } else {
    setNodeText(dom.attendoValLbl, "—");
    setNodeText(dom.attendoDaysLbl, tr("not_linked_badge"));
    dom.attendoLinkBtn?.classList.remove("hidden");
  }

  // Setup Status
  if (dom.accStatusLbl) {
    const iB = tr(linked.intra_linked ? "linked_badge" : "not_linked_badge");
    const aB = tr(linked.attendo_linked ? "linked_badge" : "not_linked_badge");
    setNodeText(dom.accStatusLbl, `Intra: ${iB} · Attendo: ${aB}`);
  }

  // Logs KPIs
  const weekSec = Number(data.week?.net_seconds || 0) + addNet;
  const monthSec = Number(data.month?.net_seconds || 0) + addNet;
  setNodeText(dom.valWeekHours, fmtCompactHours(weekSec));
  setNodeText(dom.valWeekClock, fmtHms(weekSec));
  setNodeText(dom.valMonthHours, fmtCompactHours(monthSec));
  setNodeText(dom.valMonthClock, fmtHms(monthSec));

  if (settings.activeTab === "sessions") {
    renderHistorySubTab(todayNet, todayLocked, pNet, targetH);
  }
}

function renderHistorySubTab(todayNetOverride, todayLockedOverride, pNetOverride, targetHOverride) {
  const data = lastPayload;
  const activeSub = settings.historyTab || "sessions";

  [
    { id: "sessions", el: dom.htabSessions },
    { id: "periods", el: dom.htabPeriods },
    { id: "locks", el: dom.htabLocks },
  ].forEach((t) => {
    const isSel = t.id === activeSub;
    t.el?.classList.toggle("active", isSel);
    t.el?.setAttribute("aria-selected", isSel ? "true" : "false");
  });

  if (!data || !dom.historyRowsBox) return;

  const cur = data.current_session;
  const isLive = Boolean(cur && cur.live);
  const lockedNow = Boolean(isLive && cur.locked_now);
  const elapsed = isLive && fetchedAtMs > 0 ? Math.max(0, (Date.now() - fetchedAtMs) / 1000) : 0;
  const addNet = lockedNow ? 0 : elapsed;
  const addLock = lockedNow ? elapsed : 0;

  if (activeSub === "sessions") {
    dom.historySummaryProgressWrap?.classList.add("hidden");
    const sessions = data.recent_sessions || [];
    const todayLocked = todayLockedOverride ?? (Number(data.effective_today?.locked_seconds ?? data.today?.locked_seconds ?? 0) + addLock);

    setNodeText(dom.historySummaryTitle, tr("tab_sessions").toUpperCase());
    setNodeText(
      dom.historySummaryDetail,
      tr("sessions_summary_fmt", {
        count: sessions.length,
        locked: fmtHm(todayLocked),
      })
    );

    if (!sessions.length) {
      dom.historyRowsBox.innerHTML = `<div class="empty-msg">${escapeHtml(tr("no_sessions_data"))}</div>`;
      return;
    }

    dom.historyRowsBox.innerHTML = sessions
      .map((s) => {
        const hostShort = escapeHtml((s.host || "").split(".")[0] || "x11");
        const netSec = Number(s.net_sec || 0) + (s.live ? addNet : 0);
        const endStr = s.live ? tr("status_live") : s.end_hms;
        const rowClass = s.live ? "ledger-row live-row" : "ledger-row";
        return `
          <div class="${rowClass}">
            <div class="ledger-left">
              <span class="ledger-title ltr">${escapeHtml(s.date)} · ${hostShort}</span>
              <span class="ledger-meta ltr">${escapeHtml(s.start_hm)} → ${escapeHtml(endStr)}</span>
            </div>
            <div class="ledger-right">
              <span class="ledger-dur ltr ${s.live ? "val-green" : ""}">${fmtHms(netSec)}</span>
              ${s.live ? `<span class="badge-state ok">${escapeHtml(tr("status_live"))}</span>` : ""}
            </div>
          </div>`;
      })
      .join("");
  } else if (activeSub === "periods") {
    const linked = data.linked_accounts || {};
    const pp = data.period_progress || {};
    const cp = linked.current_period;
    const periods = [];
    if (cp) periods.push(cp);
    if (linked.previous_period) periods.push(linked.previous_period);

    const pNet = pNetOverride ?? (Number(pp.net_seconds ?? data.period?.net_seconds ?? 0) + addNet);
    const targetH = targetHOverride ?? Number(pp.target_hours || settings.periodTargetHours || 30);
    const pct = Math.min(100, Math.max(0, (pNet / 3600 / targetH) * 100));

    setNodeText(dom.historySummaryTitle, `${tr("current_period_card")} · ${pp.start || "—"}`);
    setNodeText(
      dom.historySummaryDetail,
      tr("period_summary_fmt", {
        total: fmtCompactHours(pNet),
        target: fmtCompactHours(targetH * 3600),
        counted: cp ? cp.counted_days : (linked.previous_period?.counted_days || 0),
      })
    );
    dom.historySummaryProgressWrap?.classList.remove("hidden");
    if (dom.historySummaryProgress) {
      dom.historySummaryProgress.style.width = `${pct.toFixed(1)}%`;
      dom.historySummaryProgress.classList.toggle("complete", pct >= 100);
    }

    if (!periods.length) {
      dom.historyRowsBox.innerHTML = `<div class="empty-msg">${escapeHtml(tr("no_periods_data"))}</div>`;
      return;
    }

    const todayIso = campusTodayIso(Number(data.now || Date.now() / 1000));
    const allDays = [];
    for (const period of periods) {
      const sortedDays = [...(period.days || [])].sort((a, b) => b.date.localeCompare(a.date));
      for (const d of sortedDays) {
        allDays.push({ ...d, periodLabel: period.label || "" });
      }
    }

    dom.historyRowsBox.innerHTML = allDays
      .map((d) => {
        const isToday = d.date === todayIso;
        const rowClass = isToday ? "ledger-row today-row" : "ledger-row";
        const dateLabel = isToday ? `★ ${d.date}` : d.date;
        const hrs = fmtCompactHours(Number(d.hours || 0) * 3600);
        const statusCls = d.counted ? "badge-state ok" : "badge-state";
        const statusTxt = tr(d.counted ? "status_counted" : "status_not_counted");
        return `
          <div class="${rowClass}">
            <div class="ledger-left">
              <span class="ledger-title ltr">${escapeHtml(dateLabel)}</span>
              <span class="ledger-meta">${escapeHtml(d.periodLabel)}</span>
            </div>
            <div class="ledger-right">
              <span class="ledger-dur ltr">${escapeHtml(hrs)}</span>
              <span class="${statusCls}">${escapeHtml(statusTxt)}</span>
            </div>
          </div>`;
      })
      .join("");
  } else {
    dom.historySummaryProgressWrap?.classList.add("hidden");
    const locks = [...(data.today_locks || [])].reverse();
    const totalLocked = todayLockedOverride ?? (Number(data.today?.locked_seconds || 0) + addLock);

    setNodeText(dom.historySummaryTitle, tr("tab_locks").toUpperCase());
    setNodeText(
      dom.historySummaryDetail,
      tr("lock_summary_fmt", {
        count: locks.length,
        total: fmtHm(totalLocked),
      })
    );

    if (!locks.length) {
      dom.historyRowsBox.innerHTML = `<div class="empty-msg">${escapeHtml(tr("no_locks_day"))}</div>`;
      return;
    }

    dom.historyRowsBox.innerHTML = locks
      .map((lk) => {
        const statusCls = lk.ongoing ? "badge-state warn" : "badge-state";
        const statusTxt = tr(lk.ongoing ? "status_ongoing" : "status_completed");
        const sec = Number(lk.seconds || 0) + (lk.ongoing ? addLock : 0);
        return `
          <div class="ledger-row">
            <span class="ledger-dur ltr">${escapeHtml(lk.start)} → ${escapeHtml(lk.end)}</span>
            <div class="ledger-right">
              <span class="ledger-dur val-amber ltr">${fmtHms(sec)}</span>
              <span class="${statusCls}">${escapeHtml(statusTxt)}</span>
            </div>
          </div>`;
      })
      .join("");
  }
}

// =============================================================================
// Brave MV3 Cookie Helper + Native Messaging Bridge
// =============================================================================

async function gatherBraveSessionCookies(browserPref) {
  if (browserPref !== "auto" && browserPref !== "brave") {
    return { attendoCookie: "", intraCookie: "" };
  }
  if (!chrome.cookies || !chrome.cookies.getAll) {
    return { attendoCookie: "", intraCookie: "" };
  }
  try {
    const [attList, intraList] = await Promise.all([
      chrome.cookies.getAll({ url: "https://attendo.1337.ma/students/profile" }).catch(() => []),
      chrome.cookies.getAll({ url: "https://translate.intra.42.fr/" }).catch(() => []),
    ]);

    let attendoCookie = "";
    if (attList.some((c) => c.name === "student_token" && c.value)) {
      attendoCookie = attList.map((c) => `${c.name}=${c.value}`).join("; ");
    }

    let intraCookie = "";
    if (intraList.some((c) => c.name === "_intra_42_session_production" && c.value)) {
      intraCookie = intraList.map((c) => `${c.name}=${c.value}`).join("; ");
    }

    return { attendoCookie, intraCookie };
  } catch {
    return { attendoCookie: "", intraCookie: "" };
  }
}

async function requestHostSync(forceRefresh = false, draftOverrides = null) {
  dom.refreshBtn?.classList.add("spinning");

  const useBrowser = draftOverrides?.browserPreference ?? settings.browserPreference ?? "auto";
  const useLogin = draftOverrides?.intraLogin ?? settings.intraLogin ?? "";
  const useToken = draftOverrides?.attendoToken ?? settings.attendoToken ?? "";
  const useTarget = draftOverrides?.periodTargetHours ?? settings.periodTargetHours ?? 30;

  const { attendoCookie, intraCookie } = await gatherBraveSessionCookies(useBrowser);

  try {
    const port = chrome.runtime.connectNative(HOST_NAME);

    port.onMessage.addListener((response) => {
      dom.refreshBtn?.classList.remove("spinning");
      if (!response) {
        showError("Received empty response from Native Messaging host.");
        return;
      }
      if (response.error) {
        showError(`Host error: ${response.error}`);
        return;
      }
      clearError();
      lastPayload = response;
      fetchedAtMs = Date.now();

      chrome.storage.local.set({ cached_state_v4: response });
      updateUI(response);
      port.disconnect();
    });

    port.onDisconnect.addListener(() => {
      dom.refreshBtn?.classList.remove("spinning");
      const err = chrome.runtime.lastError?.message;
      if (err) {
        showError(`Host disconnected: ${err}`);
      }
    });

    port.postMessage({
      type: "sync",
      browserPreference: useBrowser,
      login: useLogin,
      attendoToken: useToken,
      targetHours: useTarget,
      browserAttendoCookie: attendoCookie,
      browserIntraCookie: intraCookie,
      forceRefresh: Boolean(forceRefresh),
    });
  } catch (err) {
    dom.refreshBtn?.classList.remove("spinning");
    showError(`Native messaging failed: ${err.message}`);
  }
}

// =============================================================================
// Event Handlers & Init
// =============================================================================

function setupEventHandlers() {
  dom.navBtnOverview?.addEventListener("click", () => switchTab("overview"));
  dom.navBtnSessions?.addEventListener("click", () => switchTab("sessions"));
  dom.navBtnSettings?.addEventListener("click", () => switchTab("settings"));

  dom.htabSessions?.addEventListener("click", () => switchHistoryTab("sessions"));
  dom.htabPeriods?.addEventListener("click", () => switchHistoryTab("periods"));
  dom.htabLocks?.addEventListener("click", () => switchHistoryTab("locks"));

  dom.refreshBtn?.addEventListener("click", () => requestHostSync(true));

  dom.themeQuickBtn?.addEventListener("click", () => {
    settings.theme = settings.theme === "paper" ? "carbon" : "paper";
    chrome.storage.local.set({ theme: settings.theme });
    applyTheme();
    if (lastPayload) updateUI(lastPayload);
  });

  document.querySelectorAll(".theme-btn").forEach((btn) => {
    btn.addEventListener("click", () => {
      const t = btn.getAttribute("data-theme-choice") || "carbon";
      settings.theme = t;
      chrome.storage.local.set({ theme: t });
      applyTheme();
      if (lastPayload) updateUI(lastPayload);
    });
  });

  dom.syncNowBtn?.addEventListener("click", () => {
    const rawTarget = Number(dom.settingTargetHours?.value || settings.periodTargetHours || 30);
    requestHostSync(true, {
      browserPreference: draftBrowserPref,
      intraLogin: (dom.settingIntraLogin?.value || "").trim(),
      attendoToken: (dom.settingAttendoToken?.value || "").trim(),
      periodTargetHours: Math.max(1, Math.min(200, isNaN(rawTarget) ? 30 : rawTarget)),
    });
  });

  document.querySelectorAll(".lang-btn").forEach((btn) => {
    btn.addEventListener("click", () => {
      const lang = btn.getAttribute("data-lang");
      if (!lang || lang === settings.language) return;
      settings.language = lang;
      chrome.storage.local.set({ language: lang });
      applyLanguage();
      if (lastPayload) updateUI(lastPayload);
    });
  });

  document.querySelectorAll(".browser-btn").forEach((btn) => {
    btn.addEventListener("click", () => {
      updateBrowserButtons(btn.getAttribute("data-browser") || "auto");
    });
  });

  dom.cancelSettingsBtn?.addEventListener("click", () => {
    syncSettingsFormFromState();
    switchTab("overview");
  });

  dom.saveSettingsBtn?.addEventListener("click", () => {
    settings.browserPreference = draftBrowserPref;
    settings.intraLogin = (dom.settingIntraLogin?.value || "").trim();
    settings.attendoToken = (dom.settingAttendoToken?.value || "").trim();
    const rawTarget = Number(dom.settingTargetHours?.value || 30);
    settings.periodTargetHours = Math.max(1, Math.min(200, isNaN(rawTarget) ? 30 : rawTarget));

    chrome.storage.local.set({
      browserPreference: settings.browserPreference,
      intraLogin: settings.intraLogin,
      attendoToken: settings.attendoToken,
      periodTargetHours: settings.periodTargetHours,
    });

    switchTab("overview");
    requestHostSync(true);
  });
}

document.addEventListener("DOMContentLoaded", () => {
  initDomHandles();
  setupEventHandlers();

  chrome.storage.local.get(
    [
      "theme",
      "language",
      "browserPreference",
      "intraLogin",
      "attendoToken",
      "periodTargetHours",
      "targetHours",
      "activeTab",
      "historyTab",
      "cached_state_v4",
    ],
    (items) => {
      if (items.theme) settings.theme = items.theme;
      if (items.language) settings.language = items.language;
      if (items.browserPreference) settings.browserPreference = items.browserPreference;
      if (items.intraLogin !== undefined) settings.intraLogin = items.intraLogin;
      if (items.attendoToken !== undefined) settings.attendoToken = items.attendoToken;

      if (items.periodTargetHours !== undefined) {
        settings.periodTargetHours = Number(items.periodTargetHours) || 30;
      } else if (items.targetHours !== undefined) {
        settings.periodTargetHours = Number(items.targetHours) || 30;
      }

      if (items.activeTab) settings.activeTab = items.activeTab;
      if (items.historyTab) settings.historyTab = items.historyTab;

      applyTheme();
      applyLanguage();
      syncSettingsFormFromState();
      switchTab(settings.activeTab || "overview");

      if (items.cached_state_v4) {
        lastPayload = items.cached_state_v4;
        fetchedAtMs = Date.now();
        updateUI(items.cached_state_v4);
      }

      requestHostSync(false);

      if (!tickTimer) {
        tickTimer = setInterval(() => {
          if (lastPayload) updateUI(lastPayload);
        }, 1000);
      }
    }
  );
});
EOF

# 7. Write Native Messaging Host Python executable
cat > "$HOST_BIN" << 'PYEOF'
#!/usr/bin/env python3
"""Unified Native Messaging host mixing live_estimate + xattendo-widget approaches.

Features:
1. Executes live_estimate.py --json to update sessions.json (preserving 100% of ledger history).
2. Merges read-only lock archives (~/.local/state/logged-time/) without mutating them.
3. Reads browser cookies directly (Chromium AES-CBC + Firefox) AND accepts decrypted cookies from Brave MV3 extension.
4. Syncs official 1337 Attendo periods & 42 Intra locations_stats.json with smart 60s disk cache & 3.5s timeouts.
5. Computes Xattendo's fused Today metrics, Attendo Period progress, Daily Average Target + ETA clock, 35m rounding expected hours, and active DayTimeline segments.
"""

from __future__ import annotations

import configparser
from datetime import date, datetime, time as dt_time, timedelta
import getpass
import hashlib
from html.parser import HTMLParser
from http.cookiejar import Cookie, CookieJar
import json
import math
import os
from pathlib import Path
import re
import shutil
import sqlite3
import struct
import subprocess
import sys
import tempfile
import time
from typing import Any, Dict, Iterable, List, Optional, Tuple
import urllib.error
from urllib.parse import quote
import urllib.request
from zoneinfo import ZoneInfo

from cryptography.hazmat.primitives import padding
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

CAMPUS_TIMEZONE = "Africa/Casablanca"
ATTENDANCE_ROUNDING_OFFSET_SECONDS = (60 - 35) * 60  # 1500s: 35m past hour rounds up
DEFAULT_PERIOD_TARGET_HOURS = 30.0
ATTENDO_PROFILE_URL = "https://attendo.1337.ma/students/profile"
INTRA_HOST = "translate.intra.42.fr"
INTRA_ORIGIN = "https://profile.intra.42.fr"
USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/157.0.0.0 Safari/537.36"
)

DATA_DIR = Path.home() / ".local" / "share" / "live_estimate"
LEDGER_PATH = DATA_DIR / "sessions.json"
CACHE_PATH = DATA_DIR / "accounts_cache.json"
SHARED_HISTORY_DB = Path.home() / ".local" / "state" / "logged-time" / "history" / "locks.sqlite3"
LEGACY_ARCHIVE_DB = Path.home() / ".local" / "state" / "logged-time" / "locks.sqlite3"
LIVE_ESTIMATE_SCRIPT = Path.home() / ".local" / "bin" / "live_estimate.py"
CACHE_TTL_SECONDS = 60.0


def campus_zone() -> ZoneInfo:
    try:
        return ZoneInfo(CAMPUS_TIMEZONE)
    except Exception:
        return ZoneInfo("UTC")


def campus_now(now_dt: datetime | None = None) -> datetime:
    tz = campus_zone()
    if now_dt is None:
        return datetime.now(tz)
    if now_dt.tzinfo is None:
        return now_dt.replace(tzinfo=tz)
    return now_dt.astimezone(tz)


def campus_today(now_dt: datetime | None = None) -> date:
    return campus_now(now_dt).date()


def attendo_period_bounds(now_dt: datetime | None = None) -> Tuple[date, date]:
    """Return (start_date, end_date) for 7-day Thu-Wed Attendo period containing now_dt."""
    cur = campus_today(now_dt)
    days_since_thu = (cur.weekday() - 3) % 7
    start_d = cur - timedelta(days=days_since_thu)
    end_d = start_d + timedelta(days=6)
    return (start_d, end_d)


# ==============================================================================
# Native Messaging Transport
# ==============================================================================

def read_message() -> dict[str, Any] | None:
    raw_len = sys.stdin.buffer.read(4)
    if not raw_len or len(raw_len) < 4:
        return None
    msg_len = struct.unpack("<I", raw_len)[0]
    if msg_len <= 0 or msg_len > 1024 * 1024:
        return None
    data = sys.stdin.buffer.read(msg_len).decode("utf-8")
    return json.loads(data)


def send_message(payload: dict[str, Any]) -> None:
    encoded = json.dumps(payload).encode("utf-8")
    sys.stdout.buffer.write(struct.pack("<I", len(encoded)))
    sys.stdout.buffer.write(encoded)
    sys.stdout.buffer.flush()


# ==============================================================================
# Browser Cookie Extraction (Pure Python from xattendo-widget)
# ==============================================================================

def _firefox_profiles() -> List[Path]:
    home = Path.home()
    roots = (
        Path(os.environ.get("XDG_CONFIG_HOME") or home / ".config") / "mozilla/firefox",
        home / ".mozilla/firefox",
        home / "snap/firefox/common/.mozilla/firefox",
        home / ".var/app/org.mozilla.firefox/config/mozilla/firefox",
    )
    profiles: List[Path] = []
    for root in roots:
        ini = root / "profiles.ini"
        if ini.is_file():
            cfg = configparser.ConfigParser()
            try:
                cfg.read(ini)
                sections = sorted(
                    (s for s in cfg.sections() if s.startswith("Profile")),
                    key=lambda s: cfg.getboolean(s, "Default", fallback=False),
                    reverse=True,
                )
                for sec in sections:
                    val = cfg.get(sec, "Path", fallback="")
                    if not val:
                        continue
                    path = Path(val).expanduser()
                    if cfg.getboolean(sec, "IsRelative", fallback=True):
                        path = root / path
                    if path not in profiles:
                        profiles.append(path)
            except (configparser.Error, OSError):
                pass
        if root.is_dir():
            for path in root.glob("*.default*"):
                if path.is_dir() and path not in profiles:
                    profiles.append(path)
    return profiles


def _chromium_cookie_files(browser: str) -> List[Path]:
    home = Path.home()
    cfg = Path(os.environ.get("XDG_CONFIG_HOME") or home / ".config")
    if browser == "brave":
        roots = [
            cfg / "BraveSoftware/Brave-Browser",
            home / ".var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser",
            home / "snap/brave/current/.config/BraveSoftware/Brave-Browser",
        ]
    elif browser == "chrome":
        roots = [
            cfg / "google-chrome",
            cfg / "google-chrome-beta",
            home / ".var/app/com.google.Chrome/config/google-chrome",
        ]
    else:
        roots = [
            cfg / "chromium",
            home / "snap/chromium/common/chromium",
        ]
    files: List[Path] = []
    for root in roots:
        for profile in [root / "Default", *sorted(root.glob("Profile *"))]:
            for db in (profile / "Network/Cookies", profile / "Cookies"):
                if db.is_file():
                    files.append(db)
    return files


def _derive_chromium_key(secret: bytes) -> bytes:
    return hashlib.pbkdf2_hmac("sha1", secret, b"saltysalt", 1, 16)


_KEYRING_CACHE: Dict[str, bytes] = {}


def _get_keyring_secret(browser: str) -> bytes:
    if browser in _KEYRING_CACHE:
        return _KEYRING_CACHE[browser]
    app_names = {
        "brave": ("Brave Safe Storage", "brave"),
        "chrome": ("Chrome Safe Storage", "chrome"),
        "chromium": ("Chromium Safe Storage", "chromium"),
    }.get(browser, ("Chrome Safe Storage",))
    secret = b"peanuts"
    try:
        import secretstorage  # type: ignore

        bus = secretstorage.dbus_init()
        collection = secretstorage.get_default_collection(bus)
        if not collection.is_locked():
            for item in collection.get_all_items():
                attrs = item.get_attributes()
                label = item.get_label()
                if label in app_names or attrs.get("application") in app_names:
                    sec = item.get_secret()
                    if sec:
                        secret = sec
                        break
    except Exception:
        pass
    _KEYRING_CACHE[browser] = secret
    return secret


def decrypt_chromium_value(encrypted_value: bytes, key: bytes, db_version: int = 24) -> str:
    if not encrypted_value:
        return ""
    prefix = encrypted_value[:3]
    if prefix not in (b"v10", b"v11"):
        return encrypted_value.decode("utf-8", errors="replace")

    ciphertext = encrypted_value[3:]
    if not ciphertext or (len(ciphertext) % 16) != 0:
        return ""

    cipher = Cipher(algorithms.AES(key), modes.CBC(b" " * 16))
    decryptor = cipher.decryptor()
    padded = decryptor.update(ciphertext) + decryptor.finalize()
    unpadder = padding.PKCS7(128).unpadder()
    raw = unpadder.update(padded) + unpadder.finalize()

    if db_version >= 24 and len(raw) >= 32:
        raw = raw[32:]
    text = raw.decode("utf-8", errors="replace")
    if not text or any(ord(ch) < 0x20 or ord(ch) > 0x7E for ch in text):
        return ""
    return text


def _chromium_expiry_to_unix(expires_utc: int) -> Optional[int]:
    if not expires_utc:
        return None
    unix_sec = int(expires_utc / 1_000_000 - 11644473600)
    return unix_sec if unix_sec > 0 else None


def _query_sqlite_readonly(db_path: Path, query_fn: Any) -> Any:
    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=1)
        try:
            return query_fn(conn)
        finally:
            conn.close()
    except (OSError, sqlite3.Error):
        try:
            with tempfile.TemporaryDirectory() as tmpdir:
                snap = Path(tmpdir) / db_path.name
                shutil.copy2(db_path, snap)
                wal = db_path.with_name(f"{db_path.name}-wal")
                if wal.is_file():
                    shutil.copy2(wal, snap.with_name(f"{snap.name}-wal"))
                conn = sqlite3.connect(f"file:{snap}?mode=ro", uri=True, timeout=1)
                try:
                    return query_fn(conn)
                finally:
                    conn.close()
        except (OSError, sqlite3.Error):
            return None


def _browser_order(browser_pref: str) -> Tuple[str, ...]:
    pref = (browser_pref or "auto").strip().lower()
    if pref in ("brave", "firefox", "chrome"):
        return (pref,)
    return ("brave", "firefox", "chrome")


def _read_firefox_cookies(domain_suffixes: Iterable[str]) -> List[Cookie]:
    now = int(time.time())
    suffixes = tuple(domain_suffixes)
    found: List[Cookie] = []
    for profile in _firefox_profiles():
        db_path = profile / "cookies.sqlite"
        if not db_path.is_file():
            continue

        def _q(conn: sqlite3.Connection):
            return conn.execute(
                "SELECT host, path, isSecure, expiry, name, value FROM moz_cookies"
            ).fetchall()

        rows = _query_sqlite_readonly(db_path, _q)
        if not rows:
            continue
        for host, path, is_sec, expiry, name, value in rows:
            clean_host = str(host or "").lstrip(".")
            if not any(clean_host == s or clean_host.endswith("." + s) for s in suffixes):
                continue
            exp = int(expiry) if expiry else None
            if exp is not None and exp <= now:
                continue
            found.append(
                Cookie(
                    version=0,
                    name=str(name),
                    value=str(value or ""),
                    port=None,
                    port_specified=False,
                    domain=str(host),
                    domain_specified=str(host).startswith("."),
                    domain_initial_dot=str(host).startswith("."),
                    path=str(path or "/"),
                    path_specified=True,
                    secure=bool(is_sec),
                    expires=exp,
                    discard=exp is None,
                    comment=None,
                    comment_url=None,
                    rest={},
                )
            )
    return found


def _read_chromium_db_version(conn: sqlite3.Connection) -> int:
    try:
        row = conn.execute("SELECT value FROM meta WHERE key = 'version'").fetchone()
        if row and row[0] is not None:
            return int(row[0])
    except sqlite3.Error:
        pass
    return 0


def _read_chromium_cookies_by_profile(browser: str, domain_suffixes: Iterable[str]) -> List[List[Cookie]]:
    now = int(time.time())
    suffixes = tuple(domain_suffixes)
    per_profile: List[List[Cookie]] = []
    v10_key = _derive_chromium_key(b"peanuts")
    v11_key: Optional[bytes] = None

    for db_path in _chromium_cookie_files(browser):
        def _q(conn: sqlite3.Connection):
            db_ver = _read_chromium_db_version(conn)
            rows = conn.execute(
                "SELECT host_key, path, is_secure, expires_utc, name, value, encrypted_value FROM cookies"
            ).fetchall()
            return (db_ver, rows)

        res = _query_sqlite_readonly(db_path, _q)
        if not res:
            continue
        db_ver, rows = res
        profile_cookies: List[Cookie] = []
        for host, path, is_sec, exp_utc, name, plain_val, enc_val in rows:
            clean_host = str(host or "").lstrip(".")
            if not any(clean_host == s or clean_host.endswith("." + s) for s in suffixes):
                continue
            exp = _chromium_expiry_to_unix(int(exp_utc or 0))
            if exp is not None and exp <= now:
                continue
            val = str(plain_val or "")
            if not val and enc_val:
                blob = bytes(enc_val)
                if blob.startswith(b"v11"):
                    if v11_key is None:
                        v11_key = _derive_chromium_key(_get_keyring_secret(browser))
                    key = v11_key
                else:
                    key = v10_key
                try:
                    val = decrypt_chromium_value(blob, key, db_ver)
                except Exception:
                    continue
            if not val:
                continue
            profile_cookies.append(
                Cookie(
                    version=0,
                    name=str(name),
                    value=val,
                    port=None,
                    port_specified=False,
                    domain=str(host),
                    domain_specified=str(host).startswith("."),
                    domain_initial_dot=str(host).startswith("."),
                    path=str(path or "/"),
                    path_specified=True,
                    secure=bool(is_sec),
                    expires=exp,
                    discard=exp is None,
                    comment=None,
                    comment_url=None,
                    rest={},
                )
            )
        if profile_cookies:
            per_profile.append(profile_cookies)
    return per_profile


def read_attendo_cookie_jars(browser_pref: str = "auto") -> List[CookieJar]:
    """Return CookieJars containing student_token (plus cf_clearance if present) per profile."""
    jars: List[CookieJar] = []
    for browser in _browser_order(browser_pref):
        batches = (
            [_read_firefox_cookies(("1337.ma",))]
            if browser == "firefox"
            else _read_chromium_cookies_by_profile(browser, ("1337.ma",))
        )
        for cookies in batches:
            if any(c.name == "student_token" and c.value for c in cookies):
                jar = CookieJar()
                for c in sorted(cookies, key=lambda x: x.expires or float("inf"), reverse=True):
                    jar.set_cookie(c)
                if len(jar):
                    jars.append(jar)
    return jars


def read_intra_cookie_jars(browser_pref: str = "auto") -> List[CookieJar]:
    jars: List[CookieJar] = []
    for browser in _browser_order(browser_pref):
        batches = (
            [_read_firefox_cookies(("42.fr",))]
            if browser == "firefox"
            else _read_chromium_cookies_by_profile(browser, ("42.fr",))
        )
        for cookies in batches:
            if cookies:
                jar = CookieJar()
                for c in cookies:
                    jar.set_cookie(c)
                if len(jar):
                    jars.append(jar)
    return jars


# ==============================================================================
# HTML & JSON Parsers for 1337 Attendo & 42 Intra
# ==============================================================================

class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise PermissionError("Session redirected to login.")


class _ScriptCollector(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.in_script = False
        self.buffer: List[str] = []
        self.scripts: List[str] = []

    def handle_starttag(self, tag: str, _attrs: Any) -> None:
        if tag == "script":
            self.in_script = True
            self.buffer = []

    def handle_data(self, data: str) -> None:
        if self.in_script:
            self.buffer.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag == "script" and self.in_script:
            self.scripts.append("".join(self.buffer))
            self.in_script = False


class _VisibleText(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: List[str] = []
        self.hidden = 0

    def handle_starttag(self, tag: str, _attrs: Any) -> None:
        if tag in ("script", "style"):
            self.hidden += 1

    def handle_endtag(self, tag: str) -> None:
        if tag in ("script", "style"):
            self.hidden = max(0, self.hidden - 1)

    def handle_data(self, text: str) -> None:
        if not self.hidden and text.strip():
            self.parts.append(text.strip())


def _extract_next_data(html: str) -> str:
    parser = _ScriptCollector()
    parser.feed(html)
    chunks: List[str] = []
    for script in parser.scripts:
        match = re.fullmatch(r"\s*self\.__next_f\.push\((.*)\)\s*", script, re.DOTALL)
        if not match:
            continue
        try:
            payload = json.loads(match.group(1))
        except json.JSONDecodeError:
            continue
        if isinstance(payload, list) and len(payload) > 1 and isinstance(payload[1], str):
            chunks.append(payload[1])
    return "".join(chunks)


def parse_attendo_profile_html(html: str) -> dict[str, Any]:
    data = _extract_next_data(html)
    if not data:
        data = html.replace(r'\"', '"')

    estimates = re.findall(r'"todayHoursEstimation"\s*:\s*(?:"([0-9]+:[0-9]{2})"|null)', data)
    estimate = estimates[-1] if estimates and estimates[-1] else None

    recorded = re.findall(r'"todayHours"\s*:\s*([0-9]+(?:\.[0-9]+)?|null)', data)
    today_hours = float(recorded[-1]) if recorded and recorded[-1] != "null" else None

    logins = re.findall(r'"login"\s*:\s*"([^"\\]+)"', data)
    if not logins:
        raise ValueError("Could not identify student login in Attendo profile HTML.")
    login = logins[-1]

    decoder = json.JSONDecoder()
    raw_periods: List[dict[str, Any]] = []
    for match in re.finditer(r'\{\s*"weekStart"\s*:', data):
        try:
            period_obj, _ = decoder.raw_decode(data, match.start())
        except json.JSONDecodeError:
            continue
        if not isinstance(period_obj, dict):
            continue
        start = period_obj.get("weekStart")
        end = period_obj.get("weekEnd")
        total = period_obj.get("total")
        daily = period_obj.get("daily")
        if not (
            isinstance(start, str)
            and isinstance(end, str)
            and type(total) in (int, float)
            and isinstance(daily, list)
        ):
            continue
        days: List[dict[str, Any]] = []
        for day_obj in daily:
            if not isinstance(day_obj, dict):
                continue
            d_str = day_obj.get("date")
            counted = day_obj.get("counted")
            hours = day_obj.get("hours", day_obj.get("hoursLogged"))
            if isinstance(d_str, str) and isinstance(counted, bool) and type(hours) in (int, float):
                days.append({"date": d_str, "hours": float(hours), "counted": counted})
        raw_periods.append({
            "start": start,
            "end": end,
            "total": float(total),
            "days": days,
            "counted_days": sum(1 for d in days if d["counted"]),
        })

    if not raw_periods:
        raise ValueError("Could not find attendance periods in Attendo profile HTML.")

    last_p = raw_periods[-1]
    if last_p["counted_days"] < 7:
        current = last_p
        current["label"] = "Current period"
        previous = raw_periods[-2] if len(raw_periods) > 1 else None
        if previous:
            previous["label"] = "Previous period"
    else:
        current = None
        previous = last_p
        previous["label"] = "Previous period"

    visible = _VisibleText()
    visible.feed(html)
    target_match = re.search(
        r"Attendance target\s+(\d+(?:\.\d+)?)\s*h\s+per counted-day period",
        " ".join(visible.parts),
        re.IGNORECASE,
    )
    target = float(target_match.group(1)) if target_match else None
    if target is not None and not (0 < target < 10000):
        target = None

    return {
        "login": login,
        "current_period": current,
        "previous_period": previous,
        "live_estimate": estimate,
        "today_hours": today_hours,
        "target_hours": target,
    }


def parse_intra_locations_json(payload: Any) -> Dict[str, float]:
    if not isinstance(payload, dict):
        raise ValueError("Unexpected 42 Intra location format.")
    totals: Dict[str, float] = {}
    for key, value in payload.items():
        if not isinstance(value, str):
            continue
        m = re.fullmatch(r"(\d+):([0-5]?\d):([0-5]?\d(?:\.\d+)?)", value)
        if m:
            date.fromisoformat(key)
            h, mins, secs = m.groups()
            totals[key] = int(h) * 3600.0 + int(mins) * 60.0 + float(secs)
    return totals


def _fetch_attendo(
    manual_token: str,
    browser_cookie_hdr: str,
    browser_pref: str,
) -> Tuple[Optional[dict[str, Any]], Optional[str]]:
    raw_headers: List[str] = []
    if manual_token.strip():
        raw_headers.append(f"student_token={manual_token.strip()}")
    if browser_cookie_hdr.strip() and "student_token=" in browser_cookie_hdr:
        raw_headers.append(browser_cookie_hdr.strip())
    env_cookie = os.environ.get("ATTENDO_COOKIE", "").strip()
    if env_cookie and env_cookie not in raw_headers:
        raw_headers.append(env_cookie)
    env_token = os.environ.get("ATTENDO_TOKEN", "").strip()
    if env_token:
        h = f"student_token={env_token}"
        if h not in raw_headers:
            raw_headers.append(h)

    jars = read_attendo_cookie_jars(browser_pref)
    if not raw_headers and not jars:
        return (None, "Sign in to 1337 Attendo in your browser.")

    last_err = "Sign in to 1337 Attendo."
    common_hdrs = {
        "Accept": "text/html,application/xhtml+xml",
        "User-Agent": USER_AGENT,
    }

    for cookie_hdr in raw_headers:
        req = urllib.request.Request(
            ATTENDO_PROFILE_URL,
            headers={**common_hdrs, "Cookie": cookie_hdr},
        )
        try:
            opener = urllib.request.build_opener(_NoRedirect())
            with opener.open(req, timeout=3.5) as resp:
                body = resp.read(8 * 1024 * 1024 + 1)
            return (parse_attendo_profile_html(body.decode("utf-8", errors="replace")), None)
        except PermissionError:
            last_err = "Attendo session expired."
            continue
        except urllib.error.HTTPError as exc:
            if exc.code in (401, 403):
                last_err = "Attendo rejected session."
                continue
            return (None, f"Attendo HTTP {exc.code}")
        except (urllib.error.URLError, OSError, TimeoutError):
            last_err = "Attendo unreachable"
            continue
        except ValueError as exc:
            return (None, str(exc))

    for jar in jars:
        req = urllib.request.Request(ATTENDO_PROFILE_URL, headers=common_hdrs)
        try:
            opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar), _NoRedirect())
            with opener.open(req, timeout=3.5) as resp:
                body = resp.read(8 * 1024 * 1024 + 1)
            return (parse_attendo_profile_html(body.decode("utf-8", errors="replace")), None)
        except PermissionError:
            last_err = "Attendo session expired."
            continue
        except urllib.error.HTTPError as exc:
            if exc.code in (401, 403):
                last_err = "Attendo rejected session."
                continue
            return (None, f"Attendo HTTP {exc.code}")
        except (urllib.error.URLError, OSError, TimeoutError):
            return (None, "Attendo unreachable")
        except ValueError as exc:
            return (None, str(exc))

    return (None, last_err)


def _fetch_intra(
    login: str,
    browser_cookie_hdr: str,
    browser_pref: str,
) -> Tuple[Optional[Dict[str, float]], Optional[str]]:
    if not login.strip():
        return (None, "42 login unknown.")
    url = f"https://{INTRA_HOST}/users/{quote(login.strip(), safe='')}/locations_stats.json"
    common_headers = {
        "Accept": "*/*",
        "Origin": INTRA_ORIGIN,
        "Referer": f"{INTRA_ORIGIN}/",
        "User-Agent": USER_AGENT,
    }

    if browser_cookie_hdr.strip():
        req = urllib.request.Request(url, headers={**common_headers, "Cookie": browser_cookie_hdr.strip()})
        try:
            opener = urllib.request.build_opener(_NoRedirect())
            with opener.open(req, timeout=3.5) as resp:
                payload = json.loads(resp.read(2 * 1024 * 1024 + 1))
            return (parse_intra_locations_json(payload), None)
        except Exception:
            pass

    jars = read_intra_cookie_jars(browser_pref)
    if not jars:
        return (None, "Sign in to 42 Intra in your browser.")

    for jar in jars:
        req = urllib.request.Request(url, headers=common_headers)
        try:
            opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar), _NoRedirect())
            with opener.open(req, timeout=3.5) as resp:
                payload = json.loads(resp.read(2 * 1024 * 1024 + 1))
            return (parse_intra_locations_json(payload), None)
        except PermissionError:
            continue
        except urllib.error.HTTPError as exc:
            if exc.code in (401, 403):
                continue
            return (None, f"42 Intra HTTP {exc.code}")
        except (urllib.error.URLError, OSError, TimeoutError, json.JSONDecodeError, ValueError):
            continue

    return (None, "Sign in to 42 Intra in your browser.")


def sync_linked_accounts(
    browser_pref: str = "auto",
    requested_login: str = "",
    manual_token: str = "",
    browser_attendo_cookie: str = "",
    browser_intra_cookie: str = "",
    force_refresh: bool = False,
) -> dict[str, Any]:
    now_ts = time.time()
    today_dt = campus_today()
    today_iso = today_dt.isoformat()
    yest_iso = (today_dt - timedelta(days=1)).isoformat()

    cache_key = {
        "browser_pref": browser_pref,
        "requested_login": requested_login,
        "has_manual_token": bool(manual_token.strip()),
        "has_browser_attendo": bool("student_token=" in browser_attendo_cookie),
        "has_browser_intra": bool(browser_intra_cookie.strip()),
    }

    if not force_refresh and CACHE_PATH.exists():
        try:
            cached = json.loads(CACHE_PATH.read_text(encoding="utf-8"))
            if (
                isinstance(cached, dict)
                and cached.get("_cache_key") == cache_key
                and (now_ts - float(cached.get("fetched_at", 0))) < CACHE_TTL_SECONDS
            ):
                return cached
        except Exception:
            pass

    profile, attendo_err = _fetch_attendo(manual_token, browser_attendo_cookie, browser_pref)

    login = (
        requested_login.strip()
        or (profile.get("login") if profile else "")
        or os.environ.get("INTRA_LOGIN", "").strip()
        or getpass.getuser()
    )

    daily_map, intra_err = _fetch_intra(login, browser_intra_cookie, browser_pref)

    attendo_live_sec = None
    attendo_rec_sec = None
    if profile:
        m = re.fullmatch(r"(\d+):([0-5]\d)", profile.get("live_estimate") or "")
        if m:
            attendo_live_sec = int(m.group(1)) * 3600.0 + int(m.group(2)) * 60.0
        if profile.get("today_hours") is not None:
            attendo_rec_sec = profile["today_hours"] * 3600.0

    intra_today = None
    intra_yest = None
    intra_period = None
    intra_prior_period = None
    intra_week = None
    intra_month = None
    if daily_map is not None:
        intra_today = daily_map.get(today_iso, 0.0)
        intra_yest = daily_map.get(yest_iso, 0.0)

        p_start, p_end = attendo_period_bounds()
        if profile and profile.get("current_period"):
            try:
                p_start = date.fromisoformat(profile["current_period"]["start"][:10])
                p_end = date.fromisoformat(profile["current_period"]["end"][:10])
            except Exception:
                pass
        w_start = today_dt - timedelta(days=today_dt.weekday())
        m_start = today_dt.replace(day=1)

        intra_period = sum(
            sec for d_str, sec in daily_map.items()
            if p_start.isoformat() <= d_str <= p_end.isoformat()
        )
        intra_prior_period = sum(
            sec for d_str, sec in daily_map.items()
            if p_start.isoformat() <= d_str < today_iso
        )
        intra_week = sum(
            sec for d_str, sec in daily_map.items()
            if w_start.isoformat() <= d_str <= today_iso
        )
        intra_month = sum(
            sec for d_str, sec in daily_map.items()
            if m_start.isoformat() <= d_str <= today_iso
        )

    result: dict[str, Any] = {
        "_cache_key": cache_key,
        "login": login,
        "intra_linked": daily_map is not None,
        "intra_error": intra_err,
        "intra_today_seconds": intra_today,
        "intra_yesterday_seconds": intra_yest,
        "intra_period_seconds": intra_period,
        "intra_prior_period_seconds": intra_prior_period,
        "intra_week_seconds": intra_week,
        "intra_month_seconds": intra_month,
        "attendo_linked": profile is not None,
        "attendo_error": attendo_err,
        "attendo_live_seconds": attendo_live_sec,
        "attendo_recorded_today_seconds": attendo_rec_sec,
        "current_period": profile.get("current_period") if profile else None,
        "previous_period": profile.get("previous_period") if profile else None,
        "target_hours": profile.get("target_hours") if profile else None,
        "fetched_at": now_ts,
    }

    try:
        CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
        CACHE_PATH.write_text(json.dumps(result), encoding="utf-8")
    except Exception:
        pass

    return result


# ==============================================================================
# Workstation Ledger Snapshot + SQLite Read-Only Locks (from xattendo-widget)
# ==============================================================================

def normalize_and_sum_locks(
    intervals: Iterable[Iterable[float | None]],
    win_start: float,
    win_end: float,
    open_fallback_end: float,
) -> tuple[float, int, list[tuple[float, float, bool]]]:
    clipped: list[tuple[float, float, bool]] = []
    for item in intervals:
        iv = list(item)
        if len(iv) < 2 or iv[0] is None:
            continue
        s, e = iv[0], iv[1]
        is_open = e is None
        eff_end = float(e) if e is not None else open_fallback_end
        a = max(float(s), win_start)
        b = min(eff_end, win_end)
        if b > a:
            clipped.append((a, b, is_open and eff_end >= win_end))

    if not clipped:
        return 0.0, 0, []

    clipped.sort(key=lambda pair: pair[0])
    merged: list[list[Any]] = [[clipped[0][0], clipped[0][1], clipped[0][2]]]
    for a, b, is_open in clipped[1:]:
        if a <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], b)
            merged[-1][2] = merged[-1][2] or is_open
        else:
            merged.append([a, b, is_open])

    total_locked = sum(b - a for a, b, _ in merged)
    return total_locked, len(merged), [(a, b, bool(o)) for a, b, o in merged]


def _read_sqlite_day_locks(username: str, day_start: float, day_end: float) -> list[list[float | None]]:
    rows: list[list[float | None]] = []
    if SHARED_HISTORY_DB.is_file():
        try:
            with sqlite3.connect(SHARED_HISTORY_DB.resolve().as_uri() + "?mode=ro", uri=True, timeout=1) as db:
                for a, b in db.execute(
                    "SELECT start, end FROM intervals WHERE username = ? AND end > ? AND start < ? ORDER BY start",
                    (username, day_start, day_end),
                ).fetchall():
                    rows.append([float(a), float(b)])
        except (OSError, sqlite3.Error):
            pass
    if LEGACY_ARCHIVE_DB.is_file():
        try:
            with sqlite3.connect(LEGACY_ARCHIVE_DB.resolve().as_uri() + "?mode=ro", uri=True, timeout=1) as db:
                for a, b in db.execute(
                    "SELECT start, end FROM locks WHERE username = ?",
                    (username,),
                ).fetchall():
                    rows.append([float(a), float(b)])
        except (OSError, sqlite3.Error):
            pass
    return rows


def compute_window_totals(
    sessions: dict[str, Any],
    current_key: str | None,
    win_start: float,
    win_end: float,
    now_ts: float,
    baselines: dict[str, Any] | None = None,
) -> dict[str, Any]:
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
        locked, _, _ = normalize_and_sum_locks(rec.get("intervals", []), a, b, s_end)
        total_gross += gross
        total_locked += min(locked, gross)

    base_sec = 0.0
    if baselines:
        for entry in baselines.values():
            b_ts = float(entry.get("ts", 0.0))
            if win_start <= b_ts <= win_end:
                base_sec += float(entry.get("net_sec", 0.0))

    total_net = max(0.0, total_gross - total_locked) + base_sec
    return {
        "net_seconds": round(total_net, 2),
        "locked_seconds": round(total_locked, 2),
        "gross_seconds": round(total_gross + base_sec, 2),
        "sessions": count,
    }


def extract_snapshot_details(
    ledger: dict[str, Any],
    current_session: dict[str, Any] | None,
    now_ts: float,
    username: str,
) -> dict[str, Any]:
    zone = campus_zone()
    now_dt = campus_now(datetime.fromtimestamp(now_ts, zone))
    day_start_dt = now_dt.replace(hour=0, minute=0, second=0, microsecond=0)
    day_start = day_start_dt.timestamp()
    day_end = (day_start_dt + timedelta(days=1)).timestamp()

    p_start_d, p_end_d = attendo_period_bounds(now_dt)
    period_start = datetime.combine(p_start_d, dt_time(), zone).timestamp()
    week_start = (now_dt - timedelta(days=now_dt.weekday())).replace(
        hour=0, minute=0, second=0, microsecond=0
    ).timestamp()
    month_start = now_dt.replace(day=1, hour=0, minute=0, second=0, microsecond=0).timestamp()

    sessions: dict[str, Any] = ledger.get("sessions", {})
    baselines: dict[str, Any] = ledger.get("baselines", {})

    current_key: str | None = None
    if current_session and current_session.get("live"):
        h = current_session.get("host", "")
        sid = current_session.get("session_id", "")
        sts = int(current_session.get("start_ts", 0))
        cand = f"{h}|{sid}|{sts}"
        if cand in sessions:
            current_key = cand
        else:
            for k, rec in sessions.items():
                if rec.get("session_id") == sid and not rec.get("closed"):
                    current_key = k
                    break

    today_tot = compute_window_totals(sessions, current_key, day_start, now_ts, now_ts, baselines)
    period_tot = compute_window_totals(sessions, current_key, period_start, now_ts, now_ts, baselines)
    week_tot = compute_window_totals(sessions, current_key, week_start, now_ts, now_ts, baselines)
    month_tot = compute_window_totals(sessions, current_key, month_start, now_ts, now_ts, baselines)

    # Today's merged locks across ledger + read-only SQLite lock archives
    today_iv: list[list[float | None]] = []
    for key, rec in sessions.items():
        s_end = now_ts if (key == current_key and not rec.get("closed")) else float(rec.get("end_ts") or rec.get("last_seen") or now_ts)
        for iv_s, iv_e in rec.get("intervals", []):
            today_iv.append([iv_s, iv_e if iv_e is not None else (None if key == current_key else s_end)])
    today_iv.extend(_read_sqlite_day_locks(username, day_start, now_ts))

    total_locked_today, _, merged_locks = normalize_and_sum_locks(today_iv, day_start, now_ts, now_ts)
    today_tot["locked_seconds"] = round(max(today_tot["locked_seconds"], total_locked_today), 2)
    today_tot["net_seconds"] = round(max(0.0, today_tot["gross_seconds"] - today_tot["locked_seconds"]), 2)

    today_locks = [
        {
            "start": campus_now(datetime.fromtimestamp(a, zone)).strftime("%H:%M:%S"),
            "end": "—" if is_open else campus_now(datetime.fromtimestamp(b, zone)).strftime("%H:%M:%S"),
            "seconds": round(max(0.0, b - a), 1),
            "ongoing": is_open,
        }
        for a, b, is_open in merged_locks
    ]

    # Recent 20 sessions
    sorted_items = sorted(sessions.items(), key=lambda kv: float(kv[1].get("start_ts", 0)), reverse=True)
    recent_sessions: list[dict[str, Any]] = []
    for key, rec in sorted_items[:20]:
        sts = float(rec.get("start_ts", 0))
        is_live = bool(key == current_key and not rec.get("closed"))
        ets = now_ts if is_live else float(rec.get("end_ts") or rec.get("last_seen") or sts)
        gross = max(0.0, ets - sts)
        locked, _, _ = normalize_and_sum_locks(rec.get("intervals", []), sts, ets, ets)
        locked = min(locked, gross)
        net = max(0.0, gross - locked)
        dt_start = campus_now(datetime.fromtimestamp(sts, zone))
        recent_sessions.append({
            "host": str(rec.get("host", "")),
            "session_id": str(rec.get("session_id", "")),
            "date": dt_start.strftime("%Y-%m-%d"),
            "start_hm": dt_start.strftime("%H:%M"),
            "start_hms": dt_start.strftime("%H:%M:%S"),
            "end_hms": "LIVE" if is_live else campus_now(datetime.fromtimestamp(ets, zone)).strftime("%H:%M:%S"),
            "net_sec": round(net, 1),
            "locked_sec": round(locked, 1),
            "gross_sec": round(gross, 1),
            "live": is_live,
        })

    # Active DayTimeline (exact xattendo build_day_active_segments)
    start_hour = 8
    end_hour = 20
    if now_dt.hour >= 20:
        end_hour = min(24, ((now_dt.hour // 2) + 1) * 2)

    active_segments: list[list[float]] = []
    lock_segments: list[list[float]] = []

    for key, rec in sessions.items():
        sts = float(rec.get("start_ts", 0))
        is_live = bool(key == current_key and not rec.get("closed"))
        ets = now_ts if is_live else float(rec.get("end_ts") or rec.get("last_seen") or sts)
        lo = max(sts, day_start)
        hi = min(ets, day_end, now_ts)
        if hi <= lo:
            continue

        s_dt = campus_now(datetime.fromtimestamp(lo, zone))
        if s_dt.hour < start_hour:
            start_hour = max(0, (s_dt.hour // 2) * 2)

        _, _, seg_locks = normalize_and_sum_locks(rec.get("intervals", []), lo, hi, hi)
        cursor = lo
        for lk_a, lk_b, _ in seg_locks:
            if lk_a > cursor:
                active_segments.append([cursor, lk_a])
            lock_segments.append([lk_a, lk_b])
            cursor = max(cursor, lk_b)
        if hi > cursor:
            active_segments.append([cursor, hi])

    win_start = (day_start_dt + timedelta(hours=start_hour)).timestamp()
    win_end = (day_start_dt + timedelta(hours=end_hour)).timestamp()

    clipped_active = [
        [max(a, win_start), min(b, win_end)]
        for a, b in sorted(active_segments)
        if min(b, win_end) > max(a, win_start)
    ]
    clipped_locks = [
        [max(a, win_start), min(b, win_end)]
        for a, b in sorted(lock_segments)
        if min(b, win_end) > max(a, win_start)
    ]

    return {
        "today": today_tot,
        "period_start": p_start_d.isoformat(),
        "period_end": p_end_d.isoformat(),
        "period": period_tot,
        "week": week_tot,
        "month": month_tot,
        "today_locks": today_locks,
        "recent_sessions": recent_sessions,
        "today_timeline": {
            "win_start": win_start,
            "win_end": win_end,
            "active_segments": clipped_active,
            "lock_segments": clipped_locks,
        },
    }


# ==============================================================================
# Pure Xattendo Fusion & Calculation Pipeline
# ==============================================================================

def compute_xattendo_metrics(
    snapshot: dict[str, Any],
    cur_session: dict[str, Any] | None,
    linked: dict[str, Any],
    now_ts: float,
    fallback_target_hours: float,
) -> dict[str, Any]:
    zone = campus_zone()
    today_d = campus_today(datetime.fromtimestamp(now_ts, zone))
    t_iso = today_d.isoformat()

    local_today = snapshot["today"]
    locked = max(0.0, float(local_today["locked_seconds"]))
    is_live = bool(cur_session and cur_session.get("live"))
    fetched_at = float(linked.get("fetched_at") or 0.0)
    elapsed_since_sync = max(0.0, min(now_ts - fetched_at, 600.0)) if (fetched_at > 0 and is_live) else 0.0

    gross = max(0.0, float(local_today["gross_seconds"]))
    has_intra = bool(linked.get("intra_linked") and linked.get("intra_today_seconds") is not None)
    if has_intra:
        gross = max(gross, float(linked["intra_today_seconds"]) + elapsed_since_sync)
    elif linked.get("attendo_linked") and linked.get("attendo_live_seconds") is not None:
        gross = max(gross, float(linked["attendo_live_seconds"]) + elapsed_since_sync)

    net = max(0.0, gross - locked)
    att_rec = linked.get("attendo_recorded_today_seconds")
    if linked.get("attendo_linked") and att_rec is not None and not has_intra:
        net = max(net, float(att_rec))
        gross = max(gross, net + locked)

    effective_today = {
        "net_seconds": round(net, 2),
        "gross_seconds": round(gross, 2),
        "locked_seconds": round(locked, 2),
        "is_fused": net > float(local_today["net_seconds"]) + 1.0,
    }

    # Merge period progress (Attendo official or Thu-Wed fallback + Intra fusion)
    target_h = max(1.0, min(200.0, float(fallback_target_hours or DEFAULT_PERIOD_TARGET_HOURS)))
    p_start = snapshot["period_start"]
    p_end = snapshot["period_end"]
    local_period_sec = max(0.0, float(snapshot["period"]["net_seconds"]))

    prior_intra_sec = float(linked.get("intra_prior_period_seconds") or 0.0)
    prior_local_sec = max(0.0, local_period_sec - float(local_today["net_seconds"]))
    p_net = max(local_period_sec, prior_local_sec + net, (prior_intra_sec + net) if has_intra else 0.0)

    cp = linked.get("current_period")
    if linked.get("attendo_linked") and cp is not None:
        if linked.get("target_hours") and float(linked["target_hours"]) > 0:
            target_h = float(linked["target_hours"])
        p_start = cp.get("start") or p_start
        p_end = cp.get("end") or p_end
        prior_days = [d for d in cp.get("days", []) if d.get("date", "") < t_iso]
        prior_attendo_sec = sum(float(d.get("hours", 0.0)) for d in prior_days) * 3600.0
        today_attendo_sec = max(net, float(att_rec or 0.0))
        fused = prior_attendo_sec + today_attendo_sec
        p_net = max(local_period_sec, float(cp.get("total", 0.0)) * 3600.0, fused)

        remaining_days = max(0, 7 - sum(1 for d in prior_days if d.get("counted")))
        remaining_period_hours = max(0.0, target_h - (prior_attendo_sec / 3600.0))
    else:
        prior_combined_hours = max(prior_local_sec, prior_intra_sec if has_intra else 0.0) / 3600.0
        remaining_period_hours = max(0.0, target_h - prior_combined_hours)
        try:
            p_end_date = date.fromisoformat(p_end[:10])
        except Exception:
            p_end_date = attendo_period_bounds(datetime.fromtimestamp(now_ts, zone))[1]
        remaining_days = max(1, min(7, (p_end_date - today_d).days + 1))

    p_hours = p_net / 3600.0
    p_pct = min(100.0, (p_hours / target_h) * 100.0) if target_h > 0 else 0.0
    p_left_h = max(0.0, target_h - p_hours)

    period_progress = {
        "net_seconds": round(p_net, 2),
        "target_hours": target_h,
        "start": p_start,
        "end": p_end,
        "percent": round(p_pct, 2),
        "left_hours": round(p_left_h, 3),
    }

    # Calculate daily average target (xattendo calculator.py)
    if remaining_period_hours <= 0.0:
        daily_target_sec = 0.0
        rem_today_sec = 0.0
        fraction = 1.0
        done = True
    else:
        denom_days = max(1, remaining_days)
        daily_target_sec = (remaining_period_hours / denom_days) * 3600.0
        rem_today_sec = max(0.0, daily_target_sec - net)
        done = rem_today_sec <= 0.0
        fraction = 1.0 if done else max(0.0, min(1.0, net / daily_target_sec))

    eta_dt = campus_now(datetime.fromtimestamp(now_ts, zone)) + timedelta(seconds=rem_today_sec)
    expected_rec_hours = math.floor((net + ATTENDANCE_ROUNDING_OFFSET_SECONDS) / 3600.0)

    daily_target = {
        "remaining_period_hours": round(remaining_period_hours, 2),
        "remaining_days": remaining_days,
        "daily_target_seconds": round(daily_target_sec, 1),
        "remaining_today_seconds": round(rem_today_sec, 1),
        "fraction": round(fraction, 4),
        "done": done,
        "eta_clock": eta_dt.strftime("%H:%M"),
        "expected_recorded_hours": max(0, expected_rec_hours),
    }

    # Week & Month fused totals
    base_week = float(snapshot["week"]["net_seconds"])
    intra_week = float(linked.get("intra_week_seconds") or 0.0) if linked.get("intra_linked") else 0.0
    base_month = float(snapshot["month"]["net_seconds"])
    intra_month = float(linked.get("intra_month_seconds") or 0.0) if linked.get("intra_linked") else 0.0

    # Ensure week/month are at least >= effective_today
    week_sec = max(base_week, intra_week, net)
    month_sec = max(base_month, intra_month, net)

    return {
        "effective_today": effective_today,
        "period_progress": period_progress,
        "daily_target": daily_target,
        "week_net_seconds": round(week_sec, 2),
        "month_net_seconds": round(month_sec, 2),
    }


def handle_request(req: dict[str, Any] | None) -> dict[str, Any]:
    req = req or {}
    browser_pref = str(req.get("browserPreference", "auto"))
    requested_login = str(req.get("login", "")).strip()
    manual_token = str(req.get("attendoToken", "")).strip()
    browser_attendo_cookie = str(req.get("browserAttendoCookie", "")).strip()
    browser_intra_cookie = str(req.get("browserIntraCookie", "")).strip()
    force_refresh = bool(req.get("forceRefresh", False))
    try:
        fallback_target_hours = max(1.0, min(200.0, float(req.get("targetHours", DEFAULT_PERIOD_TARGET_HOURS))))
    except (TypeError, ValueError):
        fallback_target_hours = DEFAULT_PERIOD_TARGET_HOURS

    # 1. Run live_estimate.py --json so sessions.json stays current
    res = subprocess.run(
        ["/usr/bin/python3", str(LIVE_ESTIMATE_SCRIPT), "--json"],
        capture_output=True,
        text=True,
        timeout=5,
        check=True,
    )
    payload = json.loads(res.stdout)

    # 2. Read ledger safely (read-only)
    ledger: dict[str, Any] = {"sessions": {}, "baselines": {}}
    if LEDGER_PATH.exists():
        try:
            raw = json.loads(LEDGER_PATH.read_text(encoding="utf-8"))
            if isinstance(raw, dict):
                ledger = raw
        except Exception:
            pass

    now_ts = float(payload.get("now", time.time()))
    cur_session = payload.get("current_session")

    resolved_login = requested_login
    if not resolved_login:
        if cur_session and cur_session.get("username"):
            resolved_login = cur_session["username"]
        elif ledger.get("sessions"):
            first_sess = next(iter(ledger["sessions"].values()), {})
            resolved_login = str(first_sess.get("username", ""))

    # 3. Sync 42 Intra & 1337 Attendo
    linked = sync_linked_accounts(
        browser_pref=browser_pref,
        requested_login=resolved_login,
        manual_token=manual_token,
        browser_attendo_cookie=browser_attendo_cookie,
        browser_intra_cookie=browser_intra_cookie,
        force_refresh=force_refresh,
    )

    # 4. Build snapshot in campus timezone + read-only SQLite lock archive merge
    username = (
        (cur_session.get("username") if cur_session else None)
        or linked.get("login")
        or os.environ.get("USER")
        or getpass.getuser()
    )
    snapshot = extract_snapshot_details(ledger, cur_session, now_ts, str(username))

    # 5. Compute fused Xattendo metrics
    computed = compute_xattendo_metrics(
        snapshot=snapshot,
        cur_session=cur_session,
        linked=linked,
        now_ts=now_ts,
        fallback_target_hours=fallback_target_hours,
    )

    return {
        "now": now_ts,
        "current_session": cur_session,
        "ledger_path": payload.get("ledger_path", str(LEDGER_PATH)),
        "today": snapshot["today"],
        "period": snapshot["period"],
        "week": {"net_seconds": computed["week_net_seconds"]},
        "month": {"net_seconds": computed["month_net_seconds"]},
        "linked_accounts": {
            k: v for k, v in linked.items() if k != "_cache_key"
        },
        "effective_today": computed["effective_today"],
        "period_progress": computed["period_progress"],
        "daily_target": computed["daily_target"],
        "today_timeline": snapshot["today_timeline"],
        "today_locks": snapshot["today_locks"],
        "recent_sessions": snapshot["recent_sessions"],
    }


def main() -> None:
    req = read_message()
    try:
        payload = handle_request(req)
        send_message(payload)
    except Exception as exc:
        send_message({"error": str(exc)})


if __name__ == "__main__":
    main()
PYEOF

chmod +x "$HOST_BIN"
python3 -m py_compile "$HOST_BIN"

# 8. Write Native Messaging Host JSON definition
NM_MANIFEST_CONTENT=$(cat << EOF
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
)

echo "$NM_MANIFEST_CONTENT" > "$BRAVE_NM_DIR/$HOST_NAME.json"

if [ -d "$HOME/snap/brave" ]; then
    echo "$NM_MANIFEST_CONTENT" > "$BRAVE_SNAP_NM_DIR/$HOST_NAME.json"
fi

if [ -d "$HOME/.config/google-chrome" ]; then
    echo "$NM_MANIFEST_CONTENT" > "$CHROME_NM_DIR/$HOST_NAME.json"
fi

# 9. Reload systemd user daemon safely if services exist
if systemctl --user list-unit-files live-estimate.timer >/dev/null 2>&1; then
    systemctl --user daemon-reload
    echo "==> Systemd user units reloaded safely without session tracking interruption."
fi

echo
echo "Add extension in Brave (first time):"
echo "  1. Open brave://extensions"
echo "  2. Enable 'Developer mode' (top-right)"
echo "  3. Click 'Load unpacked' and select: $EXT_DIR"
echo
echo "Update extension in Brave (already added):"
echo "  1. Open brave://extensions"
echo "  2. Click the reload icon (↻) on '42 Live-Estimate Counter'"
