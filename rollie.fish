# ~/.config/fish/functions/rollie.fish
#
# Usage:
#   rollie <hf-model-id>             Full pipeline: abliterate → GGUF → Ollama import
#   rollie <hf-model-id> --quant Q5_K_M   Custom quantization
#   rollie <hf-model-id> --skip-import    Stop at GGUF; skip Ollama import
#   rollie --list                    List rollie models in Ollama
#   rollie --status                  Workspace status and disk usage
#   rollie --clean <slug>            Delete workspace files for a model
#   rollie --logs [slug]             Tail the log for a run
#   rollie --help                    Show all commands

function rollie --description "Abliterate a HuggingFace model and import to Ollama"

    set WORKSPACE    "$HOME/rollie-workspace"
    set LOG_DIR      "$WORKSPACE/logs"
    set HERETIC_ENV  "$WORKSPACE/envs/heretic"
    set CONVERT_ENV  "$WORKSPACE/envs/convert"

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

    # ── --help ─────────────────────────────────────────────────────────────────

    if test (count $argv) -eq 0 -o "$argv[1]" = "--help" -o "$argv[1]" = "-h"
        echo ""
        echo (set_color --bold)"rollie"(set_color normal)" — abliterate HuggingFace models and import to Ollama"
        echo ""
        echo (set_color --bold)"USAGE"(set_color normal)
        echo "  rollie <hf-model-id>             Full pipeline: abliterate → GGUF → Ollama"
        echo "  rollie <hf-model-id> [options]"
        echo ""
        echo (set_color --bold)"OPTIONS"(set_color normal)
        printf "  %-28s %s\n" "--quant <type>"     "GGUF quantization type (default: Q4_K_M)"
        printf "  %-28s %s\n" "--skip-import"      "Stop at GGUF; skip Ollama import"
        printf "  %-28s %s\n" "--list"             "List rollie models in Ollama"
        printf "  %-28s %s\n" "--status"           "Workspace status and disk usage"
        printf "  %-28s %s\n" "--clean <slug>"     "Delete workspace files for a model"
        printf "  %-28s %s\n" "--logs [slug]"      "Tail a run log (latest if slug omitted)"
        printf "  %-28s %s\n" "--help, -h"         "Show this help"
        echo ""
        echo (set_color --bold)"EXAMPLES"(set_color normal)
        echo "  rollie Qwen/Qwen3-8B-Instruct"
        echo "  rollie meta-llama/Llama-3.1-8B-Instruct --quant Q5_K_M"
        echo "  rollie google/gemma-3-12b-it --skip-import"
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
            set _abls (ls "$_abl_dir" 2>/dev/null)
            if test (count $_abls) -gt 0
                echo (set_color --bold)"Abliterated:"(set_color normal)
                for s in $_abls
                    set _sz (du -sh "$_abl_dir/$s" 2>/dev/null | awk '{print $1}')
                    echo "  • $s  ($_sz)"
                end
                echo ""
            end
        end

        set _gguf_dir "$WORKSPACE/models/gguf"
        if test -d "$_gguf_dir"
            set _ggufs (ls "$_gguf_dir" 2>/dev/null | grep '\.gguf$')
            if test (count $_ggufs) -gt 0
                echo (set_color --bold)"GGUF files:"(set_color normal)
                for f in $_ggufs
                    set _sz (du -sh "$_gguf_dir/$f" 2>/dev/null | awk '{print $1}')
                    echo "  • $f  ($_sz)"
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
        for env_name in heretic convert mlx mergekit
            if test -d "$WORKSPACE/envs/$env_name"
                echo "  ✓ $env_name"
            else
                echo "  ✗ $env_name  (not installed)"
            end
        end
        echo ""
        return 0
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
        test -d "$WORKSPACE/models/abliterated/$_slug" && echo "  $WORKSPACE/models/abliterated/$_slug"
        for f in "$WORKSPACE/models/gguf/$_slug"*.gguf "$WORKSPACE/models/gguf/$_slug.Modelfile"
            test -f "$f" && echo "  $f"
        end
        echo ""
        read --prompt-str (set_color cyan)"[rollie]"(set_color normal)" Confirm? [y/N]: " _confirm
        if test "$_confirm" != "y" -a "$_confirm" != "Y"
            _rollie_info "Cancelled."
            return 0
        end
        rm -rf "$WORKSPACE/models/abliterated/$_slug"
        rm -f "$WORKSPACE/models/gguf/$_slug"*.gguf "$WORKSPACE/models/gguf/$_slug.Modelfile"
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
    set QUANT_TYPE  "Q4_K_M"
    set SKIP_IMPORT 0
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
        end
        set _i (math $_i + 1)
    end

    if not _rollie_check_deps
        return 1
    end

    set SLUG        (_rollie_slug $HF_ID)
    set ABL_DIR     "$WORKSPACE/models/abliterated/$SLUG"
    set GGUF_DIR    "$WORKSPACE/models/gguf"
    set GGUF_F16    "$GGUF_DIR/$SLUG-f16.gguf"
    set GGUF_FINAL  "$GGUF_DIR/$SLUG.gguf"
    set MODELFILE   "$GGUF_DIR/$SLUG.Modelfile"
    set OLLAMA_NAME "$SLUG-heretic"
    set LOGFILE     "$LOG_DIR/$SLUG.log"

    mkdir -p "$WORKSPACE/models/abliterated" "$GGUF_DIR" "$LOG_DIR"

    echo ""
    _rollie_info "Model:      $HF_ID"
    _rollie_info "Slug:       $SLUG"
    _rollie_info "Quant:      $QUANT_TYPE"
    _rollie_info "Ollama name: $OLLAMA_NAME"
    _rollie_info "Log:        $LOGFILE"
    echo ""

    # ── stage 1: abliterate ───────────────────────────────────────────────────

    if test -d "$ABL_DIR"
        _rollie_ok "Abliterated model found — skipping heretic."
    else
        _rollie_info "Running heretic (downloads from HuggingFace, then abliterates)..."
        _rollie_info "Estimated time: 1.5 h (4B) · 3–5 h (8B) · 6–10 h (12B)"
        _rollie_info "Watch progress in another terminal: rollie --logs $SLUG"
        echo ""

        if not env VIRTUAL_ENV="$HERETIC_ENV" PATH="$HERETIC_ENV/bin:$PATH" \
            heretic $HF_ID --output-dir "$ABL_DIR" 2>&1 | tee -a "$LOGFILE"
            _rollie_err "Heretic failed. See: $LOGFILE"
            rmdir "$ABL_DIR" 2>/dev/null
            return 1
        end
        _rollie_ok "Abliteration complete → $ABL_DIR"
    end

    # ── stage 2: convert to GGUF ──────────────────────────────────────────────

    if test -f "$GGUF_FINAL"
        _rollie_ok "GGUF found — skipping conversion."
    else
        _rollie_info "Converting to GGUF (F16 intermediate)..."
        if not env VIRTUAL_ENV="$CONVERT_ENV" PATH="$CONVERT_ENV/bin:$PATH" \
            python3 "$CONVERT_ENV/bin/convert_hf_to_gguf.py" \
            --outtype f16 --outfile "$GGUF_F16" "$ABL_DIR" 2>&1 | tee -a "$LOGFILE"
            _rollie_err "Conversion failed. See: $LOGFILE"
            rm -f "$GGUF_F16"
            return 1
        end
        _rollie_ok "F16 GGUF created."

        _rollie_info "Quantizing to $QUANT_TYPE..."
        if not llama-quantize "$GGUF_F16" "$GGUF_FINAL" $QUANT_TYPE 2>&1 | tee -a "$LOGFILE"
            _rollie_err "Quantization failed. See: $LOGFILE"
            rm -f "$GGUF_FINAL"
            return 1
        end
        rm -f "$GGUF_F16"
        _rollie_ok "Quantized GGUF → $GGUF_FINAL"
    end

    if test $SKIP_IMPORT -eq 1
        echo ""
        _rollie_ok "Done (--skip-import)."
        _rollie_info "  GGUF: $GGUF_FINAL"
        return 0
    end

    # ── stage 3: import to Ollama ─────────────────────────────────────────────

    _rollie_info "Writing Modelfile..."
    printf "FROM %s\n\nPARAMETER temperature 0.7\nPARAMETER top_p 0.9\nPARAMETER num_ctx 8192\n\nSYSTEM \"You are a helpful assistant.\"\n" \
        "$GGUF_FINAL" > "$MODELFILE"

    _rollie_info "Importing to Ollama as '$OLLAMA_NAME'..."
    if not ollama create "$OLLAMA_NAME" -f "$MODELFILE" 2>&1 | tee -a "$LOGFILE"
        _rollie_err "Ollama import failed. See: $LOGFILE"
        return 1
    end

    echo ""
    _rollie_ok "Model ready in Ollama!"
    _rollie_info "  Name:   $OLLAMA_NAME"
    _rollie_info "  Test:   ollama run $OLLAMA_NAME"
    _rollie_info "  llamy:  llamy $OLLAMA_NAME"
    echo ""
end
