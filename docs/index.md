---
layout: home

hero:
  name: Jetson Orin Nano Super NVMe Boot Fix
  text: Boot repair notes and local LLM proof on Jetson Orin Nano Super 8GB
  tagline: A reproducible field guide for patching an SD-card image that still points at microSD root, then running Ollama + Gemma 4-class Q4 on NVMe.
  image:
    src: /jetson-nvme-llm.svg
    alt: Jetson NVMe LLM icon
  actions:
    - theme: brand
      text: Start the Guide
      link: /guide/
    - theme: alt
      text: 日本語記事
      link: /ja/article
    - theme: alt
      text: GitHub
      link: https://github.com/Sunwood-ai-labs/jetson-orin-nano-super-nvme-fix

features:
  - title: NVMe boot repair
    details: Documents the exact extlinux.conf root-device change from /dev/mmcblk0p1 to /dev/nvme0n1p1.
  - title: Evidence first
    details: Includes before/after boot config logs, diskutil output, scripts, and local LLM runtime notes.
  - title: Local LLM result
    details: Records the Gemma 4 E2B OOM result and the Q4 model that ran with GPU offload.
---
