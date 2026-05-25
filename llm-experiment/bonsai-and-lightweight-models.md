# Bonsai-like lightweight local LLM experiment

Date: 2026-05-25

This note follows the Gemma 4 Q4 test and checks an even lighter model class on the Jetson Orin Nano Super 8GB.

## Runtime

- Jetson: Orin Nano Super 8GB
- Root storage: NVMe
- Ollama: `0.24.0`
- CUDA backend: JetPack 6 / CUDA 12.6

## Bonsai 1.7B

Model:

- `eslider/bonsai-1.7b`
- Ollama page: https://ollama.com/eslider/bonsai-1.7b
- Observed size: `248 MB`

Pull:

```sh
ollama pull eslider/bonsai-1.7b
```

Result:

```text
success
```

Generation test:

```sh
python3 - <<'PY'
import json
import urllib.request

payload = {
    "model": "eslider/bonsai-1.7b",
    "prompt": "Say hello in Japanese. Keep it short.",
    "stream": False,
    "options": {
        "num_ctx": 1024,
        "num_predict": 128,
    },
}

req = urllib.request.Request(
    "http://127.0.0.1:11434/api/generate",
    data=json.dumps(payload).encode(),
    headers={"Content-Type": "application/json"},
)
with urllib.request.urlopen(req, timeout=180) as response:
    print(response.read().decode())
PY
```

Result on the stock Ollama service:

```text
HTTP 500
model failed to load, this may be due to resource limitations or an internal error
```

The systemd Ollama log showed that the llama runner terminated while loading the model:

```text
llama runner terminated
Load failed
model failed to load
```

CPU-only retry with stock Ollama:

```sh
OLLAMA_HOST=127.0.0.1:11435 OLLAMA_LLM_LIBRARY=cpu ollama serve
OLLAMA_HOST=127.0.0.1:11435 ollama pull eslider/bonsai-1.7b
```

CPU-only generation failed the same way.

Conclusion at this stage: `eslider/bonsai-1.7b` can be pulled, but stock Ollama 0.24.0 cannot load its Q1_0 tensors. This is a runner/model compatibility issue rather than a memory-capacity issue.

## Bonsai working path: bonsai-ollama + PrismML llama-server

The model can run by using the dedicated `bonsai-ollama` proxy with PrismML's `llama-server`.

Primary references:

- https://github.com/eSlider/bonsai-ollama
- https://github.com/PrismML-Eng/llama.cpp/releases
- https://huggingface.co/prism-ml/Bonsai-1.7B-gguf

The important detail for Jetson is that the prebuilt Prism Ubuntu arm64 release requires a newer glibc than JetPack 6 / Ubuntu 22.04 provides:

```text
GLIBC_2.38 not found
GLIBCXX_3.4.32 not found
CXXABI_1.3.15 not found
```

So the working route was:

1. Install Go 1.22+ from the official arm64 tarball.
2. Clone `eSlider/bonsai-ollama`.
3. Run `setup.sh` with the Prism Ubuntu arm64 release URL to download Bonsai GGUF and build the Go proxy.
4. Clone `PrismML-Eng/llama.cpp`.
5. Build PrismML `llama-server` natively on the Jetson to avoid glibc mismatch.
6. Run `bonsai-ollama` with `BONSAI_PRISM_LIB_DIR` pointing at the native build.

### Commands used on Jetson

Install Go 1.22+:

```sh
cd /tmp
ver=$(python3 - <<'PY'
import json, urllib.request
with urllib.request.urlopen("https://go.dev/dl/?mode=json") as r:
    data = json.load(r)
for f in data[0]["files"]:
    if f["os"] == "linux" and f["arch"] == "arm64" and f["kind"] == "archive":
        print(data[0]["version"])
        break
PY
)
curl -fL -o ${ver}.linux-arm64.tar.gz https://go.dev/dl/${ver}.linux-arm64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf ${ver}.linux-arm64.tar.gz
export PATH=/usr/local/go/bin:$PATH
go version
```

Set up `bonsai-ollama`:

```sh
mkdir -p ~/Prj/bonsai
cd ~/Prj/bonsai
git clone https://github.com/eSlider/bonsai-ollama.git
cd bonsai-ollama

BONSAI_SETUP_PRISM_TAR_URL=https://github.com/PrismML-Eng/llama.cpp/releases/download/prism-b8846-d104cf1/llama-prism-b8846-d104cf1-bin-ubuntu-arm64.tar.gz \
  ./bin/setup.sh --force
```

The prebuilt arm64 `llama-server` failed on JetPack 6 due to glibc mismatch, so build PrismML `llama-server` locally:

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

