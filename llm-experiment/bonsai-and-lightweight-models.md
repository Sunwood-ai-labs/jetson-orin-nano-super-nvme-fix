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

Result on Jetson:

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

CPU-only retry:

```sh
OLLAMA_HOST=127.0.0.1:11435 OLLAMA_LLM_LIBRARY=cpu ollama serve
OLLAMA_HOST=127.0.0.1:11435 ollama pull eslider/bonsai-1.7b
```

CPU-only generation failed the same way.

Conclusion: `eslider/bonsai-1.7b` can be pulled, but did not run on this Jetson + Ollama 0.24.0 setup. This looks like a runner/model compatibility issue rather than a memory-capacity issue.

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
| `eslider/bonsai-1.7b` | 248 MB | failed | not loaded | runner/internal load failure |
| `qwen3:0.6b` | 522 MB | works | 100% GPU | about 52.8 tok/s API decode rate |

