# Jetson Orin Nano Super 8GB NVMe起動・ローカルLLM実験 引き継ぎレポート

作成日: 2026-05-27

対象リポジトリ:

- https://github.com/Sunwood-ai-labs/jetson-orin-nano-super-nvme-fix

## 目的

Jetson Orin Nano Super 8GBをSDカードなしでM.2 NVMe SSDから起動し、その上でローカルLLMを動かす。最終的に以下を確認した。

- NVMe SSDからのOS起動
- SSH鍵ログイン
- `jtop`導入
- Ollama導入
- Gemma 4系Q4量子化モデルのGPU推論
- Bonsai系軽量モデルの実行可否
- Ternary Bonsai GGUFの実行可否

## 重要な前提

今回のNVMe起動手順は、NVIDIA公式のNVMeフラッシュ手順そのものではない。

公式の正攻法は、UbuntuホストPCでJetsonをRecovery Modeに入れ、SDK ManagerまたはLinux for Tegraの`l4t_initrd_flash.sh`でNVMeへフラッシュする方法。

今回の実験では、以下の条件に合わせて別ルートを取った。

- SDカードを使わない
- MacにM.2 NVMe SSDを外付け接続できる
- まずJetsonを起動可能な状態に復旧する

実施した方法は、NVIDIA公式のJetson Orin Nano Developer Kit用SDカードイメージをM.2 NVMe SSDに書き込み、rootデバイス指定だけをNVMe向けに修正する方法。

## OSイメージ

使用したOSイメージ:

- 公式手順: https://developer.nvidia.com/embedded/learn/get-started-jetson-orin-nano-devkit
- Software setup: https://developer.nvidia.com/embedded/learn/jetson-orin-nano-devkit-user-guide/software_setup.html
- ZIP: `jp62-r1-orin-nano-sd-card-image.zip`
- ZIP内イメージ: `sd-blob.img`

## NVMe起動で直した内容

最初の起動失敗時、画面に以下のようなエラーが出た。

```text
Root device found: mmcblk0p1
ERROR: mmcblk0p1 not found
```

原因は、起動設定がmicroSDカード側のrootfsを探していたこと。

修正ファイル:

```text
/boot/extlinux/extlinux.conf
```

修正内容:

```diff
- root=/dev/mmcblk0p1
+ root=/dev/nvme0n1p1
```

証跡:

- `logs/extlinux-before.conf`
- `logs/extlinux-after.conf`
- `logs/diskutil-before-fix.txt`
- `logs/diskutil-after-fix.txt`

## Mac上で行った修正ルート

macOS標準ではext4を直接書き換えられないため、APPパーティションをイメージとして吸い出し、Docker上のUbuntuで`debugfs`を使って修正した。

大まかな流れ:

```sh
diskutil list /dev/disk5
sudo dd if=/dev/rdisk5s1 of=~/Prj/jetson-orin-nano-super-nvme-fix/work/app.img bs=4m status=progress

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
```

Macへ戻って書き戻し:

```sh
sudo dd if=~/Prj/jetson-orin-nano-super-nvme-fix/work/app.img of=/dev/rdisk5s1 bs=4m status=progress
sync
diskutil eject /dev/disk5
```

## 現在のJetson状態

確認日時: 2026-05-27

Kernel:

```text
Linux orin 5.15.148-tegra aarch64
```

rootfs:

```text
nvme0n1p1  475.5G ext4  /
nvme0n1p10 64M   vfat  /boot/efi
```

Ollama:

```text
ollama version is 0.24.0
```

systemdの`ollama.service`はinactive。ただし手動起動の`ollama serve`が`127.0.0.1:11435`で稼働中。

稼働中ポート:

```text
11434  bonsai-ollama proxy
11435  ollama backend
9988   PrismML llama-server for Bonsai Q1_0
9989   PrismML llama-server for Ternary Bonsai Q2_0
```

稼働中プロセス:

```text
bonsai-ollama-proxy
/usr/local/bin/ollama serve
llama-server -m Bonsai-1.7B-Q1_0.gguf --port 9988
llama-server -m Ternary-Bonsai-1.7B-Q2_0.gguf --port 9989
```

モデルファイル:

```text
~/Prj/bonsai/bonsai-ollama/models/bonsai-1.7b/Bonsai-1.7B-Q1_0.gguf
~/Prj/bonsai/bonsai-ollama/models/ternary-bonsai-1.7b/Ternary-Bonsai-1.7B-Q2_0.gguf
```

## SSHと監視

SSHはMac側の`~/.ssh/config`にaliasを作成済み。

```sh
ssh jetson-orin
```

Jetson監視用に`jtop`を導入済み。

```sh
jtop
```

## Gemma 4系ローカルLLM実験

### `gemma4:e2b`

URL:

- https://ollama.com/library/gemma4:e2b

結果:

- pull成功
- サイズ約7.2GB
- 推論時にOOM kill
- Jetson Orin Nano Super 8GBでは厳しい

代表ログ:

