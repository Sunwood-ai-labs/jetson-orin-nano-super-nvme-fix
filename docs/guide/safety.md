# Safety Notes

This project contains destructive disk commands. Read this page before copying commands.

## Disk Identifiers Are Examples

The experiment used:

```text
/dev/disk5
/dev/disk5s1
```

Those values are examples from one Mac. Always run:

```sh
diskutil list
```

and confirm the external NVMe SSD before using `dd`.

## `dd` Can Destroy Data

Commands such as:

```sh
sudo dd of=/dev/rdisk5 ...
sudo dd of=/dev/rdisk5s1 ...
```

overwrite disks or partitions. A wrong target can destroy your macOS install or another external drive.

## Keep Images Out of Git

The APP partition image is large and may contain device-specific state:

```text
work/app.img
```

It is intentionally ignored by Git. Do not publish it.

## Prefer Official Flashing for Production

This repository records an experiment. For production provisioning, use NVIDIA's official Ubuntu host + Recovery Mode flashing flow with SDK Manager or Linux for Tegra.
