#!/bin/bash

# This script expects a file called "media.json" to be available in the working directory.
# The "media.json" file should have the following structure:
#   {
#    "media1": "UUID1",
#     ...
#     ...
#     ...
#    "mediaN": "UUIDn",
#   }
# The UUIDs in the JSON file are the UUIDs of the LUKS partitions.

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

VOLUME_FILE="./media.json"

# Function to log messages with timestamp
log() {
  printf -v LOGDATE '%(%Y-%m-%d %H:%M:%S)T' -1
  echo "$LOGDATE $1"
}

# Load volumes from JSON
if [[ ! -f "$VOLUME_FILE" ]]; then
  echo "Volume config file not found: $VOLUME_FILE"
  exit 1
fi

# Read JSON into associative array
declare -A VOLUMES
while IFS="=" read -r name uuid; do
  VOLUMES["$name"]="$uuid"
done < <(jq -r 'to_entries[] | "\(.key)=\(.value)"' "$VOLUME_FILE")

open_volumes() {
  for NAME in "${!VOLUMES[@]}"; do
    UUID="${VOLUMES[$NAME]}"
    MOUNT="/media/$NAME"

    log "Unlocking $NAME ($UUID)..."
    if cryptsetup luksOpen "/dev/disk/by-uuid/$UUID" "$NAME"; then
      log "${GREEN}✔${NC} Unlocked $NAME"
    else
      log "${RED}✘${NC} Failed to unlock $NAME"
      continue
    fi

    log "Mounting /dev/mapper/$NAME to $MOUNT..."
    if mount "/dev/mapper/$NAME" "$MOUNT"; then
      log "${GREEN}✔${NC} Mounted $NAME"
    else
      log "${RED}✘${NC} Failed to mount $NAME"
    fi
  done
}

close_volumes() {
  for NAME in "${!VOLUMES[@]}"; do
    MOUNT="/media/$NAME"

    log "Unmounting $MOUNT..."
    if umount "$MOUNT"; then
      log "${GREEN}✔${NC} Unmounted $NAME"
    else
      log "${RED}✘${NC} Failed to unmount $NAME"
      continue
    fi

    log "Closing mapper $NAME..."
    if cryptsetup luksClose "$NAME"; then
      log "${GREEN}✔${NC} Closed $NAME"
    else
      log "${RED}✘${NC} Failed to close $NAME"
    fi
  done
}

status_volumes() {
  for NAME in "${!VOLUMES[@]}"; do
    MOUNT="/media/$NAME"
    MAPPER="/dev/mapper/$NAME"

    if [[ -e "$MAPPER" ]]; then
      if mountpoint -q "$MOUNT"; then
        log "${GREEN}✔${NC} $NAME is unlocked and mounted at $MOUNT"
      else
        log "${RED}✘${NC} $NAME is unlocked but not mounted"
      fi
    else
      log "${RED}✘${NC} $NAME is not unlocked"
    fi
  done
}

# Main logic
MODE="$1"
if [[ -z "$MODE" ]]; then
  echo "Usage: $0 {open|close|status}"
  exit 1
fi

case "$MODE" in
  open) open_volumes ;;
  close) close_volumes ;;
  status) status_volumes ;;
  *)
    echo "Invalid mode: $MODE"
    echo "Usage: $0 {open|close|status}"
    exit 1
    ;;
esac