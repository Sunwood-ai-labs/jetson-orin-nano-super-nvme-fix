# Jetson Orin Nano Super NVMe Boot Fix

SDカードなしで Jetson Orin Nano Super 8GB を NVMe SSD から起動し、その上で Ollama + Gemma 4 系ローカルLLMを動かした実験記録です。

> [!WARNING]
> これは NVIDIA 公式の NVMe フラッシュ手順そのものではありません。公式の正攻法は Ubuntu ホストで Jetson を Recovery Mode に入れ、SDK Manager または Linux for Tegra の `l4t_initrd_flash.sh` を使う方法です。このリポジトリは「SDカードイメージを NVMe SSD に書き込んだあと、root デバイス指定だけを修正して起動させた」実験的な復旧手順を記録します。

## 何を修正したか

起動できなかった原因は、Jetson の Linux 起動設定が microSD カードを rootfs として探していたことです。

修正したファイル:

```text
/boot/extlinux/extlinux.conf
```

変更内容:

```diff
- root=/dev/mmcblk0p1
+ root=/dev/nvme0n1p1
```

`/dev/mmcblk0p1` は microSD カード側のデバイス名です。今回は SD カードを使わず、M.2 NVMe SSD の root パーティションから起動したかったため、`/dev/nvme0n1p1` に変更しました。

実際の差分証跡:

- [logs/extlinux-before.conf](logs/extlinux-before.conf)
- [logs/extlinux-after.conf](logs/extlinux-after.conf)

## 使ったOSイメージ

NVIDIA 公式の Jetson Orin Nano Developer Kit Getting Started Guide から SD カードイメージを取得しました。

- 公式手順: https://developer.nvidia.com/embedded/learn/get-started-jetson-orin-nano-devkit
- Software setup: https://developer.nvidia.com/embedded/learn/jetson-orin-nano-devkit-user-guide/software_setup.html
- 使用ファイル名: `jp62-r1-orin-nano-sd-card-image.zip`
- ZIP内のイメージ: `sd-blob.img`

NVIDIA の通常手順では、このイメージは microSD カードへ書き込む想定です。NVMe を正式なプライマリストレージとして使う場合は、SDK Manager / `l4t_initrd_flash.sh` を使う方が正攻法です。

## 再現手順

### 1. M.2 SSDをMacに接続してディスク番号を確認

```sh
diskutil list
```

今回の実験では外付けM.2 SSDが `/dev/disk5` でした。

> [!CAUTION]
> `dd` の書き込み先を間違えると別ディスクを破壊します。以降の `/dev/disk5` は必ず自分の環境のディスク番号に置き換えてください。

### 2. SDカードイメージをM.2 SSDへ書き込む

```sh
unzip -p ~/Downloads/jp62-r1-orin-nano-sd-card-image.zip sd-blob.img | sudo dd of=/dev/rdisk5 bs=4m status=progress
sync
diskutil eject /dev/disk5
```

### 3. Jetsonに戻して起動し、失敗内容を確認

この状態では、環境によって以下のように止まります。

```text
Root device found: mmcblk0p1
ERROR: mmcblk0p1 not found
```

これは `/boot/extlinux/extlinux.conf` の `root=/dev/mmcblk0p1` が原因です。

### 4. M.2 SSDを再度Macに接続し、APPパーティションを吸い出す

```sh
mkdir -p ~/Prj/jetson-orin-nano-super-nvme-fix/{downloads,work,logs}
diskutil list /dev/disk5
sudo dd if=/dev/rdisk5s1 of=~/Prj/jetson-orin-nano-super-nvme-fix/work/app.img bs=4m status=progress
```

今回のAPPパーティションは `/dev/disk5s1` でした。実際のパーティション一覧は [logs/diskutil-before-fix.txt](logs/diskutil-before-fix.txt) に残しています。

### 5. Docker上のLinuxでext4イメージを編集

macOS標準ではext4を書き換えられないため、Ubuntuコンテナで `debugfs` を使いました。

```sh
docker run --rm -it \
  -v ~/Prj/jetson-orin-nano-super-nvme-fix/work:/work \
  ubuntu:24.04 bash
```

コンテナ内:

