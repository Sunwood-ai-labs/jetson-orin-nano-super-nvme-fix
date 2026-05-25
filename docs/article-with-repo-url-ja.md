# Jetson Orin Nano Super 8GBをSDカードなしでNVMe起動し、Gemma 4系ローカルLLMまで動かした記録

了解。これは「再現記事」として書き直すなら、かなり重要な注意があります。

今回やったのは **NVIDIA公式のNVMeフラッシュ手順そのものではなく**、  
**Jetson Orin Nano用SDカードイメージをM.2 SSDへ書き込み、起動設定のrootデバイスだけNVMe向けに直す実験的手順** です。

公式にきれいにやるなら、Ubuntuホスト + Recovery Mode + SDK Manager / `l4t_initrd_flash.sh` が正攻法です。  
ただ今回は「SDカードなし」「Macに挿したM.2 SSDを使う」という条件だったので、この方法で復旧・起動しました。

再現用の手順・ログ・スクリプトは以下の公開リポジトリにまとめています。

https://github.com/Sunwood-ai-labs/jetson-orin-nano-super-nvme-fix

以下、記事完全版です。

---

Jetson Orin Nano Super 8GBにM.2 NVMe SSDを挿して、SDカードなしでOS起動し、その上でOllamaとGemma 4系ローカルLLMを動かすところまで試した。

最終的には、

✅ NVMe SSDからJetson起動  
✅ SSHキー設定  
✅ `jtop`導入  
✅ Ollama導入  
✅ Gemma 4系Q4量子化モデルの推論成功  

まで到達した。

再現用リポジトリはこちら。

https://github.com/Sunwood-ai-labs/jetson-orin-nano-super-nvme-fix

## 使ったもの

今回使った構成は以下。

- Jetson Orin Nano Super 8GB
- M.2 NVMe SSD 512GB
- macOS
- 外付けM.2 SSDケース
- JetPack 6系のJetson Orin Nano Developer Kit SDカードイメージ
- Ollama
- Gemma 4系モデル

## OSイメージの入手元

OSイメージはNVIDIA公式のJetson Orin Nano Developer Kit向けページから取得した。

公式手順ページ:

