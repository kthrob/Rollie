#!/usr/bin/env fish
# setup.fish — install rollie and its dependencies
#
# Run from the repository root:
#   fish setup.fish

# ── helpers ───────────────────────────────────────────────────────────────────

function info
    echo (set_color cyan)"[setup]"(set_color normal) $argv
end
function ok
    echo (set_color green)"[setup] ✓"(set_color normal) $argv
end
function warn
    echo (set_color yellow)"[setup] !"(set_color normal) $argv
end
function err
    echo (set_color red)"[setup] ✗"(set_color normal) $argv >&2
end
function header
    echo ""
    echo (set_color --bold)"── $argv"(set_color normal)
end
function die
    err $argv
    exit 1
end

# ── 0. sanity: must be run from the repo root ─────────────────────────────────

header "Checking repo"

if not test -f ./rollie.fish
    die "rollie.fish not found in current directory. Run setup.fish from the repo root."
end
ok "rollie.fish found"

# ── 1. Homebrew ───────────────────────────────────────────────────────────────

header "Homebrew"

if not command -q brew
    info "Homebrew not found — installing..."
    /bin/bash -c (curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)
    if test -f /opt/homebrew/bin/brew
        eval (/opt/homebrew/bin/brew shellenv)
    end
    if not command -q brew
        die "Homebrew installation failed. Please install manually: https://brew.sh"
    end
    ok "Homebrew installed"
else
    info "Homebrew found — checking for updates..."
    brew update --quiet
    ok "Homebrew up to date ("(brew --version | head -1)")"
end

# ── 2. uv ─────────────────────────────────────────────────────────────────────

header "uv"

if not command -q uv
    info "uv not found — installing via Homebrew..."
    brew install uv
    if not command -q uv
        die "uv installation failed."
    end
    ok "uv installed ("(uv --version)")"
else
    info "uv already installed ("(uv --version)") — checking for upgrade..."
    brew upgrade uv --quiet 2>/dev/null
    ok "uv up to date ("(uv --version)")"
end

# ── 3. git + git-lfs ──────────────────────────────────────────────────────────

header "git + git-lfs"

if not command -q git
    info "git not found — installing via Homebrew..."
    brew install git
    if not command -q git
        die "git installation failed."
    end
    ok "git installed ("(git --version)")"
else
    ok "git already installed ("(git --version)")"
end

if not command -q git-lfs
    info "git-lfs not found — installing via Homebrew..."
    brew install git-lfs
    if not command -q git-lfs
        die "git-lfs installation failed."
    end
    ok "git-lfs installed"
else
    ok "git-lfs already installed"
end

info "Initializing git-lfs..."
git lfs install --skip-repo 2>/dev/null
ok "git-lfs initialized"

# ── 4. Ollama ─────────────────────────────────────────────────────────────────

header "Ollama"

if not command -q ollama
    info "Ollama not found — installing via Homebrew..."
    brew install ollama
    if not command -q ollama
        die "Ollama installation failed."
    end
    ok "Ollama installed ("(ollama --version 2>&1 | head -1)")"
else
    info "Ollama already installed — checking for upgrade..."
    brew upgrade ollama --quiet 2>/dev/null
    ok "Ollama up to date ("(ollama --version 2>&1 | head -1)")"
end

# ── 5. llama.cpp (for llama-quantize) ────────────────────────────────────────

header "llama.cpp"

if not command -q llama-quantize
    info "llama.cpp not found — installing via Homebrew..."
    brew install llama.cpp
    if not command -q llama-quantize
        die "llama.cpp installation failed."
    end
    ok "llama.cpp installed (llama-quantize available)"
else
    info "llama.cpp already installed — checking for upgrade..."
    brew upgrade llama.cpp --quiet 2>/dev/null
    ok "llama.cpp up to date"
end

# ── 6. huggingface-cli ────────────────────────────────────────────────────────

header "huggingface-cli"

if not command -q huggingface-cli
    info "huggingface-cli not found — installing via uv tool..."
    uv tool install huggingface_hub[cli]
    if not command -q huggingface-cli
        warn "huggingface-cli not in PATH after install. Try: uv tool update-shell"
        warn "Gate-locked models (Llama, Gemma) require 'huggingface-cli login' before running rollie."
    else
        ok "huggingface-cli installed"
    end
else
    ok "huggingface-cli already installed"
end

info "Note: gate-locked models require login: huggingface-cli login"

# ── 7. Workspace structure ────────────────────────────────────────────────────

header "Workspace"

set WORKSPACE "$HOME/rollie-workspace"

mkdir -p \
    "$WORKSPACE/models/abliterated" \
    "$WORKSPACE/models/gguf" \
    "$WORKSPACE/envs" \
    "$WORKSPACE/logs"

