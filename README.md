<p align="center">
  <img src="docs/public/jetson-nvme-llm.svg" width="132" alt="Jetson NVMe LLM icon">
</p>

<h1 align="center">Jetson Orin Nano Super NVMe Boot Fix</h1>

<p align="center">
  Reproducible notes for booting a Jetson Orin Nano Super 8GB from NVMe without a microSD card, then running a Gemma 4-class local LLM with Ollama.
</p>

<p align="center">
  <a href="https://github.com/Sunwood-ai-labs/jetson-orin-nano-super-nvme-fix/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/Sunwood-ai-labs/jetson-orin-nano-super-nvme-fix/actions/workflows/ci.yml/badge.svg"></a>
  <a href="https://github.com/Sunwood-ai-labs/jetson-orin-nano-super-nvme-fix/actions/workflows/pages.yml"><img alt="Pages" src="https://github.com/Sunwood-ai-labs/jetson-orin-nano-super-nvme-fix/actions/workflows/pages.yml/badge.svg"></a>
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-green.svg"></a>
</p>

<p align="center">
  <a href="README.ja.md">日本語 README</a> ·
  <a href="https://sunwood-ai-labs.github.io/jetson-orin-nano-super-nvme-fix/">Documentation</a> ·
  <a href="docs/ja/article.md">Japanese article</a>
</p>

> [!WARNING]
> This is not NVIDIA's official NVMe flashing path. The official path is to use an Ubuntu host with the Jetson in Recovery Mode and flash with SDK Manager or Linux for Tegra tools such as `l4t_initrd_flash.sh`. This repository documents an experimental recovery flow: write the Jetson Orin Nano SD-card image to an NVMe SSD, then patch the Linux root-device setting so the image boots from NVMe.

## ✨ What This Repository Contains

- A reproducible field guide for the `mmcblk0p1 not found` boot failure
- The exact `extlinux.conf` root-device change used in this experiment
- Safety notes for destructive `dd` writes on macOS
- Scripts for inspecting and patching `extlinux.conf` inside an ext4 APP image
- Local LLM experiment notes for Ollama + Gemma 4-class models on Jetson Orin Nano Super 8GB
- GitHub Pages documentation and CI checks for scripts, docs, and accidental large-file commits

## 🧭 The Core Fix

The boot failure happened because the image still pointed Linux at a microSD-card root filesystem:

```diff
- root=/dev/mmcblk0p1
+ root=/dev/nvme0n1p1
```

The edited file is:

```text
/boot/extlinux/extlinux.conf
```

Evidence:

- [logs/extlinux-before.conf](logs/extlinux-before.conf)
- [logs/extlinux-after.conf](logs/extlinux-after.conf)

## 💿 OS Image Source

The experiment used NVIDIA's Jetson Orin Nano Developer Kit SD-card image.

- NVIDIA getting started guide: https://developer.nvidia.com/embedded/learn/get-started-jetson-orin-nano-devkit
- NVIDIA software setup guide: https://developer.nvidia.com/embedded/learn/jetson-orin-nano-devkit-user-guide/software_setup.html
- Downloaded file name: `jp62-r1-orin-nano-sd-card-image.zip`
- Image inside the ZIP: `sd-blob.img`

NVIDIA normally expects this image to be written to a microSD card. For a production-quality NVMe installation, use NVIDIA's official SDK Manager / Linux for Tegra flashing workflow instead.

## ⚡ Quick Reproduction Outline

Replace `/dev/disk5` and `/dev/disk5s1` with the disk identifiers from your own machine.

1. Confirm the external NVMe disk on macOS:

   ```sh
   diskutil list
   ```

2. Write the SD-card image to the NVMe SSD:

   ```sh
   unzip -p ~/Downloads/jp62-r1-orin-nano-sd-card-image.zip sd-blob.img | sudo dd of=/dev/rdisk5 bs=4m status=progress
   sync
   diskutil eject /dev/disk5
   ```

3. If the Jetson stops with `ERROR: mmcblk0p1 not found`, reconnect the NVMe SSD to macOS and copy the APP partition:

   ```sh
   mkdir -p ~/Prj/jetson-orin-nano-super-nvme-fix/{work,logs}
   sudo dd if=/dev/rdisk5s1 of=~/Prj/jetson-orin-nano-super-nvme-fix/work/app.img bs=4m status=progress
   ```

4. Patch the APP image from a Linux environment with `debugfs`:

   ```sh
   apt update
   apt install -y e2fsprogs
   ./scripts/patch-extlinux-root.sh work/app.img
   ```

5. Write the patched APP image back:

   ```sh
   sudo dd if=~/Prj/jetson-orin-nano-super-nvme-fix/work/app.img of=/dev/rdisk5s1 bs=4m status=progress
   sync
   diskutil eject /dev/disk5
   ```

Full steps are in the [documentation site](https://sunwood-ai-labs.github.io/jetson-orin-nano-super-nvme-fix/) and [Japanese article](docs/ja/article.md).

## 🧠 Local LLM Result

Ollama detected the Jetson Orin CUDA backend and could run the Q4 quantized Gemma 4-class model.

| Model | URL | Result |
| --- | --- | --- |
| `gemma4:e2b` | https://ollama.com/library/gemma4:e2b | Pull succeeded, generation hit OOM on 8GB |
| `batiai/gemma4-e2b:q4` | https://ollama.com/batiai/gemma4-e2b | Worked with GPU offload |

Observed smoke-test result:

```text
Konnichiwa.
eval_count: 205
tokens_per_sec: 21.81
```

Run the smoke test:

```sh
./llm-experiment/run-gemma4-q4-smoke-test.sh
```

More details: [llm-experiment/README.md](llm-experiment/README.md)

## 🗂️ Repository Layout

```text
.
├── README.md
├── README.ja.md
├── docs/
│   ├── .vitepress/
│   ├── guide/
│   ├── ja/
│   └── public/
├── llm-experiment/
├── logs/
├── scripts/
└── .github/workflows/
```

`work/app.img`, downloaded OS archives, and other bulky local artifacts are intentionally ignored by Git.

## ✅ Verification

Local checks:

```sh
npm install
npm run check
```

CI checks:

- shell syntax for repository scripts
- no tracked files larger than 5 MiB
- VitePress documentation build

## 📄 License

MIT
