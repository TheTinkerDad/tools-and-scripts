#!/bin/bash

ARCHIVE_DIR="./archives"

# Create archive folder if it doesn't exist
mkdir -p "$ARCHIVE_DIR"

# Loop through all HD .mp4 files (excluding .4k.mp4)
find . -maxdepth 1 -type f -name "*.mp4" ! -name "*.4k.mp4" | while IFS= read -r HD_FILE; do

  # Strip leading ./ and extension
  BASENAME=$(basename "$HD_FILE" .mp4)

  # Construct expected 4K filename
  FOURK_FILE="./${BASENAME}.4k.mp4"

  if [[ -f "$FOURK_FILE" ]]; then
    echo " Archiving HD version: $HD_FILE"
    mv "$HD_FILE" "$ARCHIVE_DIR/"
  fi
done

echo " Done. HD files with 4K counterparts moved to $ARCHIVE_DIR"
