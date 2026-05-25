# Jetson Orin Nano Super 8GBをSDカードなしでNVMe起動し、Gemma 4系ローカルLLMまで動かした記録

Jetson Orin Nano Super 8GBにM.2 NVMe SSDを挿し、SDカードを使わずにOS起動し、その上でOllamaとGemma 4系ローカルLLMを動かすところまで試しました。

最終的には、NVMe起動、SSH接続、`jtop`導入、Ollama導入、Gemma 4系Q4量子化モデルの推論まで成功しました。

再現用の手順・ログ・スクリプトはGitHubにまとめています。

https://github.com/Sunwood-ai-labs/jetson-orin-nano-super-nvme-fix

## 今回のゴール

やりたかったことはシンプルです。

- Jetson Orin Nano Super 8GBをM.2 NVMe SSDから起動する
- SDカードは使わない
- MacにM.2 SSDを接続して作業する
- 起動後はSSHで操作できるようにする
- Jetson上でローカルLLMを動かす

ただし、最初からきれいに成功したわけではありません。

## 使ったもの

- Jetson Orin Nano Super 8GB
- M.2 NVMe SSD 512GB
- macOS
- 外付けM.2 SSDケース
- Docker Desktop
- NVIDIA Jetson Orin Nano Developer Kit SDカードイメージ
- Ollama
- Gemma 4系モデル

## OSイメージはどこから取ったか

OSイメージはNVIDIA公式のJetson Orin Nano Developer Kit Getting Started Guideから取得しました。

公式手順:

https://developer.nvidia.com/embedded/learn/get-started-jetson-orin-nano-devkit

Software setup:

https://developer.nvidia.com/embedded/learn/jetson-orin-nano-devkit-user-guide/software_setup.html

今回使ったファイル名は以下です。

```text
jp62-r1-orin-nano-sd-card-image.zip
```

ZIPの中には以下のイメージが入っています。

```text
sd-blob.img
```

NVIDIA公式の通常手順では、このイメージはmicroSDカードへ書き込む想定です。

NVMe SSDを正式なプライマリストレージとしてフラッシュするなら、UbuntuホストでJetsonをRecovery Modeに入れ、SDK ManagerまたはLinux for Tegraの`l4t_initrd_flash.sh`を使うのが正攻法です。

今回の方法は、SDカード用イメージをM.2 SSDへ書き込み、起動設定のrootデバイス指定を修正して起動させる実験的な手順です。

## M.2 SSDへOSイメージを書き込む

MacにM.2 SSDを接続し、まずディスク番号を確認します。

```sh
diskutil list
```

今回の環境では、外付けM.2 SSDは以下でした。

```text
/dev/disk5
```

ここは非常に危険です。自分の環境で必ず確認してください。`dd`の書き込み先を間違えると、別のディスクを破壊します。

ZIPの中にある`sd-blob.img`をM.2 SSDへ書き込みます。

```sh
unzip -p ~/Downloads/jp62-r1-orin-nano-sd-card-image.zip sd-blob.img | sudo dd of=/dev/rdisk5 bs=4m status=progress
sync
diskutil eject /dev/disk5
```

このM.2 SSDをJetsonへ戻して起動しました。

## 最初の起動失敗

起動すると途中で止まりました。

画面には以下のようなエラーが出ました。

```text
Root device found: mmcblk0p1
ERROR: mmcblk0p1 not found
```

原因は、Linuxカーネルの起動パラメータがmicroSDカードをrootfsとして探していたことです。

問題の指定はこれです。

```text
root=/dev/mmcblk0p1
```

`mmcblk0p1`はmicroSDカード側のデバイス名です。  
今回はSDカードを使わず、M.2 NVMe SSDから起動したいので、rootfsは通常以下になります。

```text
/dev/nvme0n1p1
```

つまり、OS本体はM.2 SSDに入っているのに、起動設定だけが「microSDカードを探せ」と言っていた状態でした。

## 具体的に何を修正したか

修正したのはJetsonのLinux起動設定ファイルです。

```text
/boot/extlinux/extlinux.conf
```

変更前:

```text
root=/dev/mmcblk0p1
```

変更後:

```text
root=/dev/nvme0n1p1
```

つまり「起動先をNVMe側に修正した」とは、具体的には`/boot/extlinux/extlinux.conf`内の`root=`指定を、microSDカードからNVMe SSDへ変更したという意味です。

実際の修正前後ログはリポジトリに残しています。

- https://github.com/Sunwood-ai-labs/jetson-orin-nano-super-nvme-fix/blob/main/logs/extlinux-before.conf
- https://github.com/Sunwood-ai-labs/jetson-orin-nano-super-nvme-fix/blob/main/logs/extlinux-after.conf

## Mac上でextlinux.confを修正する

macOS標準ではext4パーティションを書き換えられません。そこで今回は、M.2 SSDのAPPパーティションをイメージファイルとして吸い出し、Docker上のUbuntuで`debugfs`を使って修正しました。

作業用フォルダを作ります。

```sh
mkdir -p ~/Prj/jetson-orin-nano-super-nvme-fix/{downloads,work,logs}
```

APPパーティションを確認します。

```sh
diskutil list /dev/disk5
```