```sh
apt update
apt install -y e2fsprogs

debugfs -R "cat /boot/extlinux/extlinux.conf" /work/app.img > /work/extlinux.conf
sed -i 's#root=/dev/mmcblk0p1#root=/dev/nvme0n1p1#g' /work/extlinux.conf

cat > /work/debugfs.cmd <<'EOF'
rm /boot/extlinux/extlinux.conf
write /work/extlinux.conf /boot/extlinux/extlinux.conf
EOF

debugfs -w -f /work/debugfs.cmd /work/app.img
debugfs -R "cat /boot/extlinux/extlinux.conf" /work/app.img
exit
```

### 6. 修正済みAPPイメージをM.2 SSDへ書き戻す

```sh
sudo dd if=~/Prj/jetson-orin-nano-super-nvme-fix/work/app.img of=/dev/rdisk5s1 bs=4m status=progress
sync
diskutil eject /dev/disk5
```

これでM.2 SSDをJetsonへ戻すと、NVMe rootで起動しました。

## SSHとjtop

SSHキーを登録すると、Macから以下で入れます。

```sh
ssh jetson-orin
```

Jetsonの状態監視には `jtop` を入れました。

```sh
sudo apt update
sudo apt install -y python3-pip
sudo pip3 install -U jetson-stats
sudo systemctl restart jtop.service
jtop
```

## Ollama + Gemma 4実験

Ollamaをインストール:

```sh
curl -fsSL https://ollama.com/install.sh -o /tmp/ollama-install.sh
sudo sh /tmp/ollama-install.sh
ollama --version
```

今回の結果:

```text
ollama version is 0.24.0
```

### 公式 `gemma4:e2b`

- URL: https://ollama.com/library/gemma4:e2b
- サイズ: 7.2GB
- 結果: pull は成功、推論時に OOM kill

確認ログ:

```sh
journalctl -u ollama --no-pager -n 100
```

代表的なエラー:

```text
ollama.service: A process of this unit has been killed by the OOM killer.
```

### 動いたQ4量子化版

- URL: https://ollama.com/batiai/gemma4-e2b
- モデル: `batiai/gemma4-e2b:q4`
- サイズ: 3.4GB
- 結果: Jetson Orin Nano Super 8GB上で推論成功

```sh
ollama pull batiai/gemma4-e2b:q4
ollama run batiai/gemma4-e2b:q4
```

確認:

```sh
ollama ps
```

結果:

```text
NAME                    PROCESSOR    CONTEXT
batiai/gemma4-e2b:q4    100% GPU     1024
```

APIスモークテスト:

```sh
./llm-experiment/run-gemma4-q4-smoke-test.sh
```

実測:

```text
Konnichiwa.
eval_count: 205
tokens_per_sec: 21.81
```

詳細は [llm-experiment/README.md](llm-experiment/README.md) にまとめています。

## Bonsai系の軽量モデル追加実験

Gemma 4 Q4 のあと、さらに軽い Bonsai 系モデルも試しました。

- `eslider/bonsai-1.7b`: pull成功、ただし Jetson + Ollama 0.24.0 ではロード時に runner が落ちて実行不可
- `qwen3:0.6b`: pull成功、100% GPUで実行成功、API上のdecode速度は約52.8 tok/s

詳細ログ:

- [llm-experiment/bonsai-and-lightweight-models.md](llm-experiment/bonsai-and-lightweight-models.md)

## リポジトリ構成

```text
.
├── README.md
├── docs/
│   └── article-ja.md
├── llm-experiment/
│   ├── README.md
│   └── run-gemma4-q4-smoke-test.sh
├── logs/
│   ├── diskutil-before-fix.txt
│   ├── diskutil-after-fix.txt
│   ├── extlinux-before.conf
│   └── extlinux-after.conf
└── scripts/
    ├── inspect-extlinux.sh
    └── patch-extlinux-root.sh
```

`work/app.img` やダウンロード済みOSイメージは巨大ファイルなのでGit管理対象外です。

## まとめ

Jetson Orin Nano Super 8GBでも、NVMe起動環境を整え、軽量な量子化モデルを選べばローカルLLM実験ができます。

今回の重要ポイントは2つです。

1. SDカードイメージをNVMeへ書いた場合、`/boot/extlinux/extlinux.conf` の `root=` が microSD のままだと起動できない
2. 公式 `gemma4:e2b` は8GB機には重いが、`batiai/gemma4-e2b:q4` はGPUで動いた

## License

MIT
