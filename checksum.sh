#!/bin/bash

for FILE in *; do
  if [[ $FILE == *sha ]]; then
    echo  >/dev/null
  else
    SHA1FILE="${FILE}.sha"
    if [ -f "$SHA1FILE" ]; then
      if [ "$1" = "-c" ]; then
        echo Checking $FILE against $SHA1FILE...
        sha1sum -c $SHA1FILE
      fi
    else
      echo Creating checksum for $FILE...
      sha1sum $FILE >$SHA1FILE
    fi
  fi
done
