# rollie

## Purpose

This repository provides `rollie` — a fish shell function for macOS (Apple Silicon) that automates the heretic abliteration pipeline with a single command. It downloads an open-weight model from HuggingFace, strips its refusal training using [heretic](https://github.com/p-e-w/heretic), converts it to GGUF format, and imports it into Ollama — ready to use with `llamy` or directly via `ollama run`.

The entire pipeline runs locally on-device. No cloud GPU required.

### What's in this repo

| File | Description |
|---|---|
| `rollie.fish` | The fish function — this is the main deliverable |
| `setup.fish` | Installer: checks/installs dependencies, sets up Python envs, copies `rollie.fish` |
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

| Stage | Tool | What it does |
|---|---|---|
| 1. Abliterate | `heretic` (uv env) | Downloads model from HF, removes refusal direction from weights |
| 2. Convert | `convert_hf_to_gguf.py` (uv env) | Converts HF safetensors → GGUF F16 |
| 3. Quantize | `llama-quantize` (Homebrew) | Quantizes F16 GGUF → Q4_K_M (or custom) |
| 4. Import | `ollama create` | Imports GGUF into Ollama as `<slug>-heretic` |

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
rollie Qwen/Qwen3-8B-Instruct          # full pipeline (3–5 h on M1)
rollie Qwen/Qwen3-4B-Instruct-2507     # faster 4B model (1.5–3 h)
rollie meta-llama/Llama-3.1-8B-Instruct --quant Q5_K_M   # custom quant
rollie google/gemma-3-12b-it --skip-import               # GGUF only, no Ollama import
rollie --list                          # list rollie models in Ollama
rollie --status                        # workspace overview
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
| `~/rollie-workspace/` | Pipeline workspace root |
| `~/rollie-workspace/models/abliterated/` | Heretic output (HF format) |
| `~/rollie-workspace/models/gguf/` | Final GGUF files and Modelfiles |
| `~/rollie-workspace/envs/heretic/` | uv venv for heretic |
| `~/rollie-workspace/envs/convert/` | uv venv for GGUF conversion |
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
