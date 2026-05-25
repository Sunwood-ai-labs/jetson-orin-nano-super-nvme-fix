# 概要

Jetson Orin Nano Super 8GBをSDカードなしでNVMe起動し、Ollama + Gemma 4系Q4量子化モデルを動かした実験記録です。

## このリポジトリの要点

- NVIDIA公式SDカードイメージをM.2 NVMe SSDへ書き込んだ
- 起動時に `ERROR: mmcblk0p1 not found` で停止した
- `/boot/extlinux/extlinux.conf` の `root=` を修正した
- NVMe rootで起動した
- OllamaでGemma 4系Q4モデルの推論に成功した

## 修正内容

```diff
- root=/dev/mmcblk0p1
+ root=/dev/nvme0n1p1
```

詳しい記事は [記事ページ](./article.md) を参照してください。
