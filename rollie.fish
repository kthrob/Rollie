# ~/.config/fish/functions/rollie.fish
#
# Usage:
#   rollie <hf-model-id>                      Full pipeline: abliterate → GGUF → Ollama
#   rollie <hf-model-id> --quant Q5_K_M       Custom quantization
#   rollie <hf-model-id> --skip-import        Stop at GGUF; skip Ollama import
#   rollie <hf-model-id> --finetune <dir>     Chain finetune after abliteration
#   rollie finetune <model> --data <dir>      Standalone fine-tune (no abliteration)
#   rollie --list                             List rollie models in Ollama
#   rollie --status                           Workspace status and disk usage
#   rollie --clean <slug>                     Delete workspace files for a model
#   rollie --logs [slug]                      Tail the log for a run
#   rollie --help                             Show all commands

function rollie --description "Abliterate a HuggingFace model and import to Ollama"

    set WORKSPACE           "$HOME/rollie-workspace"
    set LOG_DIR             "$WORKSPACE/logs"
    set HERETIC_ENV         "$WORKSPACE/envs/heretic"
    set CONVERT_ENV         "$WORKSPACE/envs/convert"
    set CONFIG_DIR          "$HOME/.config/rollie"
    set CURATION_MODEL_FILE "$CONFIG_DIR/data_curation_model"
    set FINETUNE_DEFAULTS_FILE "$CONFIG_DIR/finetune_defaults"
    set SCRIPTS_DIR         "$HOME/.config/fish/rollie-scripts"

    # ── helpers ────────────────────────────────────────────────────────────────

    function _rollie_info
        echo (set_color cyan)"[rollie]"(set_color normal) $argv
    end
    function _rollie_ok
        echo (set_color green)"[rollie] ✓"(set_color normal) $argv
    end
    function _rollie_err
        echo (set_color red)"[rollie]"(set_color normal) $argv >&2
    end
    function _rollie_warn
        echo (set_color yellow)"[rollie]"(set_color normal) $argv
    end

    function _rollie_slug --argument-names hf_id
        # Qwen/Qwen3-8B-Instruct → qwen3-8b-instruct
        echo $hf_id \
            | string lower \
            | string replace -r '^[^/]+/' '' \
            | string replace -ra '[^a-z0-9]+' '-' \
            | string trim -c '-'
    end

    function _rollie_check_deps
        set _ok 1
        if not test -d "$HERETIC_ENV"
            _rollie_err "Heretic env not found — run: fish setup.fish"
            set _ok 0
        end
        if not test -f "$CONVERT_ENV/bin/convert_hf_to_gguf.py"
            _rollie_err "GGUF converter not found — run: fish setup.fish"
            set _ok 0
        end
        if not command -q llama-quantize
            _rollie_err "llama-quantize not found — run: brew install llama.cpp"
            set _ok 0
        end
        if not command -q ollama
            _rollie_err "ollama not found — run: brew install ollama"
            set _ok 0
        end
        return (math 1 - $_ok)
    end

    function _rollie_wait_for_ollama
        set _attempts 0
        while test $_attempts -lt 10
            if curl -sf "http://localhost:11434" > /dev/null 2>&1
                return 0
            end
            sleep 1
            set _attempts (math $_attempts + 1)
        end
        return 1
    end

    # List installed Ollama models. Starts ollama serve briefly if not running,
    # then kills it. Mirrors llamy's _llamy_local_models pattern.
    function _rollie_local_models
        set _started 0
        if not pgrep -x ollama > /dev/null
            ollama serve > /dev/null 2>&1 &
            set _tmp_pid $last_pid
            set _started 1
            if not _rollie_wait_for_ollama
                kill $_tmp_pid 2>/dev/null
                return 1
            end
        end

        set _models (ollama list 2>/dev/null | tail -n +2 | awk '{print $1}')

        if test $_started -eq 1
            kill $_tmp_pid 2>/dev/null
        end

        printf "%s\n" $_models
    end

    function _rollie_curation_model
        if test -f "$CURATION_MODEL_FILE"
            string trim -- (cat "$CURATION_MODEL_FILE" 2>/dev/null)
        end
    end

    # Read finetune defaults; output three lines: iters, num_layers, lora_rank
    function _rollie_finetune_defaults
        set _iters 1000
        set _layers 16
        set _rank 8
        if test -f "$FINETUNE_DEFAULTS_FILE"
            for _line in (cat "$FINETUNE_DEFAULTS_FILE" 2>/dev/null)
                set _line (string trim -- $_line)
                set _key (string split -m 1 '=' -- $_line)[1]
                set _val (string split -m 1 '=' -- $_line)[2]
                switch $_key
                    case iters
                        test -n "$_val" && set _iters $_val
                    case num_layers
                        test -n "$_val" && set _layers $_val
                    case lora_rank
                        test -n "$_val" && set _rank $_val
                end
            end
        end
        echo $_iters
        echo $_layers
        echo $_rank
    end

    # ── --help ─────────────────────────────────────────────────────────────────

    if test (count $argv) -eq 0 -o "$argv[1]" = "--help" -o "$argv[1]" = "-h"
        echo ""
        echo (set_color --bold)"rollie"(set_color normal)" — abliterate HuggingFace models, fine-tune, and import to Ollama"
        echo ""
        echo (set_color --bold)"USAGE"(set_color normal)
        echo "  rollie <hf-model-id>                       Full pipeline: abliterate → GGUF → Ollama"
        echo "  rollie <hf-model-id> --finetune <dir>      Chain finetune after abliteration"
        echo "  rollie finetune <model> --data <dir>       Standalone fine-tune (no abliteration)"
        echo "  rollie curate [source flags] ...           Generate a ChatML JSONL training dataset"
        echo ""
        echo (set_color --bold)"PIPELINE OPTIONS"(set_color normal)
        printf "  %-36s %s\n" "--quant <type>"                   "GGUF quant type (default: Q4_K_M)"
        printf "  %-36s %s\n" "--skip-import"                    "Stop at GGUF; skip Ollama import"
        printf "  %-36s %s\n" "--finetune <dataset-dir>"         "Fine-tune after abliteration"
        echo ""
        echo (set_color --bold)"FINETUNE OPTIONS (rollie finetune)"(set_color normal)
        printf "  %-36s %s\n" "--data <dataset-dir>"             "Directory containing data.jsonl"
        printf "  %-36s %s\n" "--iters <N>"                      "Training iterations (default from config)"
        printf "  %-36s %s\n" "--layers <N>"                     "Number of LoRA layers (default from config)"
        printf "  %-36s %s\n" "--rank <N>"                       "LoRA rank (default from config)"
        printf "  %-36s %s\n" "--lr <float>"                     "Learning rate (default: 1e-5)"
        echo ""
        echo (set_color --bold)"CURATE OPTIONS (rollie curate)"(set_color normal)
        printf "  %-36s %s\n" "--code <path>"                    "Ingest a local codebase"
        printf "  %-36s %s\n" "--repo <github-url>"              "Shallow-clone and ingest a GitHub repo"
        printf "  %-36s %s\n" "--db <connection-string>"         "Ingest a SQLite or PostgreSQL database"
        printf "  %-36s %s\n" "--files <path>"                   "Ingest PDF, DOCX, MD, or TXT files"
        printf "  %-36s %s\n" "--persona <persona.md>"           "Generate persona/style conversations"
        printf "  %-36s %s\n" "--output <dir>"                   "Output dir (default: workspace/datasets/)"
        printf "  %-36s %s\n" "--per-chunk <N>"                  "Q&A pairs per chunk (default: 5)"
        printf "  %-36s %s\n" "--quality-threshold <N>"          "Min quality score 1–5 (default: 3)"
        printf "  %-36s %s\n" "--no-quality-pass"                "Skip quality filtering for speed"
        echo ""
        echo (set_color --bold)"MANAGEMENT"(set_color normal)
        printf "  %-36s %s\n" "--list"                           "List rollie models in Ollama"
        printf "  %-36s %s\n" "--status"                         "Workspace status, config, disk usage"
        printf "  %-36s %s\n" "--clean <slug>"                   "Delete workspace files for a model"
        printf "  %-36s %s\n" "--logs [slug]"                    "Tail a run log (latest if omitted)"
        printf "  %-36s %s\n" "--set-data-curation-model"        "Pick Ollama model for 'rollie curate'"
        printf "  %-36s %s\n" "--set-finetune-defaults"          "Set default LoRA iters, layers, rank"
        printf "  %-36s %s\n" "--help, -h"                       "Show this help"
        echo ""
        echo (set_color --bold)"EXAMPLES"(set_color normal)
        echo "  rollie Qwen/Qwen3-8B-Instruct"
        echo "  rollie meta-llama/Llama-3.1-8B-Instruct --quant Q5_K_M"
        echo "  rollie Qwen/Qwen3-8B-Instruct --finetune ~/datasets/mydata/"
        echo "  rollie finetune Qwen/Qwen3-4B-Instruct-2507 --data ~/datasets/mydata/"
        echo "  rollie curate --persona ./persona.md --output ~/datasets/mydata/"
        echo "  rollie curate --code ~/myproject/ --files ~/docs/ --output ~/datasets/stack/"
        echo "  rollie --clean qwen3-8b-instruct"
        echo "  rollie --logs qwen3-8b-instruct"
        echo ""
        echo (set_color --bold)"RECOMMENDED MODELS"(set_color normal)
        printf "  %-45s %s\n" "Qwen/Qwen3-4B-Instruct-2507"           "Fastest — 1.5–3 h"
        printf "  %-45s %s\n" "Qwen/Qwen3-8B-Instruct"                "Best balance — 3–5 h"
        printf "  %-45s %s\n" "meta-llama/Llama-3.1-8B-Instruct"      "Well-tested — 3–5 h"
        printf "  %-45s %s\n" "google/gemma-3-9b-it"                  "Strong reasoning — 3–5 h"
        printf "  %-45s %s\n" "google/gemma-3-12b-it"                 "Overnight — 6–10 h"
        echo ""
        echo (set_color --bold)"NOTES"(set_color normal)
        echo "  • Gate-locked models (Llama 3.x, Gemma) require HuggingFace login first:"
        echo "    huggingface-cli login"
        echo "  • The pipeline is resumable — rerun the same command to continue"
        echo "    from where it left off (each stage checks for existing output)."
        echo "  • Avoid Qwen3.5 — hybrid Mamba2+Transformer, not supported by heretic."
        echo "  • 12B+ models: pass --quant bnb_4bit to heretic via a custom run;"
        echo "    the default pipeline targets 4B–9B models comfortably in 32GB."
        echo ""
        echo (set_color --bold)"FILES"(set_color normal)
        printf "  %-44s %s\n" "$WORKSPACE/models/abliterated/" "Heretic output"
        printf "  %-44s %s\n" "$WORKSPACE/models/gguf/"        "Final GGUF files"
        printf "  %-44s %s\n" "$LOG_DIR/"                      "Per-model run logs"
        echo ""
        return 0
    end

    # ── --list ─────────────────────────────────────────────────────────────────

    if test "$argv[1]" = "--list"
        set _models (ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -- '-heretic$')
        if test (count $_models) -eq 0
            _rollie_info "No rollie models in Ollama yet."
        else
            echo ""
            echo (set_color --bold)"Rollie models in Ollama:"(set_color normal)
            for m in $_models
                echo "  • $m"
            end
            echo ""
        end
        return 0
    end

    # ── --status ───────────────────────────────────────────────────────────────

    if test "$argv[1]" = "--status"
        echo ""
        echo (set_color --bold)"Workspace: $WORKSPACE"(set_color normal)
        echo ""

        if not test -d "$WORKSPACE"
            _rollie_warn "Workspace not initialized — run: fish setup.fish"
            return 0
        end

        set _abl_dir "$WORKSPACE/models/abliterated"
        if test -d "$_abl_dir"
            set _abls (find "$_abl_dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)
            if test (count $_abls) -gt 0
                echo (set_color --bold)"Abliterated:"(set_color normal)
                for s in $_abls
                    set _sz (du -sh "$s" 2>/dev/null | awk '{print $1}')
                    echo "  • "(basename "$s")"  ($_sz)"
                end
                echo ""
            end
        end

        set _gguf_dir "$WORKSPACE/models/gguf"
        if test -d "$_gguf_dir"
            set _ggufs (find "$_gguf_dir" -maxdepth 1 -name '*.gguf' -type f 2>/dev/null | sort)
            if test (count $_ggufs) -gt 0
                echo (set_color --bold)"GGUF files:"(set_color normal)
                for f in $_ggufs
                    set _sz (du -sh "$f" 2>/dev/null | awk '{print $1}')
                    echo "  • "(basename "$f")"  ($_sz)"
                end
                echo ""
            end
        end

        set _rollie_models (ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -- '-heretic$')
        if test (count $_rollie_models) -gt 0
            echo (set_color --bold)"In Ollama:"(set_color normal)
            for m in $_rollie_models
                echo "  • $m"
            end
            echo ""
        end

        echo (set_color --bold)"Environments:"(set_color normal)
        for env_name in heretic convert mlx curate
            if test -d "$WORKSPACE/envs/$env_name"
                echo "  ✓ $env_name"
            else
                echo "  ✗ $env_name  (not installed)"
            end
        end
        echo ""

        echo (set_color --bold)"Config:"(set_color normal)
        set _curation_model (_rollie_curation_model)
        if test -n "$_curation_model"
            echo "  • Curation model:  $_curation_model"
        else
            echo "  • Curation model:  (not set — run: rollie --set-data-curation-model)"
        end
        set _ft_defaults (_rollie_finetune_defaults)
        echo "  • Finetune:        iters=$_ft_defaults[1], layers=$_ft_defaults[2], rank=$_ft_defaults[3]"
        echo ""
        return 0
    end

    # ── --set-data-curation-model ─────────────────────────────────────────────

    if test "$argv[1]" = "--set-data-curation-model"
        set _models (_rollie_local_models)
        if test (count $_models) -eq 0
            _rollie_err "No Ollama models installed. Pull one first, e.g.:"
            _rollie_err "  ollama pull qwen2.5-coder:latest"
            return 1
        end

        set _current (_rollie_curation_model)

        echo ""
        echo (set_color --bold)"Pick the model 'rollie curate' will use for Q&A generation:"(set_color normal)
        for i in (seq (count $_models))
            if test "$_models[$i]" = "$_current"
                echo (set_color yellow)"  $i) $_models[$i]  ✓ current"(set_color normal)
            else
                echo "  $i) $_models[$i]"
            end
        end
        echo ""

        while true
            read --prompt-str (set_color cyan)"[rollie]"(set_color normal)" Select (1-"(count $_models)"): " _choice
            if string match -qr '^\d+$' -- $_choice
                and test $_choice -ge 1
                and test $_choice -le (count $_models)
                break
            end
            _rollie_err "Please enter a number between 1 and "(count $_models)"."
        end

        set _selected $_models[$_choice]
        mkdir -p $CONFIG_DIR
        echo $_selected > $CURATION_MODEL_FILE
        _rollie_ok "Curation model set to: $_selected"
        return 0
    end

    # ── --set-finetune-defaults ───────────────────────────────────────────────

    if test "$argv[1]" = "--set-finetune-defaults"
        set _defaults (_rollie_finetune_defaults)
        set _cur_iters $_defaults[1]
        set _cur_layers $_defaults[2]
        set _cur_rank $_defaults[3]

        echo ""
        echo (set_color --bold)"Set default LoRA fine-tuning hyperparameters."(set_color normal)
        echo "Press Enter to keep the current value."
        echo ""

        read --prompt-str (set_color cyan)"[rollie]"(set_color normal)" iters [$_cur_iters]: " _iters
        test -z "$_iters" && set _iters $_cur_iters
        if not string match -qr '^\d+$' -- $_iters
            _rollie_err "iters must be a positive integer."
            return 1
        end

        read --prompt-str (set_color cyan)"[rollie]"(set_color normal)" num_layers [$_cur_layers]: " _layers
        test -z "$_layers" && set _layers $_cur_layers
        if not string match -qr '^\d+$' -- $_layers
            _rollie_err "num_layers must be a positive integer."
            return 1
        end

        read --prompt-str (set_color cyan)"[rollie]"(set_color normal)" lora_rank [$_cur_rank]: " _rank
        test -z "$_rank" && set _rank $_cur_rank
        if not string match -qr '^\d+$' -- $_rank
            _rollie_err "lora_rank must be a positive integer."
            return 1
        end

        mkdir -p $CONFIG_DIR
        printf "iters=%s\nnum_layers=%s\nlora_rank=%s\n" $_iters $_layers $_rank > $FINETUNE_DEFAULTS_FILE
        _rollie_ok "Finetune defaults: iters=$_iters, num_layers=$_layers, lora_rank=$_rank"
        return 0
    end

    # Shared helper: convert a model dir to GGUF, quantize, optionally import to Ollama.
    # Arguments: <model-dir> <slug> <quant-type> <skip-import 0|1> <logfile> <ollama-suffix>
    function _rollie_gguf_pipeline --argument-names _src_dir _slug _quant _skip _logfile _suffix
        set _gguf_dir "$WORKSPACE/models/gguf"
        set _gguf_f16 "$_gguf_dir/$_slug-f16.gguf"
        set _gguf_final "$_gguf_dir/$_slug.gguf"
        set _modelfile "$_gguf_dir/$_slug.Modelfile"
        set _ollama_name "$_slug$_suffix"
        set _gguf_sentinel "$_gguf_final.ok"

        mkdir -p "$_gguf_dir"

        if test -f "$_gguf_sentinel"
            _rollie_ok "GGUF found — skipping conversion."
        else
            if test -f "$_gguf_final"
                _rollie_warn "Incomplete GGUF found — previous run was likely interrupted."
                read --prompt-str (set_color cyan)"[rollie]"(set_color normal)" Remove and re-quantize? [y/N]: " _retry
                if test "$_retry" != "y" -a "$_retry" != "Y"
                    _rollie_info "Leaving as-is. Run 'rollie --clean $_slug' to remove it."
                    return 1
                end
                rm -f "$_gguf_final"
            end

            _rollie_info "Converting to GGUF (F16 intermediate)..."
            if not env VIRTUAL_ENV="$CONVERT_ENV" PATH="$CONVERT_ENV/bin:$PATH" \
                python3 "$CONVERT_ENV/bin/convert_hf_to_gguf.py" \
                --outtype f16 --outfile "$_gguf_f16" "$_src_dir" 2>&1 | tee -a "$_logfile"
                _rollie_err "Conversion failed. See: $_logfile"
                rm -f "$_gguf_f16"
                return 1
            end
            _rollie_ok "F16 GGUF created."

            _rollie_info "Quantizing to $_quant..."
            if not llama-quantize "$_gguf_f16" "$_gguf_final" $_quant 2>&1 | tee -a "$_logfile"
                _rollie_err "Quantization failed. See: $_logfile"
                rm -f "$_gguf_final"
                return 1
            end
            rm -f "$_gguf_f16"
            touch "$_gguf_sentinel"
            _rollie_ok "Quantized GGUF → $_gguf_final"
        end

        if test "$_skip" = "1"
            echo ""
            _rollie_ok "Done (--skip-import)."
            _rollie_info "  GGUF: $_gguf_final"
            return 0
        end

        _rollie_info "Writing Modelfile..."
        printf "FROM %s\n\nPARAMETER temperature 0.7\nPARAMETER top_p 0.9\nPARAMETER num_ctx 8192\n\nSYSTEM \"You are a helpful assistant.\"\n" \
            "$_gguf_final" > "$_modelfile"

        _rollie_info "Importing to Ollama as '$_ollama_name'..."
        if not ollama create "$_ollama_name" -f "$_modelfile" 2>&1 | tee -a "$_logfile"
            _rollie_err "Ollama import failed. See: $_logfile"
            return 1
        end

        echo ""
        _rollie_ok "Model ready in Ollama!"
        _rollie_info "  Name:   $_ollama_name"
        _rollie_info "  Test:   ollama run $_ollama_name"
        _rollie_info "  llamy:  llamy $_ollama_name"
        echo ""
    end

    # ── finetune subcommand ───────────────────────────────────────────────────

    if test "$argv[1]" = "finetune"
        set _ft_model $argv[2]
        if test -z "$_ft_model"
            _rollie_err "Usage: rollie finetune <model-or-hf-id> --data <dataset-dir>"
            return 1
        end

        set _ft_data ""
        set _ft_iters ""
        set _ft_layers ""
        set _ft_rank ""
        set _ft_lr "1e-5"
        set _ft_quant "Q4_K_M"
        set _ft_skip_import 0
        set _i 3
        while test $_i -le (count $argv)
            switch $argv[$_i]
                case "--data"
                    set _i (math $_i + 1)
                    test $_i -le (count $argv) && set _ft_data $argv[$_i]
                case "--iters"
                    set _i (math $_i + 1)
                    test $_i -le (count $argv) && set _ft_iters $argv[$_i]
                case "--layers"
                    set _i (math $_i + 1)
                    test $_i -le (count $argv) && set _ft_layers $argv[$_i]
                case "--rank"
                    set _i (math $_i + 1)
                    test $_i -le (count $argv) && set _ft_rank $argv[$_i]
                case "--lr"
                    set _i (math $_i + 1)
                    test $_i -le (count $argv) && set _ft_lr $argv[$_i]
                case "--quant"
                    set _i (math $_i + 1)
                    test $_i -le (count $argv) && set _ft_quant $argv[$_i]
                case "--skip-import"
                    set _ft_skip_import 1
            end
            set _i (math $_i + 1)
        end

        if test -z "$_ft_data"
            _rollie_err "--data <dataset-dir> is required."
            return 1
        end
        if not test -d "$_ft_data"
            _rollie_err "Dataset dir not found: $_ft_data"
            return 1
        end
        if not test -f "$_ft_data/data.jsonl"
            _rollie_err "No data.jsonl found in: $_ft_data"
            _rollie_info "Expected format: {\"text\": \"<|im_start|>user\\n...<|im_end|>\\n<|im_start|>assistant\\n...<|im_end|>\"}"
            return 1
        end

        set _mlx_env "$WORKSPACE/envs/mlx"
        if not test -d "$_mlx_env"
            _rollie_err "MLX env not found — run: fish setup.fish"
            return 1
        end
        if not test -f "$CONVERT_ENV/bin/convert_hf_to_gguf.py"
            _rollie_err "GGUF converter not found — run: fish setup.fish"
            return 1
        end
        if not command -q llama-quantize
            _rollie_err "llama-quantize not found — run: brew install llama.cpp"
            return 1
        end

        set _defaults (_rollie_finetune_defaults)
        test -z "$_ft_iters" && set _ft_iters $_defaults[1]
        test -z "$_ft_layers" && set _ft_layers $_defaults[2]
        test -z "$_ft_rank" && set _ft_rank $_defaults[3]

        set _ft_slug (_rollie_slug "$_ft_model")
        set _ft_base_dir "$WORKSPACE/models/base/$_ft_slug"
        set _ft_adapter_dir "$WORKSPACE/models/adapters/$_ft_slug"
        set _ft_merged_dir "$WORKSPACE/models/merged/$_ft_slug"

        mkdir -p "$WORKSPACE/models/base" "$WORKSPACE/models/adapters" "$WORKSPACE/models/merged" "$LOG_DIR"
        set _ft_logfile "$LOG_DIR/$_ft_slug-finetune.log"

        echo ""
        _rollie_info "Model:    $_ft_model"
        _rollie_info "Dataset:  $_ft_data"
        _rollie_info "iters=$_ft_iters  layers=$_ft_layers  rank=$_ft_rank  lr=$_ft_lr"
        _rollie_info "Log:      $_ft_logfile"
        echo ""

        # Resolve base model — check for local path first, then treat as HF ID
        if test -d "$_ft_model"
            set _ft_use_path "$_ft_model"
        else if string match -q '*/*' -- $_ft_model
            if not test -d "$_ft_base_dir"
                _rollie_info "Downloading base model from HuggingFace..."
                if not huggingface-cli download "$_ft_model" --local-dir "$_ft_base_dir" 2>&1 | tee -a "$_ft_logfile"
                    _rollie_err "Download failed. See: $_ft_logfile"
                    return 1
                end
                _rollie_ok "Downloaded → $_ft_base_dir"
            else
                _rollie_ok "Base model cached — $_ft_base_dir"
            end
            set _ft_use_path "$_ft_base_dir"
        else
            _rollie_err "Model not found — pass a local path or a HuggingFace ID (org/model): $_ft_model"
            return 1
        end

        # LoRA training
        set _ft_adapter_sentinel "$_ft_adapter_dir/.rollie_finetune_complete"
        if test -f "$_ft_adapter_sentinel"
            _rollie_ok "Adapter found — skipping training."
        else
            _rollie_info "Training LoRA adapter (mlx_lm.lora)..."
            if not env VIRTUAL_ENV="$_mlx_env" PATH="$_mlx_env/bin:$PATH" \
                python3 -m mlx_lm.lora \
                    --model "$_ft_use_path" \
                    --train \
                    --data "$_ft_data" \
                    --adapter-path "$_ft_adapter_dir" \
                    --iters $_ft_iters \
                    --num-layers $_ft_layers \
                    --lora-rank $_ft_rank \
                    --learning-rate $_ft_lr \
                    2>&1 | tee -a "$_ft_logfile"
                _rollie_err "LoRA training failed. See: $_ft_logfile"
                return 1
            end
            touch "$_ft_adapter_sentinel"
            _rollie_ok "Adapter trained → $_ft_adapter_dir"
        end

        # Fuse adapter
        set _ft_merge_sentinel "$_ft_merged_dir/.rollie_merge_complete"
        if test -f "$_ft_merge_sentinel"
            _rollie_ok "Merged model found — skipping fuse."
        else
            _rollie_info "Fusing adapter into base model (mlx_lm.fuse)..."
            if not env VIRTUAL_ENV="$_mlx_env" PATH="$_mlx_env/bin:$PATH" \
                python3 -m mlx_lm.fuse \
                    --model "$_ft_use_path" \
                    --adapter-path "$_ft_adapter_dir" \
                    --save-path "$_ft_merged_dir" \
                    2>&1 | tee -a "$_ft_logfile"
                _rollie_err "Adapter fuse failed. See: $_ft_logfile"
                return 1
            end
            touch "$_ft_merge_sentinel"
            _rollie_ok "Merged model → $_ft_merged_dir"
        end

        # Convert → quantize → import
        if not _rollie_gguf_pipeline \
            "$_ft_merged_dir" "$_ft_slug-finetuned" "$_ft_quant" $_ft_skip_import "$_ft_logfile" ""
            return 1
        end
        return 0
    end

    # ── curate subcommand ─────────────────────────────────────────────────────

    if test "$argv[1]" = "curate"
        set _curate_env "$WORKSPACE/envs/curate"
        if not test -d "$_curate_env"
            _rollie_err "Curate env not found — run: fish setup.fish"
            return 1
        end
        if not test -f "$SCRIPTS_DIR/curate.py"
            _rollie_err "Curate script not found — run: fish setup.fish"
            return 1
        end

        # Pass all arguments after 'curate' directly to curate.py
        set _curate_args $argv[2..]

        env VIRTUAL_ENV="$_curate_env" PATH="$_curate_env/bin:$PATH" \
            PYTHONPATH="$SCRIPTS_DIR:$SCRIPTS_DIR/sources" \
            python3 "$SCRIPTS_DIR/curate.py" $_curate_args
        return $status
    end

    # ── --clean ────────────────────────────────────────────────────────────────

    if test "$argv[1]" = "--clean"
        set _slug $argv[2]
        if test -z "$_slug"
            _rollie_err "Usage: rollie --clean <model-slug>"
            _rollie_info "Run 'rollie --status' to see available slugs."
            return 1
        end

        echo ""
        _rollie_warn "Will delete workspace files for '$_slug':"
        test -d "$WORKSPACE/models/abliterated/$_slug"  && echo "  $WORKSPACE/models/abliterated/$_slug"
        test -d "$WORKSPACE/models/base/$_slug"         && echo "  $WORKSPACE/models/base/$_slug"
        test -d "$WORKSPACE/models/adapters/$_slug"     && echo "  $WORKSPACE/models/adapters/$_slug"
        test -d "$WORKSPACE/models/merged/$_slug"       && echo "  $WORKSPACE/models/merged/$_slug"
        for f in "$WORKSPACE/models/gguf/$_slug"*.gguf "$WORKSPACE/models/gguf/$_slug"*.ok "$WORKSPACE/models/gguf/$_slug.Modelfile"
            test -f "$f" && echo "  $f"
        end
        echo ""
        read --prompt-str (set_color cyan)"[rollie]"(set_color normal)" Confirm? [y/N]: " _confirm
        if test "$_confirm" != "y" -a "$_confirm" != "Y"
            _rollie_info "Cancelled."
            return 0
        end
        rm -rf "$WORKSPACE/models/abliterated/$_slug"
        rm -rf "$WORKSPACE/models/base/$_slug"
        rm -rf "$WORKSPACE/models/adapters/$_slug"
        rm -rf "$WORKSPACE/models/merged/$_slug"
        rm -f "$WORKSPACE/models/gguf/$_slug"*.gguf "$WORKSPACE/models/gguf/$_slug"*.ok "$WORKSPACE/models/gguf/$_slug.Modelfile"
        _rollie_ok "Cleaned: $_slug"
        return 0
    end

    # ── --logs ─────────────────────────────────────────────────────────────────

    if test "$argv[1]" = "--logs"
        if test -n "$argv[2]"
            set _logfile "$LOG_DIR/$argv[2].log"
            if not test -f "$_logfile"
                _rollie_err "No log found for: $argv[2]"
                _rollie_info "Logs in $LOG_DIR:"
                ls "$LOG_DIR" 2>/dev/null | sed 's/^/  /'
                return 1
            end
            tail -f "$_logfile"
        else
            set _latest (ls -t "$LOG_DIR"/*.log 2>/dev/null | head -1)
            if test -z "$_latest"
                _rollie_err "No logs yet in $LOG_DIR"
                return 1
            end
            _rollie_info "Tailing: $_latest"
            tail -f "$_latest"
        end
        return 0
    end

    # ── pipeline ───────────────────────────────────────────────────────────────

    set HF_ID $argv[1]

    # Parse remaining flags
    set QUANT_TYPE    "Q4_K_M"
    set SKIP_IMPORT   0
    set FINETUNE_DIR  ""
    set OLLAMA_SUFFIX "-heretic"
    set _i 2
    while test $_i -le (count $argv)
        switch $argv[$_i]
            case "--quant"
                set _i (math $_i + 1)
                if test $_i -le (count $argv)
                    set QUANT_TYPE $argv[$_i]
                end
            case "--skip-import"
                set SKIP_IMPORT 1
            case "--finetune"
                set _i (math $_i + 1)
                if test $_i -le (count $argv)
                    set FINETUNE_DIR $argv[$_i]
                end
        end
        set _i (math $_i + 1)
    end

    if not _rollie_check_deps
        return 1
    end

    set SLUG    (_rollie_slug $HF_ID)
    set ABL_DIR  "$WORKSPACE/models/abliterated/$SLUG"
    set GGUF_DIR "$WORKSPACE/models/gguf"
    set LOGFILE  "$LOG_DIR/$SLUG.log"

    mkdir -p "$WORKSPACE/models/abliterated" "$WORKSPACE/models/base" \
             "$WORKSPACE/models/adapters" "$WORKSPACE/models/merged" \
             "$GGUF_DIR" "$LOG_DIR"

    echo ""
    _rollie_info "Model:      $HF_ID"
    _rollie_info "Slug:       $SLUG"
    _rollie_info "Quant:      $QUANT_TYPE"
    _rollie_info "Ollama name: $SLUG$OLLAMA_SUFFIX"
    _rollie_info "Log:        $LOGFILE"
    echo ""

    # ── stage 1: abliterate ───────────────────────────────────────────────────

    set ABL_SENTINEL "$ABL_DIR/.rollie_complete"

    if test -f "$ABL_SENTINEL"
        _rollie_ok "Abliterated model found — skipping heretic."
    else
        if test -d "$ABL_DIR"
            _rollie_warn "Partial abliteration found — previous run was likely interrupted."
            _rollie_warn "  $ABL_DIR"
            read --prompt-str (set_color cyan)"[rollie]"(set_color normal)" Remove and re-run heretic? [y/N]: " _retry
            if test "$_retry" != "y" -a "$_retry" != "Y"
                _rollie_info "Leaving as-is. Run 'rollie --clean $SLUG' to remove it."
                return 1
            end
            rm -rf "$ABL_DIR"
        end

        _rollie_info "Running heretic (downloads from HuggingFace, then abliterates)..."
        _rollie_info "Estimated time: 1.5 h (4B) · 3–5 h (8B) · 6–10 h (12B)"
        _rollie_info "Watch progress in another terminal: rollie --logs $SLUG"
        echo ""

        if not env VIRTUAL_ENV="$HERETIC_ENV" PATH="$HERETIC_ENV/bin:$PATH" \
            heretic $HF_ID --output-dir "$ABL_DIR" 2>&1 | tee -a "$LOGFILE"
            _rollie_err "Heretic failed. See: $LOGFILE"
            return 1
        end
        touch "$ABL_SENTINEL"
        _rollie_ok "Abliteration complete → $ABL_DIR"
    end

    # ── stage 1.5: finetune chain (--finetune <dataset-dir>) ─────────────────

    if test -n "$FINETUNE_DIR"
        if not test -d "$FINETUNE_DIR"
            _rollie_err "Finetune dataset dir not found: $FINETUNE_DIR"
            return 1
        end
        if not test -f "$FINETUNE_DIR/data.jsonl"
            _rollie_err "No data.jsonl found in: $FINETUNE_DIR"
            return 1
        end

        set _mlx_env "$WORKSPACE/envs/mlx"
        if not test -d "$_mlx_env"
            _rollie_err "MLX env not found — run: fish setup.fish"
            return 1
        end

        set _defaults (_rollie_finetune_defaults)
        set _ft_iters $_defaults[1]
        set _ft_layers $_defaults[2]
        set _ft_rank $_defaults[3]
        set _ft_lr "1e-5"

        set _ft_adapter_dir "$WORKSPACE/models/adapters/$SLUG"
        set _ft_merged_dir "$WORKSPACE/models/merged/$SLUG"
        mkdir -p "$WORKSPACE/models/adapters" "$WORKSPACE/models/merged"

        _rollie_info "Fine-tuning (iters=$_ft_iters, layers=$_ft_layers, rank=$_ft_rank)..."

        set _ft_adapter_sentinel "$_ft_adapter_dir/.rollie_finetune_complete"
        if test -f "$_ft_adapter_sentinel"
            _rollie_ok "Adapter found — skipping training."
        else
            if not env VIRTUAL_ENV="$_mlx_env" PATH="$_mlx_env/bin:$PATH" \
                python3 -m mlx_lm.lora \
                    --model "$ABL_DIR" \
                    --train \
                    --data "$FINETUNE_DIR" \
                    --adapter-path "$_ft_adapter_dir" \
                    --iters $_ft_iters \
                    --num-layers $_ft_layers \
                    --lora-rank $_ft_rank \
                    --learning-rate $_ft_lr \
                    2>&1 | tee -a "$LOGFILE"
                _rollie_err "LoRA training failed. See: $LOGFILE"
                return 1
            end
            touch "$_ft_adapter_sentinel"
            _rollie_ok "Adapter trained → $_ft_adapter_dir"
        end

        set _ft_merge_sentinel "$_ft_merged_dir/.rollie_merge_complete"
        if test -f "$_ft_merge_sentinel"
            _rollie_ok "Merged model found — skipping fuse."
        else
            if not env VIRTUAL_ENV="$_mlx_env" PATH="$_mlx_env/bin:$PATH" \
                python3 -m mlx_lm.fuse \
                    --model "$ABL_DIR" \
                    --adapter-path "$_ft_adapter_dir" \
                    --save-path "$_ft_merged_dir" \
                    2>&1 | tee -a "$LOGFILE"
                _rollie_err "Adapter fuse failed. See: $LOGFILE"
                return 1
            end
            touch "$_ft_merge_sentinel"
            _rollie_ok "Merged model → $_ft_merged_dir"
        end

        set ABL_DIR "$_ft_merged_dir"
        set OLLAMA_SUFFIX "-heretic-finetuned"
    end

    # ── stages 2 + 3: convert → quantize → import ────────────────────────────

    if not _rollie_gguf_pipeline \
        "$ABL_DIR" "$SLUG" "$QUANT_TYPE" $SKIP_IMPORT "$LOGFILE" "$OLLAMA_SUFFIX"
        return 1
    end
end