Run the stack:

```sh
cd ~/Prj/bonsai/bonsai-ollama
export PATH=/usr/local/go/bin:$PATH
export BONSAI_PRISM_LIB_DIR=$HOME/Prj/bonsai/llama.cpp/build-bonsai-cpu/bin
./bin/run.sh
```

Ports:

```text
11434  bonsai-ollama-proxy
11435  normal ollama backend
9988   PrismML llama-server
```

### Verified Bonsai output

Ollama-compatible API through the proxy:

```sh
python3 - <<'PY'
import json
import urllib.request

payload = {
    "model": "eslider/bonsai-1.7b",
    "prompt": "Say hello in Japanese. Keep it short.",
    "stream": False,
    "options": {
        "num_predict": 128,
        "temperature": 0.2,
    },
}

req = urllib.request.Request(
    "http://127.0.0.1:11434/api/generate",
    data=json.dumps(payload).encode(),
    headers={"Content-Type": "application/json"},
)
with urllib.request.urlopen(req, timeout=240) as response:
    print(response.read().decode())
PY
```

Result:

```json
{"created_at":"2026-05-25T15:47:32.874978138Z","done":true,"model":"eslider/bonsai-1.7b","response":"こんにちは！"}
```

Ollama CLI through the proxy:

```sh
export OLLAMA_HOST=http://127.0.0.1:11434
printf "Say hello in Japanese. Keep it short.\n" | ollama run eslider/bonsai-1.7b
```

Result:

```text
こんにちは！
```

Direct PrismML server timing:

```sh
curl -sS http://127.0.0.1:9988/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"bonsai","messages":[{"role":"user","content":"Say hello in Japanese. Keep it short."}],"max_tokens":128,"temperature":0.2,"stream":false}'
```

Observed timing:

```text
prompt_tokens: 21
completion_tokens: 3
predicted_per_second: 11.14
```

Conclusion: Bonsai 1.7B works on Jetson Orin Nano Super 8GB when routed through `bonsai-ollama` and a Jetson-native PrismML `llama-server` build. It does not work through stock Ollama alone.

## Ternary Bonsai 1.7B GGUF

Model:

- `prism-ml/Ternary-Bonsai-1.7B-gguf`
- Hugging Face page: https://huggingface.co/prism-ml/Ternary-Bonsai-1.7B-gguf
- Tested file: `Ternary-Bonsai-1.7B-Q2_0.gguf`
- Observed file size on Jetson: `442 MB`

Download:

```sh
cd ~/Prj/bonsai/bonsai-ollama
mkdir -p models/ternary-bonsai-1.7b
curl -fL \
  -o models/ternary-bonsai-1.7b/Ternary-Bonsai-1.7B-Q2_0.gguf \
  https://huggingface.co/prism-ml/Ternary-Bonsai-1.7B-gguf/resolve/main/Ternary-Bonsai-1.7B-Q2_0.gguf
```

Run it with the Jetson-native PrismML `llama-server` build:

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

Server load evidence:

```text
CPU_Mapped model buffer size = 436.16 MiB
CPU KV buffer size = 448.00 MiB
main: model loaded
main: server is listening on http://127.0.0.1:9989
```

Direct OpenAI-compatible API test:

```sh
curl -sS http://127.0.0.1:9989/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"ternary-bonsai","messages":[{"role":"user","content":"こんにちは。日本語で一文だけ自己紹介して。"}],"max_tokens":128,"temperature":0.2,"stream":false}'
```

Observed Japanese short response:

```text
こんにちは。私はBonsaiです。PrismMLが開発したAIアシスタントです。日本語で一文だけの自我紹介をします。
```

Observed timing:

```text
prompt_tokens: 26
completion_tokens: 38
predicted_per_second: 9.52
```

English short response was more natural:

```text
A local LLM is a large language model that runs entirely on a single device, such as a computer or mobile phone, without requiring access to a centralized server or cloud infrastructure.
```

Observed English timing:

```text
prompt_tokens: 24
completion_tokens: 37
predicted_per_second: 10.51
```

Streaming also worked through the direct PrismML server:

```sh
curl -N http://127.0.0.1:9989/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"ternary-bonsai","messages":[{"role":"user","content":"Count from 1 to 10 slowly, separated by spaces."}],"max_tokens":64,"temperature":0.2,"stream":true}'
```

Observed stream result:

```text
22 chunks
elapsed: 3.85 s
output: 1 2 3 4 5 6 7 8 9 10
```

Stock Ollama import was also tested:

