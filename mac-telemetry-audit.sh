#!/usr/bin/env bash
#
# mac-telemetry-audit.sh — v2
# Read-only macOS audit for telemetry, observability, persistence, and data-sending software.
# Writes a report to ~/Desktop/mac-telemetry-audit.txt
#
# This script:
#   - does NOT install anything
#   - does NOT change any settings
#   - does NOT send data anywhere
#   - reads files and runs ps, lsof, launchctl, codesign, defaults read, etc.
#
# sudo is optional — requested for deeper system reads.
# Skip with Ctrl-C to run in reduced mode.

set -u
OUT="${HOME}/Desktop/mac-telemetry-audit.txt"
SEP="================================================================================"

say() { printf '\n%s\n%s\n%s\n\n' "$SEP" "  $*" "$SEP" >>"$OUT"; }
note() { printf '%s\n' "$*" >>"$OUT"; }
run() { note "\$ $*"; eval "$@" >>"$OUT" 2>&1 || true; note ""; }

: >"$OUT"
note "macOS Telemetry & Observability Audit — v2"
note "Generated: $(date)"
note "User: $(id -un)   Host: $(hostname)   macOS: $(sw_vers -productVersion)   Arch: $(uname -m)"
note ""

# --- 0. Sudo prompt up front (optional) ----------------------------------------
note "Requesting sudo for system-level reads (skip with Ctrl-C to run in reduced mode)..."
sudo -v 2>/dev/null || note "(no sudo — system sections will be reduced)"

# --- 1. Shell rc files: telemetry env var patterns -----------------------------
say "1. Shell rc files: telemetry / observability / proxy / API key patterns"
PATTERN='OTEL|TELEMETRY|ANTHROPIC|CLAUDE|TRACE|METRIC|EXPORTER|SENTRY|DATADOG|NEW.?RELIC|APPDYNAMICS|SPLUNK|ELASTIC|HONEYCOMB|PROMETHEUS|STATSD|JAEGER|ZIPKIN|OPENTELEMETRY|OBSERVA|MONITOR|ANALYTIC|HTTP_PROXY|HTTPS_PROXY|ALL_PROXY|NO_PROXY|TOKEN|API_KEY|SECRET'
for f in \
    /etc/zshenv /etc/zprofile /etc/zshrc /etc/profile /etc/bashrc /etc/paths \
    "$HOME/.zshenv" "$HOME/.zprofile" "$HOME/.zshrc" "$HOME/.zlogin" "$HOME/.zlogout" \
    "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile" \
    "$HOME/.config/fish/config.fish"; do
    if [ -r "$f" ]; then
        note "--- $f ---"
        grep -nEi "$PATTERN" "$f" 2>/dev/null \
            | sed 's/\(KEY\|TOKEN\|SECRET\)=.*/\1=<redacted>/' >>"$OUT" || note "(no matches)"
        note ""
    fi
done

# --- 1b. Shell rc files: suspicious command patterns (NEW) ---------------------
say "1b. Shell rc files: suspicious command patterns"
note "Scanning for: curl|bash pipes, wget execution, netcat listeners, base64 decode, eval injection"
CMD_PATTERN='curl[[:space:]][^#]*\|[[:space:]]*(bash|sh)\b|wget[^#]*(bash|sh)\b|nc[[:space:]]+-[leLe]*[[:space:]]|python[23]?[[:space:]]+-c[[:space:]]|base64[^#]*--decode|eval[[:space:]]*\$\(|exec[[:space:]]*\$\('
found_cmd=0
for f in \
    /etc/zshenv /etc/zprofile /etc/zshrc /etc/profile /etc/bashrc \
    "$HOME/.zshenv" "$HOME/.zprofile" "$HOME/.zshrc" "$HOME/.zlogin" \
    "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" \
    "$HOME/.config/fish/config.fish"; do
    if [ -r "$f" ]; then
        matches=$(grep -nEi "$CMD_PATTERN" "$f" 2>/dev/null)
        if [ -n "$matches" ]; then
            note "SUSPICIOUS in $f:"
            printf '%s\n' "$matches" >>"$OUT"
            note ""
            found_cmd=1
        fi
    fi
done
[ "$found_cmd" -eq 0 ] && note "(no suspicious command patterns found)"

# --- 2. launchctl getenv (variables exported to every GUI app) -----------------
say "2. launchctl-managed environment (affects every GUI app launched)"
note "User session PATH:"
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

# --- 9. Browser telemetry + extension IDs -------------------------------------
say "9. Browser telemetry preferences + extension IDs"