今回のAPPパーティションは以下でした。

```text
/dev/disk5s1
```

APPパーティションをファイルへ吸い出します。

```sh
sudo dd if=/dev/rdisk5s1 of=~/Prj/jetson-orin-nano-super-nvme-fix/work/app.img bs=4m status=progress
```

DockerでUbuntuを起動します。

```sh
docker run --rm -it \
  -v ~/Prj/jetson-orin-nano-super-nvme-fix/work:/work \
  ubuntu:24.04 bash
```

コンテナ内で`debugfs`を使います。

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

修正済みAPPイメージをM.2 SSDへ書き戻します。

```sh
sudo dd if=~/Prj/jetson-orin-nano-super-nvme-fix/work/app.img of=/dev/rdisk5s1 bs=4m status=progress
sync
diskutil eject /dev/disk5
```

これでM.2 SSDをJetsonへ戻すと、NVMe rootで起動しました。

## SSHとjtop

起動後、SSHキーを登録して、Macから以下で入れるようにしました。

```sh
ssh jetson-orin
```

状態監視用には`jtop`を導入しました。

```sh
sudo apt update
sudo apt install -y python3-pip
sudo pip3 install -U jetson-stats
sudo systemctl restart jtop.service
jtop
```

## Ollamaを導入する

ローカルLLM実行環境としてOllamaを入れました。

```sh
curl -fsSL https://ollama.com/install.sh -o /tmp/ollama-install.sh
sudo sh /tmp/ollama-install.sh
ollama --version
```

今回入ったバージョンは以下です。

```text
ollama version is 0.24.0
```

OllamaはJetson上のCUDA / Orin GPUを認識しました。

ログでは以下を確認しています。

```text
CUDA
Orin
compute capability 8.7
```

## Gemma 4公式モデルを試す

まず公式のGemma 4 E2Bを試しました。

モデルURL:

https://ollama.com/library/gemma4:e2b

```sh
ollama pull gemma4:e2b
```

モデル自体は取得できました。

```text
gemma4:e2b
SIZE: 7.2 GB
```

しかし推論時に落ちました。

```sh
journalctl -u ollama --no-pager -n 100
```

ログには以下が出ました。

```text
ollama.service: A process of this unit has been killed by the OOM killer.
```

つまり、公式`gemma4:e2b`はJetson Orin Nano Super 8GBには重すぎました。

## Q4量子化版で成功

次にQ4量子化版を試しました。

モデルURL:

https://ollama.com/batiai/gemma4-e2b

```sh
ollama pull batiai/gemma4-e2b:q4
ollama run batiai/gemma4-e2b:q4
```

サイズは約3.4GBです。

```text
batiai/gemma4-e2b:q4
SIZE: 3.4 GB
```

`ollama ps`で確認すると、GPUで動いていました。

```text
NAME                    PROCESSOR    CONTEXT
batiai/gemma4-e2b:q4    100% GPU     1024
```

API経由のスモークテストも通りました。

```text
Konnichiwa.
eval_count: 205
tokens_per_sec: 21.81
```

Jetson Orin Nano Super 8GB上で、Gemma 4系Q4量子化モデルがローカルLLMとして動きました。

## 分かったこと

今回の大きなポイントは、「モデルをpullできる」と「実際に推論できる」は別物ということです。

公式の`gemma4:e2b`は取得できます。  
しかし8GB環境ではロード時にメモリが足りず、OOMで落ちました。

一方で、Q4量子化された`batiai/gemma4-e2b:q4`は、Jetson上のGPUを使って実用的に動きました。

## まとめ

今回できたことは以下です。

- NVIDIA公式SDカードイメージをM.2 SSDへ書き込み
- 起動設定`/boot/extlinux/extlinux.conf`を修正
- `root=/dev/mmcblk0p1`から`root=/dev/nvme0n1p1`へ変更
- SDカードなしでNVMe起動
- SSHキー設定
- `jtop`導入
- Ollama導入
- CUDA / Orin GPU認識確認
- 公式`gemma4:e2b`のOOM確認
- Q4量子化版`batiai/gemma4-e2b:q4`の推論成功
- 約21.8 tokens/secを確認

Jetson Orin Nano Super 8GBでも、モデル選定を間違えなければローカルLLMは動きます。

次は、カメラ入力、センサー情報、ローカルエージェント化あたりを試したいです。Jetson単体でネットに依存しない小型AIノードを作る土台として、かなり面白い結果でした。

## 参考リンク

- NVIDIA Jetson Orin Nano Developer Kit Getting Started Guide: https://developer.nvidia.com/embedded/learn/get-started-jetson-orin-nano-devkit
- NVIDIA Jetson Orin Nano Developer Kit User Guide - Software Setup: https://developer.nvidia.com/embedded/learn/jetson-orin-nano-devkit-user-guide/software_setup.html
- Ollama Gemma 4: https://ollama.com/library/gemma4
- Ollama Gemma 4 E2B: https://ollama.com/library/gemma4:e2b
- 今回動いたQ4量子化版: https://ollama.com/batiai/gemma4-e2b
- 再現リポジトリ: https://github.com/Sunwood-ai-labs/jetson-orin-nano-super-nvme-fix
