# Jetson Orin Nano Super 8GB local LLM experiment

Date: 2026-05-25

## Device

- Host: `jetson-orin`
- Jetson: Orin Nano Super 8GB
- JetPack: R36.4.7
- CUDA detected by Ollama: Orin, compute capability 8.7, CUDA 12.6
- Root storage: NVMe

## Runtime

Installed Ollama with the official install script.

```sh
curl -fsSL https://ollama.com/install.sh -o /tmp/ollama-install.sh
sudo sh /tmp/ollama-install.sh
ollama --version
```

Installed version:

```text
ollama version is 0.24.0
```

Service:

```sh
systemctl status ollama --no-pager
```

## Models tested

### `gemma4:e2b`

Result: pulled successfully, but generation failed on Orin Nano 8GB.

Reason from `journalctl -u ollama`: the model loaded partway, then `ollama.service` was killed by the OOM killer.

Observed model size:

```text
gemma4:e2b  7.2 GB
```

Conclusion: too tight for this 8GB Jetson with Ollama defaults.

### `batiai/gemma4-e2b:q4`

Result: works.

Observed model size:

```text
batiai/gemma4-e2b:q4  3.4 GB
```

Ollama loaded it with GPU acceleration:

```text
PROCESSOR 100% GPU
CONTEXT   1024
```

Log evidence:

```text
architecture=gemma4 file_type=Q4_K_M name="Google Gemma 4 E2B It"
model weights device=CUDA0 size="3.2 GiB"
model weights device=CPU size="315.0 MiB"
offloaded 36/36 layers to GPU
total memory size="3.7 GiB"
```

## Repro command

```sh
ssh jetson-orin 'ollama run batiai/gemma4-e2b:q4'
```

API smoke test:

```sh
ssh jetson-orin 'python3 - <<'"'"'PY'"'"'
import json, urllib.request

payload = {
    "model": "batiai/gemma4-e2b:q4",
    "prompt": "Say hello in Japanese. Keep it short.",
    "stream": False,
    "options": {
        "num_ctx": 1024,
        "num_predict": 256
    }
}

req = urllib.request.Request(
    "http://127.0.0.1:11434/api/generate",
    data=json.dumps(payload).encode(),
    headers={"Content-Type": "application/json"},
)
with urllib.request.urlopen(req, timeout=180) as r:
    data = json.loads(r.read())

print(data["response"])
print("eval_count:", data.get("eval_count"))
print("tokens_per_sec:", data["eval_count"] / (data["eval_duration"] / 1e9))
PY'
```

Verified output:

```text
Konnichiwa.
eval_count: 205
tokens_per_sec: 21.81
```

## Note

With small `num_predict` values, Gemma 4 may spend the output budget on internal reasoning and return an empty `response`. Use `num_predict` around 256 or higher for reliable visible output.