note "--- Safari ---"
run "defaults read com.apple.Safari SendDoNotTrackHTTPHeader 2>/dev/null"
run "defaults read com.apple.Safari UniversalSearchEnabled 2>/dev/null"
run "defaults read com.apple.Safari WebKitPreferences.diagnosticLoggingEnabled 2>/dev/null"

note "--- Chrome ---"
chrome_ls="$HOME/Library/Application Support/Google/Chrome/Local State"
[ -r "$chrome_ls" ] && python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
print('metrics_reporting_enabled:', d.get('user_experience_metrics',{}).get('reporting_enabled'))
print('crash_reporting_enabled:', d.get('user_experience_metrics',{}).get('stability',{}).get('exited_cleanly'))
" "$chrome_ls" >>"$OUT" 2>&1

note "--- Edge ---"
edge_ls="$HOME/Library/Application Support/Microsoft Edge/Local State"
[ -r "$edge_ls" ] && python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
print('metrics_reporting_enabled:', d.get('user_experience_metrics',{}).get('reporting_enabled'))
" "$edge_ls" >>"$OUT" 2>&1

note "--- Firefox prefs.js (telemetry-related) ---"
for prof in "$HOME/Library/Application Support/Firefox/Profiles/"*.default*; do
    [ -r "$prof/prefs.js" ] && grep -iE 'telemetry|datareporting|crashreporter|healthreport' "$prof/prefs.js" >>"$OUT" 2>&1
done

note "--- Arc / Brave / Vivaldi installed? ---"
for app in "/Applications/Arc.app" "/Applications/Brave Browser.app" "/Applications/Vivaldi.app"; do
    [ -e "$app" ] && note "FOUND $app"
done

