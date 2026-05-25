# Local LLM Experiment

## Runtime

Ollama was installed on the Jetson:

```sh
curl -fsSL https://ollama.com/install.sh -o /tmp/ollama-install.sh
sudo sh /tmp/ollama-install.sh
ollama --version
```

Observed:

```text
ollama version is 0.24.0
```

The Ollama logs showed CUDA detection for Orin:

```text
CUDA
Orin
compute capability 8.7
```

## Models Tested

| Model | Size | Result |
| --- | ---: | --- |
| `gemma4:e2b` | 7.2 GB | Pull succeeded, generation was killed by OOM |
| `batiai/gemma4-e2b:q4` | 3.4 GB | Worked with GPU offload |
| `eslider/bonsai-1.7b` | 248 MB | Pull succeeded, runner failed to load on this Jetson/Ollama setup |
| `qwen3:0.6b` | 522 MB | Worked with GPU offload as a lightweight fallback |

Model URLs:

- https://ollama.com/library/gemma4:e2b
- https://ollama.com/batiai/gemma4-e2b
- https://ollama.com/eslider/bonsai-1.7b
- https://ollama.com/library/qwen3:0.6b

## Smoke Test

```sh
./llm-experiment/run-gemma4-q4-smoke-test.sh
```

Observed:

```text
Konnichiwa.
eval_count: 205
tokens_per_sec: 21.81
```

## Practical Note

Small `num_predict` values may return an empty visible response with this Gemma 4-class model because the output budget can be consumed before visible answer text appears. The smoke test uses `num_predict: 256`.

## Bonsai-like Lightweight Follow-up

`eslider/bonsai-1.7b` was extremely small and pulled successfully, but failed during model load on both the default CUDA-backed Ollama service and a CPU-only Ollama serve process. The failure looked like a runner/model compatibility issue, not a memory-capacity issue.

`qwen3:0.6b` worked as the practical lightweight fallback:

```text
qwen3:0.6b
SIZE: 522 MB
PROCESSOR: 100% GPU
```

Observed API decode rate:

```text
tokens_per_sec: 52.77
```

Detailed notes: [Bonsai-like lightweight local LLM experiment](https://github.com/Sunwood-ai-labs/jetson-orin-nano-super-nvme-fix/blob/main/llm-experiment/bonsai-and-lightweight-models.md)
