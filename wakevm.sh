#!/bin/bash

# WakeVM - Wake-on-LAN listener for Proxmox guests
# Created by nachobacanful 
# https://github.com/nachobacanful/wakevm.git

# Configuration
declare -A mac_lookup
WATCH_PATHS=("/etc/pve/qemu-server" "/etc/pve/lxc")
DEBUG=false
TAG_MODE=false
REQUIRED_TAG="wol"
DISABLE_WATCHER=false
DRY_RUN=false
TMP_PIPE="/tmp/wolpipe.$$"

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--debug) DEBUG=true; shift ;;
        -e|--tag-only) TAG_MODE=true; shift ;;
        --tag) shift; REQUIRED_TAG="$1"; shift ;;
        -w|--disable-watcher) DISABLE_WATCHER=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  -d, --debug             Enable debug output"
            echo "  -e, --tag-only          Only start guests with a matching tag"
            echo "      --tag <tag>         Tag name to match (default: wol)"
            echo "  -w, --disable-watcher   Disable automatic config watcher"
            echo "      --dry-run           Simulate behavior without starting guests"
            echo "  -h, --help              Show this help message"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Build the MAC map
declare -A mac_lookup
build_mac_map() {
    echo "[Watcher] Updating MAC map..."
    mac_lookup=()

    for vmid in $(qm list | awk 'NR>1 {print $1}'); do
        while IFS= read -r line; do
            mac=$(echo "$line" | sed -n 's/.*[[:alnum:]]=\([0-9A-Fa-f:]{17}\).*/\1/p' | tr '[:upper:]' '[:lower:]')
            if [ -n "$mac" ]; then
                $DEBUG && echo "[DEBUG] Adding VM $vmid MAC: $mac"
                mac_lookup["$mac"]="vm:$vmid"
            fi
        done < <(qm config "$vmid" 2>/dev/null | grep -E '^net[0-9]+:')
    done

    for ctid in $(pct list | awk 'NR>1 {print $1}'); do
        while IFS= read -r line; do
            mac=$(echo "$line" | sed -n 's/.*hwaddr=\([0-9A-Fa-f:]{17}\).*/\1/p' | tr '[:upper:]' '[:lower:]')
            if [ -n "$mac" ]; then
                $DEBUG && echo "[DEBUG] Adding CT $ctid MAC: $mac"
                mac_lookup["$mac"]="ct:$ctid"
            fi
        done < <(pct config "$ctid" 2>/dev/null | grep -E '^net[0-9]+:')
    done

    echo "[Watcher] MAC map rebuilt (${#mac_lookup[@]} entries)"
    for mac in "${!mac_lookup[@]}"; do
        echo "[table] ${mac_lookup[$mac]} -> $mac"
    done
    echo "[Watcher] Done updating MAC map."
}

# Watch for config changes
start_watcher() {
    while inotifywait -qq -e modify,create,delete "${WATCH_PATHS[@]}"; do
        echo "[Watcher] Change detected in VM or LXC config"
        build_mac_map
    done
}

# Start guest by MAC
start_guest_by_mac() {
    local mac="$1"
    guest="${mac_lookup[$mac]}"

    if [ -z "$guest" ]; then
        echo "[WOL] No match for MAC $mac"
        return
    fi

    type=$(echo "$guest" | cut -d: -f1)
    id=$(echo "$guest" | cut -d: -f2)

    if $TAG_MODE; then
        tags=$(if [ "$type" = "vm" ]; then qm config "$id"; else pct config "$id"; fi | awk -F': ' '/^tags:/ {print $2}')
        IFS=';' read -ra tag_array <<< "$tags"
        found=false
        for tag in "${tag_array[@]}"; do
            [ "$tag" = "$REQUIRED_TAG" ] && found=true && break
        done
        if ! $found; then
            echo "[WOL] MAC $mac matched $type:$id but tag '$REQUIRED_TAG' not found — skipping"
            return
        fi
    fi

    echo "[WOL] Matched $mac to $type:$id"
    if $DRY_RUN; then
        echo "[DRY-RUN] Would start $type $id"
        return
    fi

    if [ "$type" = "vm" ]; then
        qm start "$id"
    elif [ "$type" = "ct" ]; then
        pct start "$id"
    fi
}

# Init

echo "[PID] Running as PID $$"
if $TAG_MODE; then
    echo "[TAG] Tag filtering enabled (tag: $REQUIRED_TAG)"
fi

build_mac_map
trap build_mac_map SIGUSR1

if ! $DISABLE_WATCHER; then
    start_watcher &
    WATCHER_PID=$!
fi

cleanup() {
    echo "[Exit] Cleaning up..."
    [[ -n "$WATCHER_PID" ]] && kill "$WATCHER_PID" 2>/dev/null
    [[ -n "$SOCAT_PID" ]] && kill "$SOCAT_PID" 2>/dev/null
    [[ -p "$TMP_PIPE" ]] && rm -f "$TMP_PIPE"
    exit
}

trap cleanup INT TERM

# WOL listener setup

echo "[WOL] Listening on UDP port 9..."
mkfifo "$TMP_PIPE"
socat -u UDP-RECV:9 STDOUT > "$TMP_PIPE" &
SOCAT_PID=$!

while read -r mac_raw; do
    mac=$(echo "$mac_raw" | sed 's/../&:/g; s/:$//' | tr '[:upper:]' '[:lower:]')
    echo "[WOL] Received magic packet for MAC: $mac"
    start_guest_by_mac "$mac"
done < <(
    cat "$TMP_PIPE" \
    | stdbuf -o0 xxd -c 6 -p \
    | stdbuf -o0 uniq \
    | stdbuf -o0 grep -v 'ffffffffffff'
)
