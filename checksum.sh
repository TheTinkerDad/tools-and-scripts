#!/bin/bash

function log() {
  printf -v LOGDATE '%(%Y-%m-%d %H:%M:%S)T' -1
  echo -e "$LOGDATE $1"
}

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

rm failed_files.log >/dev/null 2>&1

# Parse arguments
for arg in "$@"; do
  case "$arg" in
    -c|--check)
      MODE="check"
      ;;
    --force)
      FORCE=true
      ;;
    *)
      echo -e "Unknown option: $arg"
      echo "Usage: $0 [-c|--check] [--force]"
      exit 1
      ;;
  esac
done

log "${YELLOW}===== Checksum script running in '$MODE' mode using SHA-256 =====${NC}"

# Loop through all regular files (excluding .sha256 files)
while IFS= read -r FILE; do
  SHA256FILE="${FILE}.sha256"
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
      log "${YELLOW}⚠ ${NC} No checksum file found for ${FILE}."
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
done < <(find . -maxdepth 1 -type f ! -name "*.sha256")

# 🧾 Summary Report
log "\n${YELLOW}===== Summary =====${NC}"
log "Total files processed: ${TOTAL}"

if [[ "$MODE" == "check" ]]; then
  log "${GREEN}✔${NC} Verified OK: ${VERIFIED_OK}"
  log "${RED}✘${NC} Verification failed or missing: ${VERIFIED_FAIL}"
else
  log "${GREEN}✔ Checksums created: ${CREATED}${NC}"
  log "${YELLOW}⚠ Skipped (already exists): ${SKIPPED}${NC}"
fi
