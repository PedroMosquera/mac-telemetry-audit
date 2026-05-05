#!/usr/bin/env bash
#
# mac-telemetry-audit.sh
# Read-only macOS audit for telemetry, observability, and data-sending software.
# Writes a report to ~/Desktop/mac-telemetry-audit.txt
#
# This script:
#   - does NOT install anything
#   - does NOT change any settings
#   - does NOT send data anywhere
#   - reads files and runs `ps`, `lsof`, `launchctl`, `defaults read`, etc.
#
# sudo is requested only for launchctl print system/ , lsof -i , kextstat.
# If you skip sudo, those sections will be reduced.

set -u
OUT="${HOME}/Desktop/mac-telemetry-audit.txt"
SEP="================================================================================"

say() { printf '\n%s\n%s\n%s\n\n' "$SEP" "  $*" "$SEP" >>"$OUT"; }
note() { printf '%s\n' "$*" >>"$OUT"; }
run() { note "\$ $*"; eval "$@" >>"$OUT" 2>&1 || true; note ""; }

: >"$OUT"
note "macOS Telemetry & Observability Audit"
note "Generated: $(date)"
note "User: $(id -un)   Host: $(hostname)   macOS: $(sw_vers -productVersion)   Arch: $(uname -m)"
note ""

# --- 0. Sudo prompt up front (optional) ----------------------------------------
note "Requesting sudo for system-level reads (skip with Ctrl-C if you don't want to)..."
sudo -v 2>/dev/null || note "(no sudo — system sections will be reduced)"

# --- 1. Environment variables in shell rc files --------------------------------
say "1. Shell rc files: telemetry / observability / proxy / API key patterns"
PATTERN='OTEL|TELEMETRY|ANTHROPIC|CLAUDE|TRACE|METRIC|EXPORTER|SENTRY|DATADOG|NEW.?RELIC|APPDYNAMICS|SPLUNK|ELASTIC|HONEYCOMB|PROMETHEUS|STATSD|JAEGER|ZIPKIN|OPENTELEMETRY|OBSERVA|MONITOR|ANALYTIC|HTTP_PROXY|HTTPS_PROXY|ALL_PROXY|NO_PROXY|TOKEN|API_KEY|SECRET'
for f in \
    /etc/zshenv /etc/zprofile /etc/zshrc /etc/profile /etc/bashrc /etc/paths \
    "$HOME/.zshenv" "$HOME/.zprofile" "$HOME/.zshrc" "$HOME/.zlogin" "$HOME/.zlogout" \
    "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile" \
    "$HOME/.config/fish/config.fish"; do
    if [ -r "$f" ]; then
        note "--- $f ---"
        grep -nEi "$PATTERN" "$f" 2>/dev/null | sed 's/\(KEY\|TOKEN\|SECRET\)=.*/\1=<redacted>/' >>"$OUT" || note "(no matches)"
        note ""
    fi
done

# --- 2. launchctl getenv (variables exported to every GUI app) -----------------
say "2. launchctl-managed environment (affects every GUI app launched)"
note "User session:"
run "launchctl getenv PATH"
note "Telemetry-relevant vars (per name):"
for v in OTEL_EXPORTER_OTLP_ENDPOINT OTEL_LOG_USER_PROMPTS OTEL_LOG_TOOL_DETAILS \
         CLAUDE_CODE_ENABLE_TELEMETRY ANTHROPIC_BASE_URL HTTPS_PROXY HTTP_PROXY \
         DATADOG_API_KEY DD_API_KEY SENTRY_DSN NEW_RELIC_LICENSE_KEY; do
    val=$(launchctl getenv "$v" 2>/dev/null)
    [ -n "$val" ] && note "$v=$val"
done
note ""

# --- 3. LaunchAgents and LaunchDaemons -----------------------------------------
say "3. LaunchAgents (run when you log in)"
for d in /Library/LaunchAgents "$HOME/Library/LaunchAgents"; do
    note "--- $d ---"
    [ -d "$d" ] && ls -la "$d" >>"$OUT" 2>&1
    note ""
done

say "3b. LaunchDaemons (run as root at boot, system-wide)"
for d in /Library/LaunchDaemons /System/Library/LaunchDaemons; do
    note "--- $d (count: $(ls -1 "$d" 2>/dev/null | wc -l | tr -d ' ')) ---"
