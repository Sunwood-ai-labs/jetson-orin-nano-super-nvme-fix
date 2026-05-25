#!/usr/bin/env bash
set -euo pipefail

ssh jetson-orin 'python3 - <<'"'"'PY'"'"'
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
print()
print("model:", data.get("model"))
print("eval_count:", data.get("eval_count"))
if data.get("eval_count") and data.get("eval_duration"):
    print("tokens_per_sec:", round(data["eval_count"] / (data["eval_duration"] / 1e9), 2))
PY'
