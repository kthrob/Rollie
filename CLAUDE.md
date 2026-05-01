# rollie

## Purpose

This repository provides `rollie` — a fish shell function for macOS (Apple Silicon) that automates the heretic abliteration pipeline with a single command. It downloads an open-weight model from HuggingFace, strips its refusal training using [heretic](https://github.com/p-e-w/heretic), converts it to GGUF format, and imports it into Ollama — ready to use with `llamy` or directly via `ollama run`.

The entire pipeline runs locally on-device. No cloud GPU required.

### What's in this repo

| File | Description |
|---|---|
| `rollie.fish` | The fish function — this is the main deliverable |
| `setup.fish` | Installer: checks/installs dependencies, sets up Python envs, copies `rollie.fish` |
| `scripts/curate.py` | Main entry point for `rollie curate` — dispatches to source modules |
| `scripts/qa_generator.py` | Ollama Q&A generation (POST /api/chat) |
| `scripts/quality_pass.py` | Second-pass Ollama rating + filtering |
| `scripts/sources/codebase.py` | Codebase walker, AST chunker, .gitignore handling |
| `scripts/sources/repo.py` | Shallow GitHub clone + codebase ingestion |
| `scripts/sources/database.py` | SQLite + PostgreSQL schema extractor + row sampler |
| `scripts/sources/files.py` | PDF/DOCX/MD/TXT parsers |
| `scripts/sources/persona.py` | Agency-agents persona parser + synthetic conversation generator |
| `CLAUDE.md` | This file — context for agents |
| `README.md` | Human-facing documentation |
| `BACKLOG.md` | Planned features, improvements, and bug fixes |

---

## Requirements

- **macOS on Apple Silicon (M1/M2/M3/M4)**
- **[Homebrew](https://brew.sh)**
- **[uv](https://github.com/astral-sh/uv)** — manages Python virtual environments
- **[Ollama](https://ollama.com)** — imports and serves the final model
- **[llama.cpp](https://github.com/ggerganov/llama.cpp)** — `llama-quantize` for GGUF quantization
- **git + git-lfs** — required for HuggingFace model downloads
- **huggingface-cli** — for login to gate-locked models (Llama, Gemma)
- **Fish shell**

All of the above are installed or upgraded by `setup.fish`.

---

## Pipeline stages

### Abliterate pipeline (`rollie <hf-id>`)

| Stage | Tool | What it does |
|---|---|---|
| 1. Abliterate | `heretic` (uv env) | Downloads model from HF, removes refusal direction from weights |
| 1.5. Finetune (optional) | `mlx_lm.lora` + `mlx_lm.fuse` (mlx uv env) | LoRA training + adapter fuse, when `--finetune <dir>` is passed |
| 2+3. Convert+Quantize | `convert_hf_to_gguf.py` + `llama-quantize` | HF safetensors → GGUF F16 → Q4_K_M |
| 4. Import | `ollama create` | Imports GGUF into Ollama as `<slug>-heretic` (or `<slug>-heretic-finetuned`) |

### Finetune pipeline (`rollie finetune <model> --data <dir>`)

| Stage | Tool | What it does |
|---|---|---|
| 1. Download | `huggingface-cli` | Downloads base model if HF id given; skips if local path |
| 2. Train | `mlx_lm.lora` | LoRA training; adapter saved to `models/adapters/<slug>/` |
| 3. Fuse | `mlx_lm.fuse` | Merges adapter into base; merged model at `models/merged/<slug>/` |
| 4+5. Convert+Quantize | same as above | GGUF pipeline |
| 6. Import | `ollama create` | Imports as `<slug>-finetuned` |

### Curate pipeline (`rollie curate [source flags]`)

| Stage | Tool | What it does |
|---|---|---|
| Ingest | Python (curate env) | Parses source into text chunks (AST chunking for code) |
| Q&A generation | Ollama (configured model) | POST /api/chat — generates N Q&A pairs per chunk |
| Quality pass | Ollama (same model) | Rates each pair 1–5; drops pairs below threshold |
| Format + write | Python | Writes ChatML JSONL to output dir |

Each stage is **idempotent** — it checks for existing output and skips if already done. Interrupted runs can be resumed by rerunning the same command.

---

## Installation

Run the setup script from the repository root:

```fish
fish setup.fish
```

The script will, in order:

1. Install or update **Homebrew**
2. Install or update **uv**
3. Install or update **git** and **git-lfs** (and run `git lfs install`)
4. Install or update **Ollama**
5. Install or update **llama.cpp** (for `llama-quantize`)
6. Install **huggingface-cli** via `uv tool install`
7. Create the workspace at `~/rollie-workspace/`
8. Create the **heretic** uv env and install `heretic-llm` + PyTorch (MPS)
9. Create the **convert** uv env, install conversion dependencies, and download `convert_hf_to_gguf.py` version-matched to the installed `llama-quantize`
10. Copy `rollie.fish` → `~/.config/fish/functions/rollie.fish`

Then open a new terminal and verify:

```fish
rollie --help
```

---

## Usage

```fish
# Abliterate pipeline
rollie Qwen/Qwen3-8B-Instruct                                # full pipeline (3–5 h on M1)
rollie Qwen/Qwen3-4B-Instruct-2507                           # faster 4B model (1.5–3 h)
rollie meta-llama/Llama-3.1-8B-Instruct --quant Q5_K_M      # custom quant
rollie google/gemma-3-12b-it --skip-import                   # GGUF only, no Ollama import
rollie Qwen/Qwen3-8B-Instruct --finetune ~/datasets/mydata/  # abliterate then fine-tune

# Standalone fine-tune
rollie finetune Qwen/Qwen3-4B-Instruct-2507 --data ~/datasets/mydata/
rollie finetune ~/local/model/ --data ~/datasets/mydata/ --iters 500

# Dataset curation
rollie curate --persona ./persona.md --output ~/datasets/mydata/
rollie curate --code ~/myproject/ --output ~/datasets/
rollie curate --repo https://github.com/org/lib --output ~/datasets/
rollie curate --files ~/docs/ --output ~/datasets/
rollie curate --db sqlite:///mydb.db --output ~/datasets/
rollie curate --code ~/project/ --files ~/docs/ --output ~/datasets/stack/  # compose

# Config
rollie --set-data-curation-model       # pick Ollama model for curate
rollie --set-finetune-defaults         # set LoRA iters/layers/rank

# Management
rollie --list                          # list rollie models in Ollama
rollie --status                        # workspace + config overview
rollie --clean qwen3-8b-instruct       # remove workspace files for a model
rollie --logs qwen3-8b-instruct        # tail the run log
rollie --help                          # show all commands
```

Gate-locked models (Llama 3.x, Gemma) require a one-time login before first use:

```fish
huggingface-cli login
```

---

## File locations

| Path | Purpose |
|---|---|
| `~/.config/fish/functions/rollie.fish` | The installed function |
| `~/.config/fish/rollie-scripts/` | Python curate scripts (installed by setup.fish) |
| `~/.config/rollie/data_curation_model` | Persisted Ollama model name for `rollie curate` |
| `~/.config/rollie/finetune_defaults` | Persisted LoRA hyperparameters (`iters=N`, `num_layers=N`, `lora_rank=N`) |
| `~/.config/rollie/codebase_extensions` | Optional extension whitelist override (one per line) |
| `~/rollie-workspace/` | Pipeline workspace root |
| `~/rollie-workspace/models/abliterated/` | Heretic output (HF format) |
| `~/rollie-workspace/models/base/` | Downloaded base models for standalone finetune |
| `~/rollie-workspace/models/adapters/` | LoRA adapter outputs |
| `~/rollie-workspace/models/merged/` | Adapter-fused model outputs |
| `~/rollie-workspace/models/gguf/` | Final GGUF files and Modelfiles |
| `~/rollie-workspace/datasets/` | Default output dir for `rollie curate` |
| `~/rollie-workspace/envs/heretic/` | uv venv for heretic |
| `~/rollie-workspace/envs/convert/` | uv venv for GGUF conversion |
| `~/rollie-workspace/envs/mlx/` | uv venv for MLX fine-tuning (opt-in) |
| `~/rollie-workspace/envs/curate/` | uv venv for dataset curation (opt-in) |
| `~/rollie-workspace/logs/` | Per-model run logs (`<slug>.log`) |

---

## Model naming

The Ollama model name is derived from the HuggingFace model ID:

| HF ID | Slug | Ollama name |
|---|---|---|
| `Qwen/Qwen3-8B-Instruct` | `qwen3-8b-instruct` | `qwen3-8b-instruct-heretic` |
| `meta-llama/Llama-3.1-8B-Instruct` | `llama-3-1-8b-instruct` | `llama-3-1-8b-instruct-heretic` |

The slug is the part after `/`, lowercased, with non-alphanumeric runs replaced by `-`.

---

## Recommended models

| Model | HF ID | Notes |
|---|---|---|
| Qwen3-4B | `Qwen/Qwen3-4B-Instruct-2507` | Fastest — 1.5–3 h |
| Qwen3-8B | `Qwen/Qwen3-8B-Instruct` | Best capability/time balance — 3–5 h |
| Llama 3.1 8B | `meta-llama/Llama-3.1-8B-Instruct` | Heretic's benchmark model — 3–5 h |
| Gemma 3 9B | `google/gemma-3-9b-it` | Strong reasoning — 3–5 h |
| Gemma 3 12B | `google/gemma-3-12b-it` | Run overnight — 6–10 h |

**Avoid:** Qwen3.5 — hybrid Mamba2+Transformer architecture, not supported by heretic.

---

## Notes for agents

- **Do not modify `CLAUDE.md` without also updating `setup.fish` and `rollie.fish`** if the change affects pipeline steps or file locations.
- The function is self-contained in `rollie.fish`. All workspace paths are defined at the top of the `rollie` function body.
- `setup.fish` is idempotent — safe to re-run at any time.
- Fish nested functions (`_rollie_*` helpers) are defined inside the outer `rollie` function to avoid polluting the global namespace.
- The `convert_hf_to_gguf.py` script is downloaded during setup, version-matched to the installed `llama-quantize`. If `llama-quantize` is upgraded via brew, re-run `setup.fish` to refresh the script.
- The heretic env uses `VIRTUAL_ENV` + `PATH` injection rather than `source activate` — this is intentional for fish compatibility.

---

## Backlog

Planned work lives in [`BACKLOG.md`](./BACKLOG.md). It is the authoritative source for what needs doing in this repo.

### Agent workflow for backlog tasks

1. **Read `BACKLOG.md` first.** Before starting any work session, scan for `[PLANNED]` or `[IN PROGRESS]` tasks relevant to the work being requested.
2. **Claim the task.** Change its status to `[IN PROGRESS]` and update the `Updated` date before touching any code.
3. **Follow the implementation notes.** Each task includes specific file locations, known edge cases, and decisions already made.
4. **Mark done and move.** When complete, change status to `[DONE]` and move the task block to the `## Completed` section.
5. **Add new tasks as discovered.** If work reveals a new bug or improvement, add it to `BACKLOG.md` with the next sequential ID.