ok "Workspace ready: $WORKSPACE"

# ── 8. Heretic Python environment ─────────────────────────────────────────────

header "Heretic environment"

set HERETIC_ENV "$WORKSPACE/envs/heretic"

if test -d "$HERETIC_ENV"
    info "Heretic env exists — upgrading packages..."
else
    info "Creating heretic env (Python 3.11)..."
    uv venv "$HERETIC_ENV" --python 3.11
    or die "Failed to create heretic venv."
end

info "Installing heretic-llm and PyTorch (MPS) — this may take a few minutes..."
uv pip install --python "$HERETIC_ENV/bin/python3" \
    heretic-llm \
    torch torchvision torchaudio \
    2>&1
or die "Failed to install heretic packages."

# Verify heretic is callable
if not env VIRTUAL_ENV="$HERETIC_ENV" PATH="$HERETIC_ENV/bin:$PATH" command -q heretic
    die "heretic command not found after install. Check the output above."
end
ok "Heretic env ready: $HERETIC_ENV"

# ── 9. Convert environment + GGUF conversion script ──────────────────────────

header "Convert environment"

set CONVERT_ENV "$WORKSPACE/envs/convert"

if test -d "$CONVERT_ENV"
    info "Convert env exists — upgrading packages..."
else
    info "Creating convert env (Python 3.11)..."
    uv venv "$CONVERT_ENV" --python 3.11
    or die "Failed to create convert venv."
end

info "Installing conversion dependencies..."
uv pip install --python "$CONVERT_ENV/bin/python3" \
    gguf \
    transformers \
    sentencepiece \
    protobuf \
    numpy \
    torch \
    2>&1
or die "Failed to install convert packages."

# Download convert_hf_to_gguf.py from llama.cpp, version-matched to installed llama-quantize
info "Fetching GGUF conversion script from llama.cpp..."

set CONVERT_SCRIPT "$CONVERT_ENV/bin/convert_hf_to_gguf.py"

# Try to match the installed llama.cpp build tag (e.g. b4800)
set _llama_build (llama-quantize --version 2>&1 | grep -oE 'b[0-9]+' | head -1)
if test -n "$_llama_build"
    set _convert_url "https://raw.githubusercontent.com/ggerganov/llama.cpp/$_llama_build/convert_hf_to_gguf.py"
    info "Fetching script at llama.cpp $_llama_build..."
else
    set _convert_url "https://raw.githubusercontent.com/ggerganov/llama.cpp/master/convert_hf_to_gguf.py"
    info "Could not determine llama.cpp build tag — fetching from master..."
end

if curl -fsSL "$_convert_url" -o "$CONVERT_SCRIPT" 2>/dev/null
    chmod +x "$CONVERT_SCRIPT"
    ok "Conversion script fetched → $CONVERT_SCRIPT"
else
    warn "Failed to download conversion script from: $_convert_url"
    warn "Try fetching it manually:"
    warn "  curl -fsSL https://raw.githubusercontent.com/ggerganov/llama.cpp/master/convert_hf_to_gguf.py \\"
    warn "       -o $CONVERT_SCRIPT && chmod +x $CONVERT_SCRIPT"
end

# ── 10. Install rollie.fish ───────────────────────────────────────────────────

header "Installing rollie"

if test -n "$__fish_config_dir"
    set FISH_FUNCTIONS "$__fish_config_dir/functions"
else
    set FISH_FUNCTIONS "$HOME/.config/fish/functions"
end
mkdir -p "$FISH_FUNCTIONS"

set DEST "$FISH_FUNCTIONS/rollie.fish"
cp ./rollie.fish "$DEST"
or die "Failed to copy rollie.fish to $DEST"
chmod +x "$DEST"

ok "rollie.fish installed → $DEST"

if fish -c "type -q rollie"
    ok "rollie command is available in Fish"
else
    warn "rollie is not immediately discoverable — open a new terminal or run:"
    warn "  source ~/.config/fish/config.fish"
end

# ── done ──────────────────────────────────────────────────────────────────────

echo ""
echo (set_color --bold)(set_color green)"  All done!"(set_color normal)
echo ""
echo "  Open a new terminal (or run "(set_color cyan)"source ~/.config/fish/config.fish"(set_color normal)") and:"
echo ""
echo "    "(set_color --bold)"rollie --help"(set_color normal)"                         see all commands"
echo "    "(set_color --bold)"rollie Qwen/Qwen3-8B-Instruct"(set_color normal)"         abliterate and import"
echo "    "(set_color --bold)"rollie --status"(set_color normal)"                        workspace overview"
echo ""
echo "  For gate-locked models (Llama 3.x, Gemma), log in first:"
echo "    "(set_color --bold)"huggingface-cli login"(set_color normal)
echo ""