```text
ollama.service: A process of this unit has been killed by the OOM killer.
```

### `batiai/gemma4-e2b:q4`

URL:

- https://ollama.com/batiai/gemma4-e2b

結果:

- pull成功
- サイズ約3.4GB
- Jetson GPUで推論成功
- `ollama ps`で`100% GPU`確認
- APIスモークテストで約21.8 tok/s

実測:

```text
Konnichiwa.
eval_count: 205
tokens_per_sec: 21.81
```

## Bonsai 1.7B実験

### `eslider/bonsai-1.7b`

URL:

- https://ollama.com/eslider/bonsai-1.7b

標準Ollamaでの結果:

- pull成功
- サイズ約248MB
- 生成時ロード失敗
- CPU-onlyでも失敗
- 原因はOOMではなく、Q1_0 GGUFとstock Ollama runnerの互換性問題

代表エラー:

```text
HTTP 500
model failed to load
llama runner terminated
```

### 成功ルート

`bonsai-ollama` proxyとPrismML版`llama-server`を使うと実行できた。

参照:

- https://github.com/eSlider/bonsai-ollama
- https://github.com/PrismML-Eng/llama.cpp/releases
- https://huggingface.co/prism-ml/Bonsai-1.7B-gguf

JetPack 6 / Ubuntu 22.04では、PrismMLのprebuilt arm64バイナリがglibc不一致で動かなかった。

代表エラー:

```text
GLIBC_2.38 not found
GLIBCXX_3.4.32 not found
CXXABI_1.3.15 not found
```

そのため、Jetson上でPrismML `llama-server`をnative buildした。

```sh
cd ~/Prj/bonsai
git clone https://github.com/PrismML-Eng/llama.cpp.git
cd llama.cpp
git fetch --tags origin
git checkout prism-b8846-d104cf1

cmake -B build-bonsai-cpu \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_CUDA=OFF \
  -DGGML_VULKAN=OFF \
  -DLLAMA_BUILD_SERVER=ON

cmake --build build-bonsai-cpu --target llama-server -j$(nproc)
```

実行:

```sh
cd ~/Prj/bonsai/bonsai-ollama
export PATH=/usr/local/go/bin:$PATH
export BONSAI_PRISM_LIB_DIR=$HOME/Prj/bonsai/llama.cpp/build-bonsai-cpu/bin
./bin/run.sh
```

成功確認:

```text
response: こんにちは！
predicted_per_second: 11.14
```

ただし日本語品質は弱い。短文挨拶は返るが、自由質問や長文では崩れや反復が出る。

## Ternary Bonsai 1.7B GGUF実験

ユーザー指定モデル:

- https://huggingface.co/prism-ml/Ternary-Bonsai-1.7B-gguf

使用ファイル:

```text
Ternary-Bonsai-1.7B-Q2_0.gguf
```

サイズ:

```text
442 MB
```

ダウンロード:

```sh
cd ~/Prj/bonsai/bonsai-ollama
mkdir -p models/ternary-bonsai-1.7b
curl -fL \
  -o models/ternary-bonsai-1.7b/Ternary-Bonsai-1.7B-Q2_0.gguf \
  https://huggingface.co/prism-ml/Ternary-Bonsai-1.7B-gguf/resolve/main/Ternary-Bonsai-1.7B-Q2_0.gguf
```

起動:

```sh
nohup ~/Prj/bonsai/llama.cpp/build-bonsai-cpu/bin/llama-server \
  -m ~/Prj/bonsai/bonsai-ollama/models/ternary-bonsai-1.7b/Ternary-Bonsai-1.7B-Q2_0.gguf \
  --host 127.0.0.1 \
  --port 9989 \
  --ctx-size 4096 \
  --parallel 1 \
  --threads 6 \
  --no-webui \
  > /tmp/ternary-bonsai-server.log 2>&1 &
```

ロード成功:

```text
CPU_Mapped model buffer size = 436.16 MiB
CPU KV buffer size = 448.00 MiB
main: model loaded
main: server is listening on http://127.0.0.1:9989
```

短文日本語:

```text
こんにちは。私はBonsaiです。PrismMLが開発したAIアシスタントです。日本語で一文だけの自我紹介をします。
```

速度:

```text
predicted_per_second: 9.52
```

英語短文:

```text
A local LLM is a large language model that runs entirely on a single device, such as a computer or mobile phone, without requiring access to a centralized server or cloud infrastructure.
```

英語速度:

```text
predicted_per_second: 10.51
```

ストリーミング:

```text
22 chunks
elapsed: 3.85 s
output: 1 2 3 4 5 6 7 8 9 10
```

同じ日本語質問での確認:

```text
prompt: 最強のご飯を提案して
elapsed: 29.25 s
predicted: 256 tokens
speed: 9.08 tok/s
```

出力品質:

- 冒頭は日本語として読める
- 途中から「料理スタイル」などの反復に崩れる
- 日本語長文用途では不採用判断
- 英語の方が安定

Ollama direct importも試した。

