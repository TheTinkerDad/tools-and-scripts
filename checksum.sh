#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default mode and flags
MODE="create"
FORCE=false

# Counters
TOTAL=0
VERIFIED_OK=0
VERIFIED_FAIL=0
SKIPPED=0
CREATED=0

function log() {
  printf -v LOGDATE '%(%Y-%m-%d %H:%M:%S)T' -1
  echo -e "$LOGDATE $1"
}

function process_file() {
  local FILE="$1"
  local SHA256FILE="${FILE}.sha256"
  ((TOTAL++))

  if [[ "$MODE" == "check" ]]; then
    if [[ -f "$SHA256FILE" ]]; then
      log "Checking ${FILE} against ${SHA256FILE}..."
      if sha256sum -c "$SHA256FILE" &>/dev/null; then
        log "${GREEN}✔${NC} ${FILE} is valid."
        ((VERIFIED_OK++))
      else
        log "${RED}✘${NC} ${FILE} FAILED checksum verification!"
        ((VERIFIED_FAIL++))
        echo "${FILE}" >>failed_files.log
      fi
    else
      log "${YELLOW}⚠${NC} No checksum file found for ${FILE}."
      ((VERIFIED_FAIL++))
    fi
  else
    if [[ -f "$SHA256FILE" && "$FORCE" == false ]]; then
      log "${YELLOW}⚠${NC} Checksum file already exists for ${FILE}. Skipping..."
      ((SKIPPED++))
    else
      log "${YELLOW}Creating checksum for ${FILE}...${NC}"
      sha256sum "$FILE" > "$SHA256FILE"
      log "${GREEN}✔${NC} Saved to ${SHA256FILE}."
      ((CREATED++))
    fi
  fi
}

rm failed_files.log >/dev/null 2>&1

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--check)
      MODE="check"
      shift
      ;;
    --force)
      FORCE=true
      shift
      ;;
    --file)
      TARGET_FILE="$2"
      shift 2
      ;;
    *)
      echo -e "Unknown option: $1"
      echo "Usage: $0 [-c|--check] [--force] [--file <filename>]"
      exit 1
      ;;
  esac
done

log "${YELLOW}===== Checksum script running in '$MODE' mode using SHA-256 =====${NC}"

if [[ -n "$TARGET_FILE" ]]; then
  if [[ ! -f "$TARGET_FILE" ]]; then
    log "${RED}✘${NC} Specified file '$TARGET_FILE' does not exist."
    exit 1
  fi
  process_file "$TARGET_FILE"
else
  # Loop through all regular files (excluding .sha256 files)
  while IFS= read -r FILE; do
    process_file $FILE
  done < <(find . -maxdepth 1 -type f ! -name "*.sha256")
fi

# 🧾 Summary Report
log "${YELLOW}===== Summary =====${NC}"
log "Total files processed: ${TOTAL}"

if [[ "$MODE" == "check" ]]; then
  log "${GREEN}✔${NC} Verified OK: ${VERIFIED_OK}"
  log "${RED}✘${NC} Verification failed or missing: ${VERIFIED_FAIL}"
else
  log "${GREEN}✔ Checksums created: ${CREATED}${NC}"
  log "${YELLOW}⚠ Skipped (already exists): ${SKIPPED}${NC}"
fi