```sh
cat > /tmp/Modelfile.ternary <<'EOF'
FROM /home/orin/Prj/bonsai/bonsai-ollama/models/ternary-bonsai-1.7b/Ternary-Bonsai-1.7B-Q2_0.gguf
TEMPLATE """{{ if .System }}<|im_start|>system
{{ .System }}<|im_end|>
{{ end }}{{ if .Prompt }}<|im_start|>user
{{ .Prompt }}<|im_end|>
<|im_start|>assistant
{{ end }}"""
PARAMETER stop <|im_end|>
PARAMETER temperature 0.2
EOF

OLLAMA_HOST=http://127.0.0.1:11435 ollama create ternary-bonsai-1.7b-q2 -f /tmp/Modelfile.ternary
```

The model manifest was created, but generation failed at load time:

```text
HTTP 500
model failed to load, this may be due to resource limitations or an internal error
```

Conclusion: `prism-ml/Ternary-Bonsai-1.7B-gguf` can run on Jetson Orin Nano Super 8GB through the Jetson-native PrismML `llama-server`. It is not a good Japanese-answer model in this test: short Japanese works, but longer Japanese answers still repeat and drift. English output is noticeably more stable.

## Qwen3 0.6B as a working lightweight fallback

Model:

- `qwen3:0.6b`
- Ollama page: https://ollama.com/library/qwen3:0.6b
- Observed size: `522 MB`

Pull:

```sh
ollama pull qwen3:0.6b
```

Result:

```text
success
```

Generation API test:

```sh
python3 - <<'PY'
import json
import time
import urllib.request

payload = {
    "model": "qwen3:0.6b",
    "prompt": "Say hello in Japanese. Keep it short.",
    "stream": False,
    "options": {
        "num_ctx": 1024,
        "num_predict": 128,
        "temperature": 0.2,
    },
}

req = urllib.request.Request(
    "http://127.0.0.1:11434/api/generate",
    data=json.dumps(payload).encode(),
    headers={"Content-Type": "application/json"},
)

start = time.time()
with urllib.request.urlopen(req, timeout=180) as response:
    data = json.loads(response.read())

print("response:", repr(data.get("response", "").strip()))
print("eval_count:", data.get("eval_count"))
print("tokens_per_sec:", data["eval_count"] / (data["eval_duration"] / 1e9))
print("wall_seconds:", round(time.time() - start, 2))
PY
```

Observed API result:

```text
response: ''
eval_count: 128
tokens_per_sec: 52.77
wall_seconds: 4.61
```

The empty API response is similar to the earlier Gemma 4 behavior: the model used the output budget before visible text appeared. The terminal CLI produced visible output:

```sh
printf "/no_think\nSay hello in Japanese.\n" | ollama run qwen3:0.6b
```

Visible output:

```text
こんにちは！
何かお世話いたします！
```

Ollama runtime evidence:

```text
qwen3:0.6b  522 MB
PROCESSOR  100% GPU
CONTEXT    4096
```

Log evidence:

```text
architecture=qwen3 file_type=Q4_K_M name="Qwen3 0.6B"
offloaded 29/29 layers to GPU
model weights device=CUDA0 size="409.3 MiB"
model weights device=CPU size="83.5 MiB"
total memory size="1008.8 MiB"
```

Conclusion: for an actually working lightweight model on this Jetson setup, `qwen3:0.6b` is currently a better fit than Bonsai through Ollama.

## Current model comparison

| Model | Size | Jetson result | Processor | Notes |
| --- | ---: | --- | --- | --- |
| `gemma4:e2b` | 7.2 GB | failed | partial load | OOM killed |
| `batiai/gemma4-e2b:q4` | 3.4 GB | works | 100% GPU | about 21.8 tok/s |
| `eslider/bonsai-1.7b` with stock Ollama | 248 MB | failed | not loaded | Q1_0 unsupported by stock Ollama runner |
| `eslider/bonsai-1.7b` with bonsai-ollama + native PrismML server | 231 MB GGUF | works | CPU via PrismML server | about 11.1 tok/s on short test |
| `prism-ml/Ternary-Bonsai-1.7B-gguf` Q2_0 with native PrismML server | 442 MB GGUF | works | CPU via PrismML server | about 9.5-10.5 tok/s; Japanese still weak |
| `prism-ml/Ternary-Bonsai-1.7B-gguf` Q2_0 with stock Ollama import | 442 MB GGUF | failed | not loaded | manifest created, load returned HTTP 500 |
| `qwen3:0.6b` | 522 MB | works | 100% GPU | about 52.8 tok/s API decode rate |
