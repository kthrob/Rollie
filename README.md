```
██████╗  ██████╗ ██╗     ██╗     ██╗███████╗
██╔══██╗██╔═══██╗██║     ██║     ██║██╔════╝
██████╔╝██║   ██║██║     ██║     ██║█████╗  
██╔══██╗██║   ██║██║     ██║     ██║██╔══╝  
██║  ██║╚██████╔╝███████╗███████╗██║███████╗
╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚══════╝╚═╝╚══════╝
```

A fish shell command that automates the full local LLM pipeline on Apple Silicon:

- **Abliterate** — strip refusal training from any open-weight HuggingFace model using [heretic](https://github.com/p-e-w/heretic)
- **Fine-tune** — LoRA training with [MLX-LM](https://github.com/ml-explore/mlx-examples), either standalone or chained after abliteration
- **Curate** — generate ChatML JSONL training datasets from codebases, GitHub repos, databases, local files, or persona definitions using a local Ollama model

Everything runs locally on-device. No cloud GPU required.

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

### Abliterate

```fish
rollie <hf-model-id>                              # full pipeline
rollie <hf-model-id> --quant Q5_K_M              # custom GGUF quantization
rollie <hf-model-id> --skip-import               # stop at GGUF; skip Ollama import
rollie <hf-model-id> --finetune <dataset-dir>    # abliterate then fine-tune
```

### Fine-tune (standalone)

```fish
rollie finetune <hf-model-id> --data <dataset-dir>    # download and fine-tune
rollie finetune <local-model-path> --data <dir>        # use a local model
rollie finetune <model> --data <dir> --iters 500 --rank 16   # custom hyperparameters
rollie finetune <model> --data <dir> --lr 5e-5               # custom learning rate
```

Dataset must be a directory containing `data.jsonl` in ChatML format:
```jsonl
{"text": "<|im_start|>user\n...<|im_end|>\n<|im_start|>assistant\n...<|im_end|>"}
```

### Curate datasets

```fish
rollie curate --persona ./persona.md --output ~/datasets/
rollie curate --code ~/myproject/ --output ~/datasets/
rollie curate --repo https://github.com/org/lib --output ~/datasets/
rollie curate --files ~/docs/ --output ~/datasets/
rollie curate --db sqlite:///mydb.db --output ~/datasets/
rollie curate --code ~/project/ --files ~/docs/ --output ~/datasets/stack/  # compose sources
```

Before curating, set the Ollama model that generates Q&A pairs:

```fish
rollie --set-data-curation-model
```

### Management

```fish
rollie --list                              # list rollie models in Ollama
rollie --status                            # workspace and config overview
rollie --clean <slug>                      # remove workspace files for a model
rollie --logs [slug]                       # tail a run log
rollie --set-finetune-defaults             # set LoRA iters, layers, rank
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

## Pipelines

### Abliterate pipeline

```
HuggingFace model ID
      │
      ▼
1. heretic              strips refusal direction from model weights
      │                   output → ~/rollie-workspace/models/abliterated/<slug>/
      │
      ▼ (optional --finetune)
1.5. mlx_lm.lora        LoRA fine-tuning on the abliterated model
      │   mlx_lm.fuse     adapters → ~/rollie-workspace/models/adapters/<slug>/
      │                   merged  → ~/rollie-workspace/models/merged/<slug>/
      ▼
2. convert              HF safetensors → GGUF F16
      │                   uses convert_hf_to_gguf.py from llama.cpp
      ▼
3. llama-quantize       GGUF F16 → GGUF Q4_K_M (or custom)
      │                   output → ~/rollie-workspace/models/gguf/<slug>.gguf
      ▼
4. ollama create        imports GGUF with a default Modelfile
                          model name → <slug>-heretic
```

### Fine-tune pipeline (standalone)

```
HuggingFace model ID or local path
      │
      ▼
1. download             huggingface-cli (if HF id; skipped if local path)
      │                   output → ~/rollie-workspace/models/base/<slug>/
      ▼
2. mlx_lm.lora          LoRA training on ChatML JSONL dataset
      │                   adapter → ~/rollie-workspace/models/adapters/<slug>/
      ▼
3. mlx_lm.fuse          fuse adapter into base
      │                   merged → ~/rollie-workspace/models/merged/<slug>/
      ▼
4–6. convert → quantize → ollama create   (same as above)
                          model name → <slug>-finetuned
```

### Curate pipeline

```
Source(s): --code / --repo / --db / --files / --persona
      │
      ▼
1. Ingest               parse into text chunks
      │                   (AST chunking for code via tree-sitter)
      ▼
2. Q&A generation       Ollama model generates N pairs per chunk
      ▼
3. Quality pass         second Ollama call rates each pair 1–5; drops below threshold
      ▼
4. Write JSONL          ChatML format to --output/data.jsonl
```

All pipelines are **resumable** — each stage checks for existing output before running. Interrupted runs resume from where they left off.

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
| `~/.config/fish/rollie-scripts/` | Curate Python scripts |
| `~/.config/rollie/data_curation_model` | Configured curation model |
| `~/.config/rollie/finetune_defaults` | Default LoRA hyperparameters |
| `~/rollie-workspace/models/abliterated/` | Heretic output (HF format) |
| `~/rollie-workspace/models/base/` | Downloaded base models |
| `~/rollie-workspace/models/adapters/` | LoRA adapters |
| `~/rollie-workspace/models/merged/` | Fused (adapter+base) models |
| `~/rollie-workspace/models/gguf/` | Final GGUF files and Modelfiles |
| `~/rollie-workspace/datasets/` | Generated JSONL datasets |
| `~/rollie-workspace/envs/heretic/` | Python env for heretic |
| `~/rollie-workspace/envs/convert/` | Python env for GGUF conversion |
| `~/rollie-workspace/envs/mlx/` | Python env for MLX fine-tuning |
| `~/rollie-workspace/envs/curate/` | Python env for dataset curation |
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
