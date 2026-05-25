#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/app.img" >&2
  exit 2
fi

app_img="$1"

if [[ ! -f "$app_img" ]]; then
  echo "APP image not found: $app_img" >&2
  exit 1
fi

if ! command -v debugfs >/dev/null 2>&1; then
  echo "debugfs is required. Install e2fsprogs first." >&2
  exit 1
fi

debugfs -R "cat /boot/extlinux/extlinux.conf" "$app_img"
