#!/usr/bin/env bash
set -euo pipefail

limit_bytes="${LARGE_FILE_LIMIT_BYTES:-5242880}"
failed=0

while IFS= read -r path; do
  size="$(wc -c < "$path" | tr -d ' ')"
  if (( size > limit_bytes )); then
    printf 'large file tracked: %s (%s bytes)\n' "$path" "$size" >&2
    failed=1
  fi
done < <(git ls-files)

if (( failed != 0 )); then
  exit 1
fi

echo "No tracked files exceed ${limit_bytes} bytes."
