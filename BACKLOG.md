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

### [PLANNED] Clean up partial output on interrupted abliteration (#ROLLIE-3)

- **ID**: ROLLIE-3
- **Type**: bug
- **Priority**: high
- **Effort**: small
- **Added**: 2026-05-01
- **Updated**: 2026-05-01
- **Author**: agent

#### Problem / Motivation

If the user presses Ctrl-C during the heretic stage, the abliterated output directory is created but contains incomplete model files. On the next run, the pipeline sees the directory exists and skips heretic entirely — serving a corrupt model through the rest of the pipeline.

The same issue applies (less critically) if the GGUF conversion step is interrupted: the partial `.gguf` file is left on disk and will be mistaken for a complete file on resumption.

#### Proposed Solution

Add a sentinel file (e.g. `$ABL_DIR/.rollie_complete`) that is written only after heretic exits successfully. The resumption check should test for the sentinel, not just the directory. If the directory exists without the sentinel, warn the user and prompt to re-run heretic or clean the partial output.

Same approach for the GGUF file: write a sentinel `$GGUF_FINAL.ok` after `llama-quantize` succeeds; check for the sentinel rather than the file.

#### Implementation Notes

- **rollie.fish, abliterate stage (~line where ABL_DIR check is)**:
  Replace `test -d "$ABL_DIR"` with `test -f "$ABL_DIR/.rollie_complete"`.
  After heretic succeeds, write `touch "$ABL_DIR/.rollie_complete"`.
  If directory exists but sentinel is missing, show a warning and prompt:
  `rm -rf "$ABL_DIR" and rerun heretic? [y/N]`

- **rollie.fish, GGUF stage (~line where GGUF_FINAL check is)**:
  Replace `test -f "$GGUF_FINAL"` with `test -f "$GGUF_FINAL.ok"`.
  After `llama-quantize` succeeds, write `touch "$GGUF_FINAL.ok"`.
  If GGUF exists without sentinel, warn and offer to re-quantize.

- The `--clean` command already deletes the whole directory and `.gguf` files —
  also add `rm -f "$GGUF_FINAL.ok"` there.

#### Acceptance Criteria

- [ ] Interrupting heretic mid-run and rerunning does not silently skip to conversion
- [ ] Interrupted heretic triggers a warning + prompt to clean and retry
- [ ] Interrupting GGUF quantization and rerunning triggers a re-quantize, not a skip
- [ ] `--clean` removes sentinels alongside other files
- [ ] Fully completed runs are still correctly detected as resumable

---

### [PLANNED] Fine-tuning support via MLX-LM (#ROLLIE-1)

- **ID**: ROLLIE-1
- **Type**: feature
- **Priority**: medium
- **Effort**: large
- **Added**: 2026-05-01
- **Updated**: 2026-05-01
- **Author**: agent

#### Problem / Motivation

The current pipeline produces an abliterated model with no domain-specific fine-tuning. The design brief includes a fine-tuning stage using MLX-LM (Apple's native ML framework) to apply LoRA adapters after abliteration.

#### Proposed Solution

Add an optional `--finetune <dataset-dir>` flag to `rollie`. When supplied, insert a MLX-LM LoRA training step between abliteration and GGUF conversion. The adapter is stored in the workspace and merged into the base before conversion.

Because MLX-LM fine-tuning requires a user-supplied dataset, this flag is explicitly opt-in and documented as requiring dataset preparation outside of rollie.

#### Implementation Notes

- New env: `~/rollie-workspace/envs/mlx/` with `mlx-lm` installed
- Add to `setup.fish` as an optional step (prompt user, skip if declined)
- New workspace dir: `~/rollie-workspace/models/adapters/<slug>/`
- Pipeline with `--finetune`:
  1. Abliterate (existing)
  2. Fine-tune: `mlx_lm.lora --model $ABL_DIR --train --data <dataset-dir> --adapter-path $ADAPTERS_DIR/$SLUG`
  3. Merge: `mlx_lm.fuse --model $ABL_DIR --adapter-path $ADAPTERS_DIR/$SLUG --save-path $MERGED_DIR/$SLUG`
  4. Convert (existing, using merged dir)
  5. Quantize + import (existing)
- The merged dir replaces `$ABL_DIR` as the input to the convert stage when `--finetune` is used
- Dataset format (JSONL, ChatML): document clearly in `--help` output and README
- LoRA hyperparameters: expose `--lora-iters` and `--lora-layers` flags with sensible defaults (iters=1000, layers=16)

#### Open Questions (answer before implementing)

- What is the intended use case / domain for fine-tuning? This determines dataset format and LoRA rank.
- Should `mlx_lm.fuse` (merge without mergekit) suffice, or is mergekit needed for more complex merge recipes?

#### Acceptance Criteria

- [ ] `rollie <hf-id> --finetune ~/my-dataset/` runs the full 5-stage pipeline
- [ ] `--finetune` without `--dataset` (or with a missing dir) fails with a clear error
- [ ] Fine-tuned adapter is preserved in workspace for inspection
- [ ] `--skip-import` still works when combined with `--finetune`
- [ ] `--clean` removes adapter and merged dirs alongside other workspace files
- [ ] `setup.fish` offers optional MLX env install
- [ ] `--help` output documents dataset format and hyperparameter flags

#### Dependencies

- ROLLIE-3 (sentinel files) should land first — fine-tuning adds another interruptible stage
- User must supply a training dataset; format guidance documented in README

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
