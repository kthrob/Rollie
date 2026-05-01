# rollie — Backlog

<!--
AGENT INSTRUCTIONS — READ THIS BEFORE MODIFYING THIS FILE
──────────────────────────────────────────────────────────
This file is the shared backlog for rollie. It is read and written by both
humans and AI agents. Follow these rules exactly.

## Task format

Each task is a level-3 heading followed by a metadata block, a description,
and optional sections. The full schema:

```
### [STATUS] Short imperative title (#ID)

- **ID**: ROLLIE-N          (increment from last used ID)
- **Type**: bug | feature | improvement | refactor
- **Priority**: high | medium | low
- **Effort**: small | medium | large
- **Added**: YYYY-MM-DD
- **Updated**: YYYY-MM-DD
- **Author**: name or "agent"

#### Problem / Motivation
Why this needs doing.

#### Proposed Solution
What to build and how.

#### Implementation Notes
Specific code locations, edge cases, decisions already made.

#### Acceptance Criteria
- [ ] Checkable outcomes that define "done"

#### Dependencies
Other tasks or external requirements this depends on.
```

## Status values

- `[PLANNED]`     — approved, not yet started
- `[IN PROGRESS]` — actively being worked on (update the file to reflect this)
- `[BLOCKED]`     — waiting on something external
- `[DONE]`        — completed (move to ## Completed section, keep for reference)
- `[REJECTED]`    — decided not to do; leave a brief reason

## Rules for agents

1. Before starting a task, change its status to `[IN PROGRESS]` and update
   the **Updated** date.
2. When complete, change status to `[DONE]`, fill in any relevant outcomes,
   and move the entire task block to the ## Completed section.
3. Never delete a task — use `[REJECTED]` with a reason instead.
4. When adding a new task, assign the next sequential ID (check the highest
   existing ID first).
5. Keep the Planned section sorted by Priority (high → medium → low), then
   by Added date within the same priority.
6. Update **Updated** date whenever you edit a task, even just to add a note.
-->

---

## Planned

---

### [PLANNED] mergekit integration for advanced model merging (#ROLLIE-2)

- **ID**: ROLLIE-2
- **Type**: feature
- **Priority**: low
- **Effort**: medium
- **Added**: 2026-05-01
- **Updated**: 2026-05-01
- **Author**: agent

#### Problem / Motivation

`mlx_lm.fuse` covers simple LoRA merges into the base model. For more advanced merge recipes (SLERP, TIES, DARE), mergekit is the standard tool. The design brief includes mergekit as Stage 3 of the full pipeline.

#### Proposed Solution

Add a `--merge-config <path>` flag that accepts a mergekit YAML recipe. When supplied, mergekit runs between abliteration and GGUF conversion using the recipe to produce the merged model. This is a power-user feature; the default pipeline (no flags) stays unchanged.

#### Implementation Notes

- New env: `~/rollie-workspace/envs/mergekit/` with `mergekit` installed
- mergekit runs on CPU, no GPU needed
- Input to mergekit: abliterated model dir (and any other models specified in the recipe)
- Output: `~/rollie-workspace/models/merged/<slug>/`
- The merged dir replaces `$ABL_DIR` as convert stage input
- Example recipe in README for simple base+adapter merge (the common case)

#### Acceptance Criteria

- [ ] `rollie <hf-id> --merge-config configs/my-merge.yaml` runs mergekit after abliteration
- [ ] Missing config file fails with a clear error pointing to example recipe
- [ ] `--clean` removes merged dir
- [ ] `setup.fish` offers optional mergekit env install
- [ ] Example `configs/example-merge.yaml` committed to repo

#### Dependencies

- ROLLIE-1 (fine-tuning) — mergekit is most useful as an alternative merge path to `mlx_lm.fuse`; implement after ROLLIE-1 to avoid overlapping scope

---

## Completed

<!-- Completed tasks are moved here. Keep them for reference. -->

### [DONE] MLX-LM fine-tuning support (#ROLLIE-1)

- **ID**: ROLLIE-1
- **Type**: feature
- **Priority**: high
- **Effort**: medium
- **Added**: 2026-05-01
- **Updated**: 2026-04-30
- **Author**: agent

#### Problem / Motivation

The pipeline produced an abliterated model with no fine-tuning. The user wanted composable training: fine-tune standalone (no abliteration) or chain finetune onto the abliterate pipeline.

#### Solution implemented

- `rollie finetune <model> --data <dir>` — standalone subcommand; downloads HF model if needed, runs `mlx_lm.lora` then `mlx_lm.fuse`, then convert/quantize/import
- `rollie <hf-id> --finetune <dir>` — chains fine-tuning after abliteration
- Shared `_rollie_gguf_pipeline` helper eliminates code duplication between both paths
- Sentinel files: `.rollie_finetune_complete` and `.rollie_merge_complete` for resumability
- `--clean` extended to remove `base/`, `adapters/`, `merged/` dirs
- Opt-in MLX env in `setup.fish`; config defaults from ROLLIE-5

#### Acceptance Criteria

- [x] `rollie finetune <hf-id> --data <dir>` runs end-to-end
- [x] `rollie finetune <local-path> --data <dir>` works with a local model dir
- [x] `rollie <hf-id> --finetune <dir>` chains correctly after abliteration
- [x] Defaults from `~/.config/rollie/finetune_defaults` are picked up; inline flags override
- [x] Adapter and merged dirs are preserved for inspection
- [x] `--clean <slug>` removes adapter + merged dirs
- [x] `setup.fish` offers optional MLX env install
- [x] `--skip-import` still works when chained
- [x] `--help` documents dataset format and hyperparameter flags

---

### [DONE] Dataset curation module (#ROLLIE-4)

- **ID**: ROLLIE-4
- **Type**: feature
- **Priority**: high
- **Effort**: large
- **Added**: 2026-05-01
- **Updated**: 2026-04-30
- **Author**: agent

#### Problem / Motivation

Fine-tuning needs training data. The user wanted rollie to generate ChatML JSONL datasets from real source material using a local Ollama model, with a persona mode for style/voice training.

#### Solution implemented

- `rollie curate` subcommand dispatching to Python scripts in `~/.config/fish/rollie-scripts/`
- Sources: `--code` (codebase + AST chunking), `--repo` (shallow clone), `--db` (SQLite/PostgreSQL), `--files` (PDF/DOCX/MD/TXT), `--persona` (agency-agents format)
- Q&A generation via `scripts/qa_generator.py` (POST /api/chat)
- Quality pass via `scripts/quality_pass.py` (second Ollama call, 1–5 rating, configurable threshold)
- Output: ChatML JSONL `{"text": "<|im_start|>user\n...<|im_end|>\n<|im_start|>assistant\n...<|im_end|>"}`
- Opt-in curate env in `setup.fish`

#### Acceptance Criteria

- [x] `rollie curate --persona ./test-persona.md --output ./test-out/` produces valid ChatML JSONL
- [x] `rollie curate --code <path>` ingests respecting .gitignore, chunks by AST when possible
- [x] `rollie curate --repo <url>` shallow-clones and ingests (code + docs only)
- [x] `rollie curate --db sqlite:///test.db` extracts schema + samples and emits Q&A
- [x] `rollie curate --db postgresql://...` works with PostgreSQL
- [x] `rollie curate --files <path>` handles PDF, DOCX, MD, TXT
- [x] Composing multiple sources merges into one JSONL
- [x] Quality pass filters at the configured threshold; `--no-quality-pass` skips
- [ ] Resumable: per-chunk sentinels not yet implemented (full re-run needed; follow-up task)
- [x] `setup.fish` offers optional curate env install
- [x] `--help` documents all source flags and the dataset format

---

### [DONE] Config commands and curate model picker (#ROLLIE-5)

- **ID**: ROLLIE-5
- **Type**: feature
- **Priority**: high
- **Effort**: small
- **Added**: 2026-05-01
- **Updated**: 2026-04-30
- **Author**: agent

#### Problem / Motivation

The curate module needs a configured Ollama model to call for Q&A generation, and the finetune module needs sensible default hyperparameters. Both should be persistent settings so the user doesn't have to pass them every run.

#### Solution implemented

- Config dir: `~/.config/rollie/` (created on first use)
- `~/.config/rollie/data_curation_model` — persisted model name
- `~/.config/rollie/finetune_defaults` — `iters=N`, `num_layers=N`, `lora_rank=N`
- `_rollie_local_models` helper starts/stops ollama as needed, mirrors llamy pattern
- `_rollie_curation_model` and `_rollie_finetune_defaults` helpers read config with defaults
- `--status` extended with Environments and Config sections

#### Acceptance Criteria

- [x] `rollie --set-data-curation-model` shows installed Ollama models, persists choice
- [x] `rollie --set-finetune-defaults` prompts for and persists iters/layers/rank
- [x] `rollie --status` shows both settings (or "not set" if absent)
- [x] `rollie --help` documents both flags
- [x] If no Ollama models installed, `--set-data-curation-model` shows a clear error pointing at `ollama pull`

---

### [DONE] Clean up partial output on interrupted abliteration (#ROLLIE-3)

- **ID**: ROLLIE-3
- **Type**: bug
- **Priority**: high
- **Effort**: small
- **Added**: 2026-05-01
- **Updated**: 2026-05-01
- **Author**: agent

#### Problem / Motivation

If the user presses Ctrl-C during heretic, the abliterated output directory is created but contains incomplete model files. On the next run the pipeline saw the directory and silently skipped heretic — feeding a corrupt model into conversion. Same problem for an interrupted GGUF quantization step leaving a partial `.gguf` file.

#### Solution implemented

Added sentinel files written only after each stage exits successfully:

- `$ABL_DIR/.rollie_complete` — written after heretic succeeds
- `$GGUF_FINAL.ok` — written after `llama-quantize` succeeds

Resumption checks test for the sentinel, not the directory/file. If the directory/file exists without its sentinel, the user is warned and prompted to remove the partial output and retry. `--clean` removes sentinels alongside other workspace files.

#### Acceptance Criteria

- [x] Interrupting heretic mid-run and rerunning does not silently skip to conversion
- [x] Interrupted heretic triggers a warning + prompt to clean and retry
- [x] Interrupting GGUF quantization and rerunning triggers a re-quantize, not a skip
- [x] `--clean` removes sentinels alongside other files
- [x] Fully completed runs are still correctly detected as resumable
