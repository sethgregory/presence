# presence

Detects whether you're in a Microsoft Teams meeting and optionally updates a Home Assistant `input_boolean`.

## How it works

A small Swift binary (`mic_status`) queries the CoreAudio HAL for active audio input streams using `kAudioDevicePropertyDeviceIsRunningSomewhere`. When Teams grabs the microphone for a call, this flag goes live. The shell script wraps that check with a Teams process guard and handles Home Assistant updates and logging.

> **Note:** The mic check is app-agnostic — any application capturing audio input will trigger `in_meeting`. In practice this is a reliable proxy for being on a call.

## Requirements

- macOS
- Microsoft Teams desktop app (`MSTeams`)
- Xcode Command Line Tools (for `swiftc`)
- `curl` (pre-installed on macOS)

## Build

Compile the Swift binary once before first use:

```bash
swiftc mic_status.swift -o bin/mic_status
```

## Usage

```
./presence.sh [--watch [interval_seconds]] [--json]

  (no args)       Print current status and exit
  --watch [N]     Poll every N seconds, print only on change (default: 10)
  --json          Output as JSON
```

### Examples

```bash
# One-shot check
./presence.sh

# Watch mode, update every 30 seconds
./presence.sh --watch 30

# Machine-readable output
./presence.sh --json
```

### Output values

| Status | Meaning |
|---|---|
| `IN MEETING` | Teams is running and the microphone is active |
| `Available` | Teams is running, microphone is idle |
| `Teams not running` | The MSTeams process is not found |

## Home Assistant integration

The script updates `input_boolean.meeting` via the HA REST API when status changes. Set two environment variables:

```bash
export HA_URL=http://homeassistant.local:8123
export HA_TOKEN=<long-lived access token>
```

Generate a token in Home Assistant under **Profile → Security → Long-Lived Access Tokens**.

If either variable is unset, the HA integration is silently skipped.

## Running at login (launchd)

A sample LaunchAgent plist is included in the repo as `com.sethgregory.presence.plist`. Copy and customize it, then install:

```bash
cp com.sethgregory.presence.plist ~/Library/LaunchAgents/
# Edit the copy: set HA_URL, HA_TOKEN, and correct the path to presence.sh
```

It polls every 15 seconds and starts automatically at login. The plist embeds `HA_URL` and `HA_TOKEN` directly (launchd does not source your shell profile).

**Load:**
```bash
launchctl load ~/Library/LaunchAgents/com.sethgregory.presence.plist
```

**Unload:**
```bash
launchctl unload ~/Library/LaunchAgents/com.sethgregory.presence.plist
```

**Logs:**
```
~/Library/Logs/presence.log      # status changes
~/Library/Logs/presence.err.log  # warnings and errors
```

State is persisted to `$TMPDIR/presence_last_status` between launchd invocations so HA is only called when status actually changes.

## File overview

```
presence/
├── mic_status.swift    CoreAudio input probe (Swift source)
├── bin/mic_status      Compiled binary (build before first use)
├── presence.sh         Main CLI script
└── ~/Library/LaunchAgents/com.sethgregory.presence.plist
```
