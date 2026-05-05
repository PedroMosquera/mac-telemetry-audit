# mac-telemetry-audit

> **⚠️ FOR RECREATIONAL & EDUCATIONAL PURPOSES ONLY.**
> This script is a personal curiosity tool. It is not a security product, not a
> compliance scanner, and not a substitute for professional security advice.
> Use it to learn what software is running on your own Mac — nothing more.

---

## What is this?

`mac-telemetry-audit.sh` is a **read-only macOS privacy and observability audit script**.
It scans your Mac to reveal *what software may be watching, monitoring, or reporting data*
from your machine — without installing anything, changing any settings, or sending data anywhere.

Think of it as shining a torch under the hood of your own Mac.

---

## What it checks

| # | Area | Details |
|---|------|---------|
| 1 | **Shell config files** | Scans `.zshrc`, `.bashrc`, etc. for env vars related to telemetry, API keys, proxy settings, and monitoring endpoints (patterns: `OTEL`, `ANTHROPIC`, `SENTRY`, `DATADOG`, `TOKEN`…) |
| 2 | **launchctl environment** | Variables exported to every GUI app via `launchctl getenv` |
| 3 | **LaunchAgents & LaunchDaemons** | What auto-starts at login/boot — both Apple and third-party |
| 4 | **Login items** | Software registered to open at login (classic + modern `sfltool dumpbtm`) |
| 5 | **System & Kernel Extensions** | EDR/security tools using modern system extensions or legacy kexts |
| 6 | **MDM Configuration Profiles** | What your employer (or any MDM) may have pushed onto the device |
| 7 | **Known monitoring agents** | 25+ agents checked by path: Dynatrace OneAgent, Datadog, New Relic, Splunk, CrowdStrike Falcon, SentinelOne, Carbon Black, Jamf, Kandji, Mosyle, Intune, TeamViewer, AnyDesk, Zoom, Slack, Adobe, and more |
| 8 | **Anthropic / Claude config** | Local Claude Code config, caches, and OTEL/telemetry keys (redacted) |
| 9 | **Browser telemetry** | Safari, Chrome, Edge, Firefox — metrics reporting, crash reporting, diagnostic logging preferences |
| 10 | **Network snapshot** | Listening ports + established outbound connections (excluding localhost); DNS cache for known telemetry hostnames |
| 11 | **`/etc/hosts`** | Detects any redirects for known endpoints |
| 12 | **Cron / periodic jobs** | User crontab + system periodic directories |
| 13 | **Running processes** | Live `ps` output filtered for 40+ telemetry/observability keywords |
| 14 | **System-wide defaults** | `/Library/Preferences/.GlobalPreferences` + Managed Preferences |

All output is saved to `~/Desktop/mac-telemetry-audit.txt`.

---

## What it does NOT do

- ❌ Does NOT install anything
- ❌ Does NOT change any settings
- ❌ Does NOT send data anywhere
- ❌ Does NOT kill or disable any process

It is **purely read-only**.

---

## How to run

```bash
# Make executable (first time only)
chmod +x mac-telemetry-audit.sh

# Run
./mac-telemetry-audit.sh

# Open the report
open -e ~/Desktop/mac-telemetry-audit.txt
```

`sudo` is requested at startup for a handful of system-level reads
(`launchctl print system/`, `lsof -i`, `kextstat`).
You can skip `sudo` with **Ctrl-C** at the prompt — those sections will
show reduced output, but everything else will still work.

---

## Requirements

- macOS (tested on Ventura / Sonoma / Sequoia, Intel + Apple Silicon)
- Bash 3.2+ (ships with macOS)
- Optional: `sudo` for deeper system reads

No third-party tools or Homebrew packages required.

---

## Sample output (excerpt)

```
================================================================================
  7. Known observability / EDR / monitoring agents
================================================================================

FOUND  Dynatrace OneAgent   →   /Library/Application Support/Dynatrace/OneAgent
absent Datadog Agent
absent New Relic
...
```

---

## Next steps after running

1. Open the report: `open -e ~/Desktop/mac-telemetry-audit.txt`
2. Anything you don't recognise → ask your IT/security team before disabling it.
3. For **continuous** outbound connection monitoring, consider
   [Little Snitch](https://www.obdev.at/products/littlesnitch/) or
   [LuLu](https://objective-see.org/products/lulu.html) (free, open-source).

---

## Disclaimer

> This script is provided **as-is, for recreational and educational purposes only**.
> The author makes no warranties, express or implied, about the accuracy,
> completeness, or fitness for any particular purpose of the information produced.
> Running this script is your own responsibility. Do not use it on machines you
> do not own or do not have explicit permission to audit.
> This is not a security product. It will not protect you from anything.
> It just helps you see what's already there.

---

*Inspired by curiosity about what runs quietly in the background on a typical developer's Mac.*
