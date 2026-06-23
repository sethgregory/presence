#!/usr/bin/env bash
# Detects whether you're in a Teams meeting by checking microphone capture status.
# Requires mic_status binary to be compiled: swiftc mic_status.swift -o bin/mic_status

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY="$SCRIPT_DIR/bin/mic_status"

usage() {
  echo "Usage: $(basename "$0") [--watch [interval_seconds]] [--json]"
  echo ""
  echo "  (no args)       Print current status and exit"
  echo "  --watch [N]     Poll every N seconds (default: 10)"
  echo "  --json          Output as JSON"
  echo ""
  echo "Home Assistant (optional):"
  echo "  export HA_URL=http://homeassistant.local:8123"
  echo "  export HA_TOKEN=<long-lived access token>"
  echo "  export HA_ENTITY=input_boolean.meeting  (default)"
  exit 1
}

teams_running() {
  pgrep -x "MSTeams" > /dev/null 2>&1
}

mic_in_use() {
  "$BINARY" 2>/dev/null | grep -q "^in_use$"
}

crd_running() {
  pgrep -f "remoting_me2me_host" > /dev/null 2>&1
}

# When CRD is running it holds the mic persistently. Confirm a real meeting is
# happening by checking whether any meeting app has active WebRTC UDP sockets
# bound to a specific local address. When idle, Teams only has *:50074
# (wildcard); in a meeting it binds many sockets to real local IPs for RTP.
meeting_app_webrtc_active() {
  local pids udp_count

  # Specific meeting app processes only — broad renderer globs pull in hundreds
  # of unrelated PIDs and slow down the lsof call.
  pids=$(pgrep -x "MSTeams" 2>/dev/null)
  pids+=$'\n'$(pgrep -x "zoom.us" 2>/dev/null)
  pids+=$'\n'$(pgrep -x "Webex" 2>/dev/null)
  pids+=$'\n'$(pgrep -x "FaceTime" 2>/dev/null)

  pids=$(echo "$pids" | grep -v '^$' | sort -u | tr '\n' ',')
  pids="${pids%,}"
  [[ -z "$pids" ]] && return 1

  # Count UDP sockets bound to a real local address (not wildcard *:PORT).
  # Teams uses unconnected UDP sockets for RTP/ICE so they show as
  # "192.168.x.x:PORT" with no arrow — grep -v "^\*" excludes the idle
  # wildcard sockets, leaving only in-call media bindings.
  udp_count=$(lsof -a -p "$pids" -i UDP 2>/dev/null \
    | awk 'NR>1 {print $NF}' \
    | grep -v "^\*" \
    | grep -v "mdns" \
    | wc -l)

  [[ "$udp_count" -gt 0 ]]
}

get_status() {
  if ! teams_running; then
    echo "teams_not_running"
    return
  fi
  if mic_in_use; then
    if crd_running && ! meeting_app_webrtc_active; then
      echo "available"
    else
      echo "in_meeting"
    fi
  else
    echo "available"
  fi
}

update_ha() {
  local status="$1"
  [[ -z "${HA_URL:-}" || -z "${HA_TOKEN:-}" ]] && return

  local entity="${HA_ENTITY:-input_boolean.meeting}"
  local domain="${entity%%.*}"
  local service
  if [[ "$status" == "in_meeting" ]]; then
    service="turn_on"
  else
    service="turn_off"
  fi

  curl -sf \
    -X POST \
    -H "Authorization: Bearer $HA_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"entity_id\":\"${entity}\"}" \
    "${HA_URL}/api/services/${domain}/${service}" \
    > /dev/null \
    || echo "Warning: failed to update Home Assistant" >&2
}

format_output() {
  local status="$1"
  local ts
  ts=$(date -Iseconds)

  if [[ "$JSON" == "1" ]]; then
    printf '{"status":"%s","timestamp":"%s"}\n' "$status" "$ts"
  else
    case "$status" in
      in_meeting)          echo "[$ts] IN MEETING" ;;
      available)           echo "[$ts] Available" ;;
      teams_not_running)   echo "[$ts] Teams not running" ;;
    esac
  fi
}

# Argument parsing
WATCH=0
INTERVAL=10
JSON=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --watch)
      WATCH=1
      if [[ "${2:-}" =~ ^[0-9]+$ ]]; then
        INTERVAL="$2"
        shift
      fi
      ;;
    --json) JSON=1 ;;
    --help|-h) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
  shift
done

if [[ ! -x "$BINARY" ]]; then
  echo "Error: binary not found at $BINARY" >&2
  echo "Run: swiftc \"$SCRIPT_DIR/mic_status.swift\" -o \"$BINARY\"" >&2
  exit 1
fi

if [[ "$WATCH" == "1" ]]; then
  prev=""
  while true; do
    status=$(get_status)
    if [[ "$status" != "$prev" ]]; then
      format_output "$status"
      update_ha "$status"
      prev="$status"
    fi
    sleep "$INTERVAL"
  done
else
  STATE_FILE="${TMPDIR:-/tmp}/presence_last_status"
  status=$(get_status)
  prev=$(cat "$STATE_FILE" 2>/dev/null || echo "")
  if [[ "$status" != "$prev" ]]; then
    format_output "$status"
    update_ha "$status"
    echo "$status" > "$STATE_FILE"
  fi
fi
