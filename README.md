```
 _ __   ___  _ _  _   ___
| '__| / _ \| | |(_) / _ \
| |   | (_) || | | | |  __/
|_|    \___/ |_|_|_|  \___|
```

```
             \ | /                 a fish shell command that
              \|/                  abliterates HuggingFace models
          ____(.)____              and rolls them into Ollama
         /  o (_) o  \
        | --|     |-- |            no cloud GPU.
        |   |_____|   |            no refusals.
         \_/         \_/           no gods, no masters.
              |   |
            (     )
           ( ~~~~~ )
          (  ~~~~~  )
           ( ~~~~~ )
            (     )
```

A fish shell command that automates the [heretic](https://github.com/p-e-w/heretic) abliteration pipeline on Apple Silicon — downloading an open-weight model from HuggingFace, stripping its refusal training, converting it to GGUF, and importing it into Ollama.

Everything runs locally. No cloud GPU required.

---

## Requirements

- macOS on Apple Silicon (M1/M2/M3/M4)
- [Homebrew](https://brew.sh)
- Fish shell

All other dependencies (uv, Ollama, llama.cpp, git-lfs, huggingface-cli, Python envs) are installed by the setup script.

---

## Installation

Clone the repo and run the setup script from the repo root:

```fish
git clone <repo-url> ~/Scripts/rollie
cd ~/Scripts/rollie
fish setup.fish
```

Open a new terminal and verify:

```fish
rollie --help
```

---

## Usage

```fish
rollie <hf-model-id>                       # full pipeline
rollie <hf-model-id> --quant Q5_K_M       # custom GGUF quantization
rollie <hf-model-id> --skip-import        # stop at GGUF; skip Ollama import
rollie --list                              # list rollie models in Ollama
rollie --status                            # workspace overview
rollie --clean <slug>                      # remove workspace files for a model
rollie --logs [slug]                       # tail a run log
rollie --help                              # show all commands
```

### Gate-locked models

Llama 3.x and Gemma require accepting a license on HuggingFace before downloading. Log in once:

```fish
huggingface-cli login
```

---

## Recommended models

| Model | HuggingFace ID | Estimated time (M1 32GB) |
|---|---|---|
| Qwen3-4B | `Qwen/Qwen3-4B-Instruct-2507` | 1.5–3 h |
| Qwen3-8B | `Qwen/Qwen3-8B-Instruct` | 3–5 h |
| Llama 3.1 8B | `meta-llama/Llama-3.1-8B-Instruct` | 3–5 h |
| Gemma 3 9B | `google/gemma-3-9b-it` | 3–5 h |
| Gemma 3 12B | `google/gemma-3-12b-it` | 6–10 h (overnight) |

> **Avoid Qwen3.5** — hybrid Mamba2+Transformer architecture, not supported by heretic.

---

## Pipeline

```
HuggingFace model ID
      │
      ▼
1. heretic          strips refusal direction from model weights
      │               output → ~/rollie-workspace/models/abliterated/<slug>/
      ▼
2. convert          HF safetensors → GGUF F16
      │               uses convert_hf_to_gguf.py from llama.cpp
      ▼
3. llama-quantize   GGUF F16 → GGUF Q4_K_M (or custom)
      │               output → ~/rollie-workspace/models/gguf/<slug>.gguf
      ▼
4. ollama create    imports GGUF with a default Modelfile
                      model name → <slug>-heretic
```

The pipeline is **resumable** — each stage checks for existing output before running. If rollie is interrupted, rerun the same command to continue from where it left off.

---

## Using the result with llamy

Once imported, the model appears in Ollama and can be launched directly with [llamy](../llamy):

```fish
llamy qwen3-8b-instruct-heretic
```

---

## File locations

| Path | Purpose |
|---|---|
| `~/.config/fish/functions/rollie.fish` | The installed function |
| `~/rollie-workspace/models/abliterated/` | Heretic output (HF format) |
| `~/rollie-workspace/models/gguf/` | Final GGUF files and Modelfiles |
| `~/rollie-workspace/envs/heretic/` | Python env for heretic |
| `~/rollie-workspace/envs/convert/` | Python env for GGUF conversion |
| `~/rollie-workspace/logs/` | Per-model run logs |

---

## Updating

To update dependencies and refresh the conversion script, re-run setup:

```fish
fish setup.fish
```

---

## Notes

- Activity Monitor → Metal GPU History will show GPU utilization during heretic. If it shows consistently low usage, PyTorch is falling back to CPU (a known MPS limitation for some ops) and the run will take longer.
- The intermediate F16 GGUF is deleted automatically after quantization succeeds.
- The Modelfile written at import sets `temperature 0.7`, `top_p 0.9`, and `num_ctx 8192`. Edit `~/rollie-workspace/models/gguf/<slug>.Modelfile` and re-run `ollama create` to change these.