done
note ""
note "Non-Apple LaunchDaemons (third-party — these are the interesting ones):"
ls -1 /Library/LaunchDaemons/*.plist 2>/dev/null | while read -r p; do
    label=$(basename "$p" .plist)
    prog=$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$p" 2>/dev/null \
           || /usr/libexec/PlistBuddy -c 'Print :Program' "$p" 2>/dev/null)
    note "  $label   →   $prog"
done
note ""
note "Non-Apple LaunchAgents (system + user):"
for d in /Library/LaunchAgents "$HOME/Library/LaunchAgents"; do
    ls -1 "$d"/*.plist 2>/dev/null | while read -r p; do
        label=$(basename "$p" .plist)
        prog=$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$p" 2>/dev/null \
               || /usr/libexec/PlistBuddy -c 'Print :Program' "$p" 2>/dev/null)
        note "  [$d] $label   →   $prog"
    done
done

say "3c. launchctl list (currently loaded — third-party only)"
run "launchctl list | grep -viE '^-|com\\.apple\\.'"

if sudo -n true 2>/dev/null; then
    say "3d. sudo launchctl print system | grep services"
    run "sudo launchctl print system 2>/dev/null | grep -E 'service ' | grep -viE 'com\\.apple\\.' | head -200"
fi

# --- 4. Login items ------------------------------------------------------------
say "4. Login items (open at login)"
run "osascript -e 'tell application \"System Events\" to get the name of every login item'"
note "Modern (LaunchServices-managed) login items DB:"
run "sfltool dumpbtm 2>/dev/null | head -200"

# --- 5. System Extensions and Kernel Extensions --------------------------------
say "5. System Extensions (modern macOS) — EDR, network filters, file providers live here"
run "systemextensionsctl list"
if sudo -n true 2>/dev/null; then
    say "5b. Kernel Extensions (legacy)"
    run "sudo kextstat | grep -v com.apple"
fi

# --- 6. Configuration Profiles (MDM) ------------------------------------------
say "6. Configuration Profiles (MDM-pushed settings)"
run "profiles list 2>/dev/null"
run "profiles status -type enrollment"

# --- 7. Known observability and EDR agents -------------------------------------
say "7. Known observability / EDR / monitoring agents"
declare -a CHECKS=(
    "/Library/Application Support/Dynatrace/OneAgent|Dynatrace OneAgent"
    "/Library/Dynatrace|Dynatrace alt path"
    "/Library/Application Support/Datadog|Datadog Agent"
    "/opt/datadog-agent|Datadog Agent (opt)"
    "/Library/Application Support/New Relic|New Relic"
    "/Applications/SplunkForwarder.app|Splunk Forwarder"
    "/Library/Elastic|Elastic Agent"
    "/Library/Application Support/AppDynamics|AppDynamics"
    "/Applications/Falcon.app|CrowdStrike Falcon (EDR)"
    "/Library/Application Support/CrowdStrike|CrowdStrike data"
    "/Applications/SentinelOne|SentinelOne (EDR)"
    "/Applications/CarbonBlack|Carbon Black (EDR)"
    "/Library/CS/cbmacosagent.app|Carbon Black agent"
    "/Applications/Cisco/Cisco AnyConnect Secure Mobility Client.app|Cisco AnyConnect"
    "/Applications/GlobalProtect.app|Palo Alto GlobalProtect"
    "/Applications/Microsoft Defender.app|Microsoft Defender"
    "/Applications/Jamf.app|Jamf Self Service (MDM)"
    "/Applications/Kandji Self Service.app|Kandji (MDM)"
    "/Applications/Mosyle Self-Service.app|Mosyle (MDM)"
    "/Applications/Workspace ONE Intelligent Hub.app|VMware Workspace ONE"
    "/Library/Application Support/Microsoft/Intune|Microsoft Intune"
    "/Applications/Company Portal.app|Microsoft Intune Portal"
    "/Library/Application Support/com.teamviewer.TeamViewer|TeamViewer (remote)"
    "/Applications/AnyDesk.app|AnyDesk (remote)"
    "/Library/Application Support/Logitech|Logitech (often analytics)"
    "/Library/Application Support/Adobe|Adobe (telemetry)"
    "/Applications/Slack.app|Slack (analytics)"
    "/Applications/zoom.us.app|Zoom (analytics)"
    "/Applications/Microsoft Teams.app|Microsoft Teams (telemetry)"
)
for entry in "${CHECKS[@]}"; do
    path="${entry%%|*}"; name="${entry##*|}"
    if [ -e "$path" ]; then note "FOUND  $name   →   $path"
    else note "absent $name"
    fi
done

# --- 8. Anthropic / Claude artifacts ------------------------------------------
say "8. Anthropic / Claude config and caches"
for p in "$HOME/.claude" "$HOME/.config/claude" "$HOME/Library/Application Support/Claude" \
         "$HOME/Library/Application Support/Cowork" "$HOME/Library/Caches/com.anthropic.*" \
         "$HOME/Library/Logs/Claude" "$HOME/Library/Logs/Cowork"; do
    if [ -e "$p" ]; then
        note "FOUND $p ($(du -sh "$p" 2>/dev/null | awk '{print $1}'))"
    fi
done
note ""
note "Anthropic / OTEL keys in ~/.claude.json (redacted):"
[ -r "$HOME/.claude.json" ] && \
    grep -iE 'otel|telemetry|exporter|endpoint|dynatrace|tracing|prompt_log' "$HOME/.claude.json" \
    | sed -E 's/(token|key|secret)"\s*:\s*"[^"]*"/\1": "<redacted>"/g' >>"$OUT"
note ""

# --- 9. Browser telemetry ------------------------------------------------------
say "9. Browser telemetry preferences"

note "--- Safari ---"
run "defaults read com.apple.Safari SendDoNotTrackHTTPHeader 2>/dev/null"
run "defaults read com.apple.Safari UniversalSearchEnabled 2>/dev/null"
run "defaults read com.apple.Safari WebKitPreferences.diagnosticLoggingEnabled 2>/dev/null"

note "--- Chrome (look for metrics_reporting_enabled in Local State) ---"
chrome_ls="$HOME/Library/Application Support/Google/Chrome/Local State"
[ -r "$chrome_ls" ] && python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print('metrics_reporting_enabled:', d.get('user_experience_metrics',{}).get('reporting_enabled')); print('crash_reporting_enabled:', d.get('user_experience_metrics',{}).get('stability',{}).get('exited_cleanly'))" "$chrome_ls" >>"$OUT" 2>&1

note "--- Edge ---"
edge_ls="$HOME/Library/Application Support/Microsoft Edge/Local State"
[ -r "$edge_ls" ] && python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print('metrics_reporting_enabled:', d.get('user_experience_metrics',{}).get('reporting_enabled'))" "$edge_ls" >>"$OUT" 2>&1

note "--- Firefox prefs.js (telemetry-related) ---"
for prof in "$HOME/Library/Application Support/Firefox/Profiles/"*.default*; do
    [ -r "$prof/prefs.js" ] && grep -iE 'telemetry|datareporting|crashreporter|healthreport' "$prof/prefs.js" >>"$OUT" 2>&1
done

note "--- Arc / Brave / Vivaldi installed? ---"
for app in "/Applications/Arc.app" "/Applications/Brave Browser.app" "/Applications/Vivaldi.app"; do
    [ -e "$app" ] && note "FOUND $app"
done

note ""
note "Browser extensions (count per browser — review manually):"
for d in "$HOME/Library/Application Support/Google/Chrome/Default/Extensions" \
         "$HOME/Library/Application Support/Microsoft Edge/Default/Extensions" \
         "$HOME/Library/Application Support/BraveSoftware/Brave-Browser/Default/Extensions"; do
    if [ -d "$d" ]; then
        count=$(ls -1 "$d" 2>/dev/null | wc -l | tr -d ' ')
        note "  $d → $count extensions"
    fi
done

# --- 10. Network: outbound connections, listening ports -----------------------
say "10. Network — listening ports + established outbound (snapshot)"
if sudo -n true 2>/dev/null; then
    run "sudo lsof -nP -iTCP -sTCP:LISTEN | head -100"
    note "Established outbound (top 80, excluding localhost):"
    run "sudo lsof -nP -iTCP -sTCP:ESTABLISHED 2>/dev/null | grep -v '127.0.0.1\\|::1' | head -80"
else
    run "lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | head -50"
    run "lsof -nP -iTCP -sTCP:ESTABLISHED 2>/dev/null | grep -v '127.0.0.1\\|::1' | head -50"
fi

note ""
note "DNS lookups for known telemetry endpoints (does the OS resolve them?):"
for h in vit18089.live.dynatrace.com api.anthropic.com statsigapi.net browser.sentry-cdn.com \
         api.datadoghq.com mobile.events.data.microsoft.com firebaselogging-pa.googleapis.com; do
    ip=$(dscacheutil -q host -a name "$h" 2>/dev/null | awk '/ip_address:/ {print $2; exit}')
    note "  $h → ${ip:-<no cached entry>}"
done

# --- 11. /etc/hosts, /etc/resolver, sudoers extras ----------------------------
say "11. /etc/hosts (look for redirects)"
run "grep -vE '^\\s*#|^\\s*$' /etc/hosts"

# --- 12. Cron and at jobs ------------------------------------------------------
say "12. Cron / periodic jobs"
run "crontab -l 2>/dev/null"
run "ls -la /etc/cron.d /etc/periodic 2>/dev/null"

# --- 13. Top processes by name (telemetry-pattern matched) ---------------------
say "13. Running processes matching telemetry / observability patterns"
ps -axo pid,user,comm | grep -iE 'oneagent|dynatrace|datadog|newrelic|sentinel|falcon|cbagent|cbdaemon|sentry|honeycomb|otelcol|otel|jamf|kandji|mosyle|intune|teamviewer|anydesk|splunk|elastic-agent|appdynamics|filebeat|metricbeat|fluentd|fluent-bit|telegraf|collectd|prometheus|grafana-agent|claude|cowork|anthropic' | grep -v grep >>"$OUT" 2>&1

# --- 14. /private/etc and /Library defaults of interest ------------------------
say "14. System-wide defaults for telemetry"
run "defaults read /Library/Preferences/.GlobalPreferences 2>/dev/null | head -40"
run "ls /Library/Managed\\ Preferences 2>/dev/null"

# --- 15. Wrap up ---------------------------------------------------------------
say "Done."
note "Report saved to: $OUT"
note ""
note "Next steps:"
note "  1. Open the report:  open -e $OUT"
note "  2. Anything you don't recognize → ask Dynatrace IT before disabling."
note "  3. For continuous outbound monitoring, install Little Snitch or LuLu."

echo "Report written to $OUT"
echo "Open with:  open -e $OUT"
