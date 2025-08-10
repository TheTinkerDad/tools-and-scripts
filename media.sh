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
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

VOLUME_FILE="./media.json"

# Function to log messages with timestamp
log() {
  printf -v LOGDATE '%(%Y-%m-%d %H:%M:%S)T' -1
  echo -e "$LOGDATE $1"
}

setup_environment() {
  log "Checking prerequisites..."

  # Detect package manager
  if command -v apt-get &>/dev/null; then
    PKG_MANAGER="apt-get"
    INSTALL_CMD="sudo apt-get install -y"
    UPDATE_CMD="sudo apt-get update"
    DISTRO="Debian/Ubuntu"
  elif command -v dnf &>/dev/null; then
    PKG_MANAGER="dnf"
    INSTALL_CMD="sudo dnf install -y"
    UPDATE_CMD="sudo dnf check-update"
    DISTRO="RHEL/Fedora"
  elif command -v yum &>/dev/null; then
    PKG_MANAGER="yum"
    INSTALL_CMD="sudo yum install -y"
    UPDATE_CMD="sudo yum check-update"
    DISTRO="RHEL/CentOS"
  else
    log "${RED}✘${NC} Unsupported Linux distribution. Cannot detect package manager."
    exit 1
  fi

  log "Detected $DISTRO system using $PKG_MANAGER"

  # Update package list
  log "Updating package list..."
  $UPDATE_CMD

  # Check and install cryptsetup
  if ! command -v cryptsetup &>/dev/null; then
    log "Installing cryptsetup..."
    $INSTALL_CMD cryptsetup
  else
    log "${GREEN}✔${NC} cryptsetup is already installed."
  fi

  # Check and install jq
  if ! command -v jq &>/dev/null; then
    log "Installing jq..."
    $INSTALL_CMD jq
  else
    log "${GREEN}✔${NC} jq is already installed."
  fi

  log "${GREEN}✔${NC} Setup complete."
}

create_volume_test() {
  PARTITION="$1"
  if [ -z "$PARTITION" ]; then
    log "${RED}✘${NC} No partition specified. Usage: $0 create-test /dev/sdXn"
    exit 1
  fi

  # Confirm partition exists
  if ! lsblk "$PARTITION" &>/dev/null; then
    log "${RED}✘${NC} Partition $PARTITION does not exist."
    exit 1
  fi

  # Check if already formatted
  if blkid "$PARTITION" | grep -q 'TYPE='; then
    log "${YELLOW}⚠${NC} Partition $PARTITION already has a filesystem."
  fi

  # Get UUID
  UUID=$(lsblk -no UUID "$PARTITION" | head -n1)
  if [ -z "$UUID" ]; then
    log "${RED}✘${NC} Failed to retrieve UUID from $PARTITION."
    exit 1
  fi

  # Determine next available mediaX name
  if [ ! -f "$VOLUME_FILE" ]; then
    echo '{}' > "$VOLUME_FILE"
  fi
  NEXT_ID=$(jq -r 'keys[] | select(startswith("media"))' "$VOLUME_FILE" | sed 's/media//' | sort -n | tail -1)
  NEXT_ID=$((NEXT_ID + 1))
  VOLUME="media$NEXT_ID"

  MOUNT_POINT="/media/$VOLUME"

  # Dry-run output
  echo "Dry-run: Here's what would happen:"
  echo " - Format $PARTITION with LUKS"
  echo " - Open LUKS volume /dev/disk/by-uuid/$UUID as $VOLUME"
  echo " - Create ext4 filesystem on /dev/mapper/$VOLUME"
  echo " - Create mount point at $MOUNT_POINT"
  echo " - Mount /dev/mapper/$VOLUME to $MOUNT_POINT"
  echo " - Update volumes.json with \"$VOLUME\": \"$UUID\""
}

create_volume() {
  PARTITION="$1"
  if [ -z "$PARTITION" ]; then
    log "${RED}✘${NC} No partition specified. Usage: $0 create /dev/sdXn"
    exit 1
  fi

  # Confirm partition exists
  if ! lsblk "$PARTITION" &>/dev/null; then
    log "${RED}✘${NC} Partition $PARTITION does not exist."
    exit 1
  fi

  # Confirm it's not already formatted
  if blkid "$PARTITION" | grep -q 'TYPE='; then
    log "${RED}✘${NC} Partition $PARTITION already has a filesystem. Aborting."
    exit 1
  fi

  # Format with LUKS
  log "Formatting $PARTITION with LUKS..."
  sudo cryptsetup luksFormat "$PARTITION"

  # Get UUID
  UUID=$(lsblk -no UUID "$PARTITION" | head -n1)
  if [ -z "$UUID" ]; then
    log "${RED}✘${NC} Failed to retrieve UUID from $PARTITION."
    exit 1
  fi

  # Determine next available mediaX name
  if [ ! -f "$VOLUME_FILE" ]; then
    echo '{}' > "$VOLUME_FILE"
  fi
  NEXT_ID=$(jq -r 'keys[] | select(startswith("media"))' "$VOLUME_FILE" | sed 's/media//' | sort -n | tail -1)
  NEXT_ID=$((NEXT_ID + 1))
  VOLUME="media$NEXT_ID"

  # Open LUKS volume
  log "Opening LUKS volume as $VOLUME..."
  sudo cryptsetup luksOpen "/dev/disk/by-uuid/$UUID" "$VOLUME"

  # Format with ext4
  log "Creating ext4 filesystem on /dev/mapper/$VOLUME..."
  sudo mkfs.ext4 "/dev/mapper/$VOLUME"

  # Create mount point
  MOUNT_POINT="/media/$VOLUME"
  log "Creating mount point at $MOUNT_POINT..."
  sudo mkdir -p "$MOUNT_POINT"

  # Mount the volume
  log "Mounting /dev/mapper/$VOLUME to $MOUNT_POINT..."
  sudo mount "/dev/mapper/$VOLUME" "$MOUNT_POINT"

  # Update volumes.json
  jq --arg vol "$VOLUME" --arg uuid "$UUID" '. + {($vol): $uuid}' "$VOLUME_FILE" > "${VOLUME_FILE}.tmp" && mv "${VOLUME_FILE}.tmp" "$VOLUME_FILE"

  log "${GREEN}✔${NC} Volume $VOLUME created and mounted at $MOUNT_POINT"
}

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

usage() {
  echo "Usage: $0 {open|close|status|setup|create|create-test}"
  exit 1
}

# Main logic
MODE="$1"
if [[ -z "$MODE" ]]; then
  usage
fi

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

case "$MODE" in
  open) open_volumes ;;
  close) close_volumes ;;
  status) status_volumes ;;
  setup) setup_environment ;;
  create-test) create_volume_test "$2" ;;
  *)
    echo "Invalid mode: $MODE"
    usage
    ;;
esac
