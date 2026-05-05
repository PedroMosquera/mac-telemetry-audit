# mac-telemetry-audit

> **⚠️ FOR RECREATIONAL & EDUCATIONAL PURPOSES ONLY.**
> This script is a personal curiosity tool. It is not a security product, not a
> compliance scanner, and not a substitute for professional security advice.
> Use it to learn what software is running on your own Mac — nothing more.

---

## What is this?

`mac-telemetry-audit.sh` is a **read-only macOS privacy and observability audit script**.
It scans your Mac to reveal *what software may be watching, monitoring, persisting, or reporting data*
from your machine — without installing anything, changing any settings, or sending data anywhere.

Think of it as shining a torch under the hood of your own Mac.

**Coverage: ~70–75% of the practical macOS threat surface** in pure Bash, no external tools required.

---

## What it checks

| # | Area | What it catches |
|---|------|-----------------|
| 1 | **Shell rc files — env vars** | Telemetry, API key, proxy, and monitoring variable names in `.zshrc`, `.bashrc`, etc. |
| 1b | **Shell rc files — command patterns** | `curl \| bash` pipes, `wget` execution, netcat listeners, `base64 --decode`, `eval $(...)` injections |
| 2 | **launchctl environment** | Variables exported to every GUI app via `launchctl getenv` |
| 3 | **LaunchAgents & LaunchDaemons** | Every auto-start entry at login and boot — the #1 persistence mechanism |
| 4 | **Login items** | Classic GUI login items + modern `sfltool dumpbtm` database |
| 5 | **System & Kernel Extensions** | EDR tools, network filters, file interceptors |
| 6 | **MDM Configuration Profiles** | What your employer (or any MDM) has pushed onto the device |
| 7 | **Known monitoring agents** | 25+ agents checked by path: Dynatrace, Datadog, CrowdStrike, SentinelOne, New Relic, Jamf, Intune, TeamViewer, AnyDesk, and more |
| 8 | **Anthropic / Claude config** | Local Claude Code config, caches, and telemetry keys (values redacted) |
| 9 | **Browser telemetry + extension IDs** | Safari, Chrome, Edge, Firefox metrics/crash reporting preferences; full extension ID list per browser |
| 10 | **Network snapshot** | Listening ports + established outbound connections; DNS cache for known telemetry hostnames |
| 11 | **`/etc/hosts`** | Redirects or blocks of known endpoints |
| 12 | **Cron / periodic / `at` jobs** | All scheduled execution mechanisms |
| 13 | **Running processes** | Live `ps` output filtered for 40+ telemetry/observability keywords |
| 14 | **System-wide defaults** | `/Library/Preferences/.GlobalPreferences` + Managed Preferences |
| 15 | **DYLD injection** | `DYLD_INSERT_LIBRARIES` and related vars — injects malicious `.dylib` into every app on launch |
| 16 | **Processes from suspicious paths** | Executables running from `/tmp`, `~/Downloads`, hidden dot-directories |
| 17 | **Deleted-binary processes** | Binaries that were erased from disk after launch (`lsof +L1`) — classic file-in-memory trick |
| 18 | **LaunchAgent binary signing** | Code signature check on every LaunchAgent/Daemon binary — unsigned = red flag |
| 19 | **Hidden executables in `$HOME`** | Dot-files with execute bit in your home directory |
| 20 | **SSH `authorized_keys`** | Unexpected SSH keys = passwordless backdoor access |
| 21 | **PAM modules** | Non-standard `/etc/pam.d` entries — compromised modules steal credentials silently |
| 22 | **Sudoers** | Unexpected rules in `/etc/sudoers` or `/etc/sudoers.d/` = permanent root backdoor |

All output is saved to `~/Desktop/mac-telemetry-audit.txt`.

---

## What it will NOT catch

| Blind spot | Why |
|------------|-----|
| **Rootkits hiding at kernel level** | `ps`, `ls`, `lsof` are user-space tools — kernel-level malware can lie to all of them |
| **Memory-only malware** | No file, no LaunchAgent, no persistence — runs once and leaves no trace for this script |
| **Encrypted (TLS) exfiltration content** | Outbound connections appear in the network snapshot, but what's *inside* HTTPS traffic is invisible |
| **Randomly named processes** | A process called `com.apple.updateagentd` won't match any keyword pattern |

For those, see the [External tools](#next-steps-after-running) section below.

---

## ⚠️ Risks of running this script

Running any shell script with `sudo` carries inherent risk. Here's what to know before you execute this one:

### 1. Always verify the file hash first
The `run()` helper internally uses `eval`. The hardcoded commands are safe, but if the script were
tampered with between download and execution, `eval` would execute the malicious string without resistance.

```bash
# Verify the hash matches what's published on GitHub before running
shasum -a 256 mac-telemetry-audit.sh
```

### 2. `sudo -v` refreshes your sudo token
The script calls `sudo -v` at startup to cache credentials for deeper reads. This extends your
sudo session for ~5 minutes. If a malicious process on your machine is waiting to call
`sudo something-bad`, it could ride on your freshly granted token.

**Mitigation:** Skip `sudo` with **Ctrl-C** at the prompt — the script still runs ~90% of its checks.

### 3. The output file is sensitive
`~/Desktop/mac-telemetry-audit.txt` reveals which security tools are *absent* (useful for an
attacker to know what to evade), your network connections, MDM enrollment status, and partially
redacted API key patterns. Any app with file-system access can read it.

**Mitigation:** Review it, then delete it. Don't leave it on your Desktop.

### 4. It reads sensitive browser files
Section 9 opens Chrome's `Local State` JSON to extract telemetry preferences. As written it only
reads two fields — but be aware the script has access to the same file that stores other browser state.

---

## How to run

```bash
# Make executable (first time only)
chmod +x mac-telemetry-audit.sh

# Verify the hash (recommended)
shasum -a 256 mac-telemetry-audit.sh

# Run
./mac-telemetry-audit.sh

# Open the report
open -e ~/Desktop/mac-telemetry-audit.txt
```

`sudo` is requested at startup for system-level reads
(`launchctl print system/`, `lsof -i`, `kextstat`, `/etc/sudoers`).
Skip with **Ctrl-C** — those sections show reduced output but everything else still works.

---

## Requirements

- macOS Ventura / Sonoma / Sequoia (Intel or Apple Silicon)
- Bash 3.2+ (ships with macOS)
- Python 3 (ships with macOS — used for browser JSON parsing only)
- Optional: `sudo` for deeper system reads

No Homebrew, no third-party tools.

---

## Next steps after running

1. **Open the report:** `open -e ~/Desktop/mac-telemetry-audit.txt`
2. **Anything unrecognised** → research it before removing. On a work Mac, ask IT first.
3. **Delete the report** after reviewing — it contains sensitive system info.
4. For coverage beyond ~75%, complement with these free tools:
   - **[LuLu](https://objective-see.org/products/lulu.html)** — real-time outbound connection monitoring (catches encrypted exfiltration by process)
   - **[KnockKnock](https://objective-see.org/products/knockknock.html)** — deep persistent software scanner
   - **[BlockBlock](https://objective-see.org/products/blockblock.html)** — real-time persistence installation alerts
   - **[ReiKey](https://objective-see.org/products/reikey.html)** — keylogger detection

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
