# NVMe Boot Repair

## What Failed

After writing the NVIDIA Jetson Orin Nano SD-card image to an M.2 NVMe SSD, the Jetson stopped during boot with:

```text
Root device found: mmcblk0p1
ERROR: mmcblk0p1 not found
```

The image was still configured to look for the root filesystem on a microSD device.

## What Was Changed

The file inside the APP partition was:

```text
/boot/extlinux/extlinux.conf
```

The root-device argument was changed:

```diff
- root=/dev/mmcblk0p1
+ root=/dev/nvme0n1p1
```

Evidence:

- [Before](../../logs/extlinux-before.conf)
- [After](../../logs/extlinux-after.conf)

## Mac + Docker Repair Flow

Replace `/dev/disk5` and `/dev/disk5s1` with the correct identifiers from your own `diskutil list`.

```sh
diskutil list
sudo dd if=/dev/rdisk5s1 of=work/app.img bs=4m status=progress
```

Use a Linux environment with `debugfs`:

```sh
docker run --rm -it \
  -v "$PWD/work:/work" \
  ubuntu:24.04 bash
```

Inside the container:

```sh
apt update
apt install -y e2fsprogs
```

Inspect:

```sh
debugfs -R "cat /boot/extlinux/extlinux.conf" /work/app.img
```

Patch:

```sh
debugfs -R "cat /boot/extlinux/extlinux.conf" /work/app.img > /work/extlinux.conf
sed -i 's#root=/dev/mmcblk0p1#root=/dev/nvme0n1p1#g' /work/extlinux.conf

cat > /work/debugfs.cmd <<'EOF'
rm /boot/extlinux/extlinux.conf
write /work/extlinux.conf /boot/extlinux/extlinux.conf
EOF

debugfs -w -f /work/debugfs.cmd /work/app.img
```

Write the patched APP image back:

```sh
sudo dd if=work/app.img of=/dev/rdisk5s1 bs=4m status=progress
sync
diskutil eject /dev/disk5
```

## Helper Scripts

The repository includes scripts for Linux environments:

```sh
./scripts/inspect-extlinux.sh work/app.img
./scripts/patch-extlinux-root.sh work/app.img
```