[Jetson Orin Nano Developer Kit Getting Started Guide](https://developer.nvidia.com/embedded/learn/get-started-jetson-orin-nano-devkit)

NVIDIAの手順では、Jetson Orin Nano Developer Kit用のSDカードイメージをダウンロードしてmicroSDカードへ書き込む流れになっている。

今回使ったファイル名はこれ。

```text
jp62-r1-orin-nano-sd-card-image.zip
```

中身は以下のイメージファイル。

```text
sd-blob.img
```

NVIDIA公式ドキュメント上も、通常はこのSDカードイメージをmicroSDカードへ書き込む想定になっている。  
また、NVMeやUSBなどを正式なプライマリストレージとして使う場合は、SDK Managerを使うオプション手順が案内されている。

参考:

[NVIDIA Jetson Orin Nano Developer Kit User Guide - Software Setup](https://developer.nvidia.com/embedded/learn/jetson-orin-nano-devkit-user-guide/software_setup.html)

## 重要な注意

今回の方法は、公式の「NVMeへ正規フラッシュする手順」ではない。

公式の正攻法は、UbuntuホストPCでJetsonをRecovery Modeに入れて、SDK ManagerまたはLinux for Tegraのフラッシュツールを使う方法。

今回は、

- SDカードを使わない
- すでにM.2 SSDをMacに挿せる
- まず起動する状態まで持っていきたい

という条件だったので、SDカード用イメージをM.2 SSDに書き込み、起動設定だけ修正する方法を取った。

この作業で使った再現用ログと補助スクリプトは以下に置いている。

https://github.com/Sunwood-ai-labs/jetson-orin-nano-super-nvme-fix

## M.2 SSDへOSイメージを書き込む

MacにM.2 SSDを接続し、ディスク番号を確認する。

```sh
diskutil list
```

今回の環境では、外付けM.2 SSDは以下だった。

```text
/dev/disk5
```

危険なので、ここは必ず自分の環境で確認すること。  
間違えるとMac本体や別ディスクを破壊する。

ZIPの中にある `sd-blob.img` をM.2 SSDへ書き込む。

例:

```sh
unzip -p ~/Downloads/jp62-r1-orin-nano-sd-card-image.zip sd-blob.img | sudo dd of=/dev/rdisk5 bs=4m status=progress
sync
diskutil eject /dev/disk5
```

これでM.2 SSDにはJetson Orin Nano用のOSイメージが書き込まれる。

## 最初の起動失敗

M.2 SSDをJetsonに戻して起動すると、途中で止まった。

画面には以下のようなエラーが出た。

```text
Root device found: mmcblk0p1
ERROR: mmcblk0p1 not found
```

これは何が起きているかというと、Linuxカーネルの起動パラメータが、

```text
root=/dev/mmcblk0p1
```

になっていた。

`mmcblk0p1` はmicroSDカード側のデバイス名。  
しかし今回はSDカードを使わず、M.2 NVMe SSDから起動したい。

NVMe SSDの場合、rootパーティションは通常こう見える。

```text
/dev/nvme0n1p1
```

つまり、OS本体はM.2 SSDに入っているのに、起動設定だけが「microSDカードを探せ」と言っていた。  
そのため、起動途中でrootfsを見つけられずに止まっていた。

## 修正したファイル

修正したのは、JetsonのLinux起動設定ファイル。

```text
/boot/extlinux/extlinux.conf
```

このファイルは、JetsonのAPPパーティション内にある。

変更前は、起動オプションに以下が含まれていた。

```text
root=/dev/mmcblk0p1
```

これを以下へ変更した。

```text
root=/dev/nvme0n1p1
```

つまり「起動先をNVMe側に修正した」とは、具体的には、

```text
/boot/extlinux/extlinux.conf
```

内の `root=` 指定を、

```text
/dev/mmcblk0p1
```

から

```text
/dev/nvme0n1p1
```

へ変更した、という意味。

修正前後の実ファイルログはこちら。

- https://github.com/Sunwood-ai-labs/jetson-orin-nano-super-nvme-fix/blob/main/logs/extlinux-before.conf
- https://github.com/Sunwood-ai-labs/jetson-orin-nano-super-nvme-fix/blob/main/logs/extlinux-after.conf

## Mac上でextlinux.confを修正する方法

macOSは標準ではext4を書き換えられない。  
そのため、今回はM.2 SSDのAPPパーティションをイメージファイルとして吸い出し、Linux環境で中身を修正した。

作業用フォルダを作る。

```sh
mkdir -p ~/Prj/jetson-orin-nano-super-nvme-fix/{downloads,work,logs}
```

APPパーティションを確認する。

```sh
diskutil list /dev/disk5
```

JetsonイメージのAPPパーティションは通常、最初の大きなLinuxパーティションになっている。  
今回の環境では以下だった。

```text
/dev/disk5s1
```

APPパーティションをファイルに吸い出す。

```sh
sudo dd if=/dev/rdisk5s1 of=~/Prj/jetson-orin-nano-super-nvme-fix/work/app.img bs=4m status=progress
```

DockerでLinux環境を使い、`debugfs` でext4イメージ内のファイルを読む。

```sh
docker run --rm -it \
  -v ~/Prj/jetson-orin-nano-super-nvme-fix/work:/work \
  ubuntu:24.04 bash
```

コンテナ内で必要なツールを入れる。

```sh
apt update
apt install -y e2fsprogs
```

変更前の設定を確認する。

```sh
debugfs -R "cat /boot/extlinux/extlinux.conf" /work/app.img
```

ここで以下のように出る。

```text
APPEND ${cbootargs} root=/dev/mmcblk0p1 ...
```

修正版の `extlinux.conf` を作る。

```sh
debugfs -R "cat /boot/extlinux/extlinux.conf" /work/app.img > /work/extlinux.conf
sed -i 's#root=/dev/mmcblk0p1#root=/dev/nvme0n1p1#g' /work/extlinux.conf
```

`debugfs` で元ファイルを差し替える。

```sh
cat > /work/debugfs.cmd <<'EOF'
rm /boot/extlinux/extlinux.conf
write /work/extlinux.conf /boot/extlinux/extlinux.conf
EOF

debugfs -w -f /work/debugfs.cmd /work/app.img
```

修正後を確認する。

```sh
debugfs -R "cat /boot/extlinux/extlinux.conf" /work/app.img
```

以下になっていればOK。

```text
root=/dev/nvme0n1p1
```

この確認・修正用の補助スクリプトもリポジトリに置いている。

- https://github.com/Sunwood-ai-labs/jetson-orin-nano-super-nvme-fix/blob/main/scripts/inspect-extlinux.sh
- https://github.com/Sunwood-ai-labs/jetson-orin-nano-super-nvme-fix/blob/main/scripts/patch-extlinux-root.sh

コンテナを抜ける。

```sh
exit
```

修正済みAPPイメージをM.2 SSDへ書き戻す。

```sh
sudo dd if=~/Prj/jetson-orin-nano-super-nvme-fix/work/app.img of=/dev/rdisk5s1 bs=4m status=progress
sync
diskutil eject /dev/disk5
```

これでM.2 SSDをJetsonに戻す。

## 起動成功

修正後、Jetson Orin Nano Super 8GBはNVMe SSDから起動した。

SSHでも接続できるようになった。

```sh
ssh jetson-orin
```

確認したカーネルは以下。

```text
Linux orin 5.15.148-tegra aarch64
```

## SSHキー設定

毎回パスワードを打たずに入れるようにSSHキーも設定した。

Mac側で鍵を作成。

```sh
ssh-keygen -t ed25519 -f ~/.ssh/jetson_orin_ed25519 -C "codex-jetson-orin"
```

Jetson側へ公開鍵を登録。

```sh
ssh-copy-id -i ~/.ssh/jetson_orin_ed25519.pub orin@192.168.11.26
```

`~/.ssh/config` に以下を追加。

```text
Host jetson-orin
    HostName 192.168.11.26
    User orin
    IdentityFile ~/.ssh/jetson_orin_ed25519
    IdentitiesOnly yes
```

これで以下だけでログインできる。

```sh
ssh jetson-orin
```

## jtop導入

Jetsonの状態監視用に `jtop` を入れた。

```sh
sudo apt update
sudo apt install -y python3-pip
sudo pip3 install -U jetson-stats
sudo systemctl restart jtop.service
```

実行。

```sh
jtop
```

またはMacから直接。

```sh
ssh -t jetson-orin jtop
```

## Ollama導入

ローカルLLM実行環境としてOllamaを入れた。

```sh
curl -fsSL https://ollama.com/install.sh -o /tmp/ollama-install.sh
sudo sh /tmp/ollama-install.sh
```

バージョン確認。

```sh
ollama --version
```

今回入ったのは以下。

```text
ollama version is 0.24.0
```

サービス確認。

```sh
systemctl status ollama --no-pager
```

OllamaはJetson上のCUDA / Orin GPUを認識した。

ログ上では以下を確認。

```text
CUDA
Orin
compute capability 8.7
```

## Gemma 4公式モデルを試す

まず公式のGemma 4 E2Bを試した。

モデルURL:

[gemma4:e2b - Ollama](https://ollama.com/library/gemma4:e2b)

実行。

```sh
ollama pull gemma4:e2b
```

モデル自体は取得できた。

```text
gemma4:e2b
SIZE: 7.2 GB
```

しかし、推論時に落ちた。

ログ確認。

```sh
journalctl -u ollama --no-pager -n 100
```

以下が出た。

```text
ollama.service: A process of this unit has been killed by the OOM killer.
```

つまり、公式 `gemma4:e2b` はJetson Orin Nano Super 8GBには重すぎた。

## Q4量子化版を試す

次にQ4量子化版を試した。

モデルURL:

[batiai/gemma4-e2b - Ollama](https://ollama.com/batiai/gemma4-e2b)

取得。

```sh
ollama pull batiai/gemma4-e2b:q4
```

サイズは約3.4GB。

```text
batiai/gemma4-e2b:q4
SIZE: 3.4 GB
```

実行。

```sh
ollama run batiai/gemma4-e2b:q4
```

確認。

```sh
ollama ps
```

結果。

```text
NAME                    PROCESSOR    CONTEXT
batiai/gemma4-e2b:q4    100% GPU     1024
```

GPUで動いている。

## APIで推論テスト

API経由でも試した。

```sh
python3 - <<'PY'
import json
import urllib.request

payload = {
    "model": "batiai/gemma4-e2b:q4",
    "prompt": "Say hello in Japanese. Keep it short.",
    "stream": False,
    "options": {
        "num_ctx": 1024,
        "num_predict": 256,
    },
}

req = urllib.request.Request(
    "http://127.0.0.1:11434/api/generate",
    data=json.dumps(payload).encode(),
    headers={"Content-Type": "application/json"},
)

with urllib.request.urlopen(req, timeout=180) as response:
    data = json.loads(response.read())

print(data.get("response", "").strip())
print("eval_count:", data.get("eval_count"))

if data.get("eval_count") and data.get("eval_duration"):
    print("tokens_per_sec:", round(data["eval_count"] / (data["eval_duration"] / 1e9), 2))
PY
```

結果。

```text
Konnichiwa.

eval_count: 205
tokens_per_sec: 21.81
```

Jetson Orin Nano Super 8GB上で、Gemma 4系Q4量子化モデルがローカルLLMとして動いた。

Ollama / Gemma 4実験の再現メモはこちら。

https://github.com/Sunwood-ai-labs/jetson-orin-nano-super-nvme-fix/tree/main/llm-experiment

## 注意: Gemma 4の空返答

最初、短すぎる `num_predict` では空返答になることがあった。

Gemma 4系は思考トークン側に出力枠を使う挙動があるため、`num_predict` が小さいと見える本文が出る前に終了することがある。

そのため、今回のテストでは以下のようにした。

```text
num_ctx: 1024
num_predict: 256
```

これで可視の応答が返った。

## 今回の結果

今回できたこと。

- NVIDIA公式SDカードイメージをM.2 SSDへ書き込み
- 起動設定 `/boot/extlinux/extlinux.conf` を修正
- `root=/dev/mmcblk0p1` から `root=/dev/nvme0n1p1` へ変更
- SDカードなしでNVMe起動
- SSHキー設定
- `jtop`導入
- Ollama導入
- CUDA / Orin GPU認識確認
- 公式 `gemma4:e2b` のOOM確認
- Q4量子化版 `batiai/gemma4-e2b:q4` の推論成功
- 約21.8 tokens/secを確認

再現に必要な手順・ログ・補助スクリプトは以下のリポジトリにまとめた。

https://github.com/Sunwood-ai-labs/jetson-orin-nano-super-nvme-fix

## まとめ

Jetson Orin Nano Super 8GBでも、モデル選定を間違えなければローカルLLMは動く。

ただし、公式の `gemma4:e2b` は7.2GBあり、8GB環境ではかなり厳しい。  
実際に今回もOOMで落ちた。

一方で、Q4量子化版の `batiai/gemma4-e2b:q4` は3.4GBで、Jetson上のGPUを使って推論できた。

Jetson単体で、

- 小型AIアシスタント
- カメラ入力 + LLM
- センサー情報を読むローカルエージェント
- ネットなしで動くエッジAIノード

を作る土台としてかなり面白い。

## 参考リンク

NVIDIA Jetson Orin Nano Developer Kit Getting Started Guide:

https://developer.nvidia.com/embedded/learn/get-started-jetson-orin-nano-devkit

NVIDIA Jetson Orin Nano Developer Kit User Guide - Software Setup:

https://developer.nvidia.com/embedded/learn/jetson-orin-nano-devkit-user-guide/software_setup.html

Ollama Gemma 4:

https://ollama.com/library/gemma4

Ollama Gemma 4 E2B:

https://ollama.com/library/gemma4:e2b

今回動いたQ4量子化版:

https://ollama.com/batiai/gemma4-e2b

再現リポジトリ:

https://github.com/Sunwood-ai-labs/jetson-orin-nano-super-nvme-fix