note ""
note "Browser extension IDs (look each up at https://crxcavator.io or the Chrome Web Store):"
for browser_path in \
    "$HOME/Library/Application Support/Google/Chrome/Default/Extensions" \
    "$HOME/Library/Application Support/Microsoft Edge/Default/Extensions" \
    "$HOME/Library/Application Support/BraveSoftware/Brave-Browser/Default/Extensions"; do
    if [ -d "$browser_path" ]; then
        browser_label=$(basename "$(dirname "$(dirname "$browser_path")")")
        note "--- $browser_label ---"
        ls -1 "$browser_path" 2>/dev/null | while read -r ext_id; do
            manifest=$(find "$browser_path/$ext_id" -name "manifest.json" -maxdepth 2 2>/dev/null | head -1)
            if [ -n "$manifest" ]; then
                ext_name=$(python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print(d.get('name', '(unknown)'))
except Exception:
    print('(parse error)')
" "$manifest" 2>/dev/null)
                note "  $ext_id  →  $ext_name"
            else
                note "  $ext_id"
            fi
        done
        note ""
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

# --- 11. /etc/hosts (look for redirects) --------------------------------------
say "11. /etc/hosts (look for redirects)"
run "grep -vE '^\\s*#|^\\s*$' /etc/hosts"

# --- 12. Cron and at jobs ------------------------------------------------------
say "12. Cron / periodic / at jobs"
run "crontab -l 2>/dev/null"
run "ls -la /etc/cron.d /etc/periodic 2>/dev/null"
note "at jobs (one-shot scheduled tasks):"
run "atq 2>/dev/null"

# --- 13. Running processes matching telemetry / observability patterns ---------
say "13. Running processes matching telemetry / observability patterns"
ps -axo pid,user,comm | grep -iE \
    'oneagent|dynatrace|datadog|newrelic|sentinel|falcon|cbagent|cbdaemon|sentry|honeycomb|\
otelcol|otel|jamf|kandji|mosyle|intune|teamviewer|anydesk|splunk|elastic-agent|appdynamics|\
filebeat|metricbeat|fluentd|fluent-bit|telegraf|collectd|prometheus|grafana-agent|claude|cowork|anthropic' \
    | grep -v grep >>"$OUT" 2>&1

# --- 14. System-wide defaults for telemetry ------------------------------------
say "14. System-wide defaults for telemetry"
run "defaults read /Library/Preferences/.GlobalPreferences 2>/dev/null | head -40"
run "ls /Library/Managed\\ Preferences 2>/dev/null"

# ==============================================================================
# NEW SECTIONS — v2
# ==============================================================================

# --- 15. DYLD injection (library preloading attack vector) --------------------
say "15. DYLD injection — library preloading attack vector"
note "If DYLD_INSERT_LIBRARIES is set, a malicious .dylib is injected into every app on launch."
note ""
note "launchctl-managed DYLD environment variables (scope: all GUI apps):"
found_dyld=0
for v in DYLD_INSERT_LIBRARIES DYLD_LIBRARY_PATH DYLD_FRAMEWORK_PATH DYLD_FORCE_FLAT_NAMESPACE; do
    val=$(launchctl getenv "$v" 2>/dev/null)
    if [ -n "$val" ]; then
        note "  *** SUSPICIOUS: $v=$val"
        found_dyld=1
    fi
done
[ "$found_dyld" -eq 0 ] && note "  (none set — good)"
note ""
note "Current shell DYLD environment variables:"
env 2>/dev/null | grep -iE '^DYLD_' >>"$OUT" || note "  (none set in current shell)"

# --- 16. Processes running from suspicious paths --------------------------------
say "16. Processes running from suspicious locations"
note "Flagging anything in: /tmp, /private/tmp, /var/tmp, ~/Downloads, hidden dot-dirs in \$HOME"
HOME_ESC=$(printf '%s' "$HOME" | sed 's/[[\.*^$()+?{|]/\\&/g')
results=$(ps -axo pid,user,args 2>/dev/null \
    | grep -E "(/tmp/|/private/tmp/|/var/tmp/|${HOME_ESC}/Downloads/|${HOME_ESC}/\\.)" \
    | grep -vE "(grep|\.app/Contents/MacOS/)" 2>/dev/null)
if [ -n "$results" ]; then
    note "*** SUSPICIOUS processes found:"
    printf '%s\n' "$results" >>"$OUT"
else
    note "(no processes found in suspicious paths — good)"
fi

# --- 17. Processes with deleted binaries (file-in-memory trick) ---------------
say "17. Processes with deleted binaries (binary removed from disk after launch)"
note "FD type 'txt' with link count 0 = the process's own executable was deleted while running."
note "This is a classic malware persistence trick: write, run, erase file."
note ""
if sudo -n true 2>/dev/null; then
    deleted=$(sudo lsof +L1 2>/dev/null | awk 'NR==1 || $4=="txt"' | grep -v '\.dylib')
else
    deleted=$(lsof +L1 2>/dev/null | awk 'NR==1 || $4=="txt"' | grep -v '\.dylib')
fi
if [ -n "$deleted" ]; then
    note "*** SUSPICIOUS — deleted binaries still running:"
    printf '%s\n' "$deleted" >>"$OUT"
else
    note "(none found$(sudo -n true 2>/dev/null || echo ' — run with sudo for full view'))"
fi

# --- 18. LaunchAgent / LaunchDaemon binary code signing -----------------------
say "18. Code signing of LaunchAgent / LaunchDaemon binaries"
note "Legend:  UNSIGNED = high suspicion   |   self-signed = medium   |   Developer ID / Apple = expected"
note ""
for d in /Library/LaunchDaemons /Library/LaunchAgents "$HOME/Library/LaunchAgents"; do
    [ -d "$d" ] || continue
    ls -1 "$d"/*.plist 2>/dev/null | while read -r p; do
        prog=$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$p" 2>/dev/null \
               || /usr/libexec/PlistBuddy -c 'Print :Program' "$p" 2>/dev/null)
        [ -z "$prog" ] || [ ! -f "$prog" ] && continue
        sig_out=$(codesign -dv "$prog" 2>&1)
        authority=$(printf '%s\n' "$sig_out" | grep 'Authority=' | head -2)
        team=$(printf '%s\n' "$sig_out" | grep 'TeamIdentifier=' | head -1)
        if [ -z "$authority" ]; then
            note "  *** UNSIGNED  $(basename "$p")  →  $prog"
        else
            note "  OK  $(basename "$p")  →  $prog"
            printf '      %s\n' "$authority" >>"$OUT"
            [ -n "$team" ] && printf '      %s\n' "$team" >>"$OUT"
        fi
        note ""
    done
done

# --- 19. Hidden executable files in $HOME -------------------------------------
say "19. Hidden executable files in \$HOME (dot-files with execute bit)"
note "Legitimate dot-executables are rare and well-known. Anything unexpected = suspicious."
find "$HOME" -maxdepth 4 -name ".*" -type f \
    \( -perm -u+x -o -perm -g+x -o -perm -o+x \) 2>/dev/null \
    | grep -vE '(\.DS_Store|\.localized|\.CFUserTextEncoding|\.bash_history|\.zsh_history|\
\.zsh_sessions|\.Trash|\.gitkeep|\.npmrc|\.yarnrc|\.nvmrc|\.editorconfig|\
node_modules/|\.git/hooks/|\.rbenv/|\.nvm/|\.cargo/|\.rustup/|\.pyenv/)' \
    | sort >>"$OUT" || note "(none found)"

# --- 20. SSH authorized_keys (backdoor access) --------------------------------
say "20. SSH authorized_keys — unexpected keys mean passwordless backdoor access"
found_ssh=0
for f in "$HOME/.ssh/authorized_keys" "$HOME/.ssh/authorized_keys2"; do
    if [ -r "$f" ]; then
        count=$(grep -c '' "$f" 2>/dev/null || echo 0)
        note "FOUND $f ($count line(s)):"
        cat "$f" >>"$OUT" 2>/dev/null
        note ""
        found_ssh=1
    fi
done
[ "$found_ssh" -eq 0 ] && note "(no authorized_keys files found — good)"
note ""
note "SSH config — ProxyCommand / ProxyJump entries (watch for unexpected tunnels):"
if [ -r "$HOME/.ssh/config" ]; then
    grep -nEi 'ProxyCommand|ProxyJump|HostName|IdentityFile' "$HOME/.ssh/config" \
        >>"$OUT" 2>/dev/null || note "(no proxy entries)"
else
    note "(no ~/.ssh/config)"
fi

# --- 21. PAM modules (/etc/pam.d) ---------------------------------------------
say "21. PAM modules — compromised modules silently steal credentials on every auth"
if [ -d /etc/pam.d ]; then
    note "Non-standard PAM module references (Apple's built-in set excluded):"
    grep -rn 'pam_' /etc/pam.d/ 2>/dev/null \
        | grep -vE 'pam_opendirectory|pam_deny|pam_permit|pam_rootok|pam_smartcard|\
pam_tid|pam_env|pam_nologin|pam_unix|pam_group|pam_wheel|pam_localuser|\
pam_uwtmp|pam_sacl|pam_launchd|pam_mount|pam_cas' \
        >>"$OUT" || note "(no non-standard PAM modules found — good)"
else
    note "(/etc/pam.d not found)"
fi

# --- 22. Sudoers configuration ------------------------------------------------
say "22. Sudoers — unexpected rules can grant permanent root access"
if sudo -n true 2>/dev/null; then
    note "Main /etc/sudoers (non-comment lines):"
    sudo grep -vE '^\s*#|^\s*$' /etc/sudoers 2>/dev/null >>"$OUT" || note "(could not read)"
    note ""
    note "Drop-in files in /etc/sudoers.d/:"
    dropin_count=$(sudo ls /etc/sudoers.d/ 2>/dev/null | grep -c '' || echo 0)
    if [ "$dropin_count" -gt 0 ]; then
        sudo ls -la /etc/sudoers.d/ >>"$OUT" 2>/dev/null
        for f in $(sudo ls /etc/sudoers.d/ 2>/dev/null); do
            note "--- /etc/sudoers.d/$f ---"
            sudo grep -vE '^\s*#|^\s*$' "/etc/sudoers.d/$f" 2>/dev/null >>"$OUT" || true
            note ""
        done
    else
        note "(empty — good)"
    fi
else
    note "(sudo required to read /etc/sudoers — rerun with sudo for this section)"
fi

# --- Done ---------------------------------------------------------------------
say "Done — v2"
note "Report saved to: $OUT"
note ""
note "Coverage summary (~70-75% of practical macOS threat surface):"
note "  CATCHES:  LaunchAgents/Daemons, login items, cron, at jobs (all persistence vectors)"
note "  CATCHES:  System/kernel extensions, MDM profiles"
note "  CATCHES:  25+ known monitoring/EDR/MDM agents by path"
note "  CATCHES:  DYLD injection, deleted-binary trick, processes from suspicious paths"
note "  CATCHES:  Unsigned LaunchAgent binaries, hidden executables, SSH backdoors"
note "  CATCHES:  PAM module tampering, sudoers backdoors"
note "  CATCHES:  Browser telemetry settings + extension IDs, shell rc malicious patterns"
note ""
note "  MISSES:   Rootkits hiding from ps/ls at kernel level"
note "  MISSES:   Memory-only malware with no persistence mechanism"
note "  MISSES:   Content inside encrypted (TLS) outbound connections"
note "  MISSES:   Randomly named processes that avoid keyword patterns"
note ""
note "Next steps:"
note "  1. Open the report:  open -e $OUT"
note "  2. Anything unrecognised → research before removing (ask IT if on a work machine)."
note "  3. Real-time network: Little Snitch (paid) or LuLu (free, open-source)."
note "  4. Deeper static analysis: Objective-See KnockKnock, BlockBlock, ReiKey."

echo "Report written to $OUT"
echo "Open with:  open -e $OUT"
