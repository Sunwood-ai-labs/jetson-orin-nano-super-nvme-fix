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

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

before="$tmpdir/extlinux-before.conf"
after="$tmpdir/extlinux-after.conf"
cmds="$tmpdir/debugfs.cmd"

debugfs -R "cat /boot/extlinux/extlinux.conf" "$app_img" > "$before"

if ! grep -q 'root=/dev/mmcblk0p1' "$before"; then
  echo "Expected root=/dev/mmcblk0p1 was not found. Current root setting:" >&2
  grep -o 'root=[^ ]*' "$before" >&2 || true
  exit 1
fi

sed 's#root=/dev/mmcblk0p1#root=/dev/nvme0n1p1#g' "$before" > "$after"

cat > "$cmds" <<EOF
rm /boot/extlinux/extlinux.conf
write $after /boot/extlinux/extlinux.conf
EOF

debugfs -w -f "$cmds" "$app_img"

echo "Patched /boot/extlinux/extlinux.conf:"
debugfs -R "cat /boot/extlinux/extlinux.conf" "$app_img" | grep 'root='