```sh
OLLAMA_HOST=http://127.0.0.1:11435 ollama create ternary-bonsai-1.7b-q2 -f /tmp/Modelfile.ternary
```

結果:

- manifest作成は成功
- 生成時ロードでHTTP 500
- stock Ollama経由は現時点では実用不可

## Qwen3 0.6B実験

URL:

- https://ollama.com/library/qwen3:0.6b

結果:

- サイズ約522MB
- Ollamaでpull成功
- Jetson GPU offload成功
- `ollama ps`で`100% GPU`確認
- API decode速度は約52.8 tok/s

注意:

- APIでは空返答になるケースがあった
- CLIでは可視出力あり
- 日本語用途ではBonsai系より現実的

## モデル比較

| Model | Size | Result | Processor | Notes |
| --- | ---: | --- | --- | --- |
| `gemma4:e2b` | 7.2GB | failed | partial load | OOM killed |
| `batiai/gemma4-e2b:q4` | 3.4GB | works | 100% GPU | about 21.8 tok/s |
| `eslider/bonsai-1.7b` stock Ollama | 248MB | failed | not loaded | Q1_0 unsupported |
| `eslider/bonsai-1.7b` via bonsai-ollama + PrismML | 237MB GGUF | works | CPU | about 11.1 tok/s |
| `prism-ml/Ternary-Bonsai-1.7B-gguf` Q2_0 via PrismML | 442MB GGUF | works | CPU | about 9.1-10.5 tok/s; Japanese weak |
| `prism-ml/Ternary-Bonsai-1.7B-gguf` Q2_0 via stock Ollama | 463MB Ollama model | failed | not loaded | manifest created, load failed |
| `qwen3:0.6b` | 522MB | works | 100% GPU | about 52.8 tok/s |

## 現時点の判断

日本語で使う前提なら、Bonsai系はまだ品質不足。

実験としては以下の判断。

- 最軽量Bonsaiを動かす実験: 成功
- Ternary Bonsaiを動かす実験: 成功
- Bonsai系を日本語用途に採用: 現時点では非推奨
- 日本語軽量LLM候補: `qwen3:0.6b`の方が現実的
- Gemma 4系で品質を取りたい場合: `batiai/gemma4-e2b:q4`

## リポジトリで整備済みのもの

主要ファイル:

- `README.md`
- `README.ja.md`
- `docs/ja/article.md`
- `docs/article-with-repo-url-ja.md`
- `docs/guide/nvme-boot-repair.md`
- `docs/guide/local-llm.md`
- `llm-experiment/README.md`
- `llm-experiment/bonsai-and-lightweight-models.md`
- `llm-experiment/run-gemma4-q4-smoke-test.sh`
- `scripts/inspect-extlinux.sh`
- `scripts/patch-extlinux-root.sh`

GitHub Pages / VitePress:

- `docs/.vitepress/config.mts`
- `.github/workflows/pages.yml`

CI:

- `.github/workflows/ci.yml`
- `npm run check`

直近コミット:

```text
7694c7f Document Ternary Bonsai Jetson experiment
bd3249b Document working Bonsai proxy path on Jetson
a4980d6 Add Bonsai lightweight LLM experiment
b4dbba5 Add article markdown with repository URL
```

## 検証状況

リポジトリ側チェック:

```sh
npm run check
```

結果:

```text
check:shell passed
check:large passed
vitepress build passed
```

## 未解決・次にやるなら

1. Bonsai系の日本語品質改善

   日本語チューニング済みBonsaiは現時点で見つかっていない。Bonsai系を継続するなら、日本語用途ではなく英語・低レイテンシ用途に絞る方がよい。

2. `qwen3:0.6b`の日本語評価

   Bonsaiより実用寄り。日本語プロンプトセットを固定して、速度・品質・空返答問題を確認する。

3. Ollama backend整理

   現在はsystemdの`ollama.service`ではなく、手動起動の`ollama serve`が`11435`で動いている。恒久運用するならsystemd unitを分ける。

4. PrismML `llama-server`のsystemd化

   `9988`と`9989`は現在手動起動プロセス。再起動後も使うならsystemd unit化する。

5. 公式NVMeフラッシュ手順との比較

   今回の方法は復旧実験として有効だが、再現性と保守性を上げるならUbuntuホスト + Recovery Mode + SDK Manager / `l4t_initrd_flash.sh`版の記事も別途作る。

## 引き継ぎ時の注意

- ディスク書き込み系コマンドは必ず`diskutil list`や`lsblk`で対象ディスクを確認してから実行する。
- パスワードや秘密情報はリポジトリに入れない。
- Bonsai系は「動いた」と「日本語で使える」を分けて判断する。
- `eslider/bonsai-1.7b`がstock Ollamaで失敗した原因はOOMではなくQ1_0互換性。
- Ternary Bonsai Q2_0もstock Ollamaでは生成時ロード失敗。PrismML直サーバーが現在の成功ルート。
- Jetson Orin Nano Super 8GBでGemma 4公式E2Bは重い。Q4量子化版を使う。
