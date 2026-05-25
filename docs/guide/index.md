# Overview

This repository documents a Jetson Orin Nano Super 8GB experiment:

1. Write NVIDIA's Jetson Orin Nano Developer Kit SD-card image to an M.2 NVMe SSD.
2. Fix the boot failure caused by the image still pointing at a microSD root device.
3. Boot the Jetson from NVMe without a microSD card.
4. Install Ollama and test Gemma 4-class local LLM models.

## Important Scope

This is an experimental recovery path, not NVIDIA's official NVMe flashing workflow.

Use NVIDIA's official SDK Manager or Linux for Tegra flashing flow for production provisioning. This guide exists because the experiment started from a Mac, an external M.2 enclosure, and an already-written SD-card image.

## Key Result

The boot issue was fixed by editing:

```text
/boot/extlinux/extlinux.conf
```

and changing:

```diff
- root=/dev/mmcblk0p1
+ root=/dev/nvme0n1p1
```

The local LLM result was:

```text
batiai/gemma4-e2b:q4
PROCESSOR: 100% GPU
tokens_per_sec: 21.81
```

## Source Links

- NVIDIA getting started guide: https://developer.nvidia.com/embedded/learn/get-started-jetson-orin-nano-devkit
- NVIDIA software setup: https://developer.nvidia.com/embedded/learn/jetson-orin-nano-devkit-user-guide/software_setup.html
- Ollama Gemma 4 E2B: https://ollama.com/library/gemma4:e2b
- Working Q4 model: https://ollama.com/batiai/gemma4-e2b
