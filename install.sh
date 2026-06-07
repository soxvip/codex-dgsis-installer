#!/usr/bin/env bash
set -Eeuo pipefail

on_error() {
  local status="$?" line="${BASH_LINENO[0]:-$LINENO}" command_text="${BASH_COMMAND:-comando desconhecido}"
  printf '\nERROR: instalador interrompido antes de concluir. Linha %s, status %s.\n' "$line" "$status" >&2
  printf 'Ultimo comando: %s\n' "$command_text" >&2
  printf 'Rode novamente o mesmo comando. Se repetir, envie essas linhas ao suporte.\n' >&2
}

trap on_error ERR

DGSIS_BASE_URL="https://gtw.dgsis.com.br/v1"
DGSIS_MODEL="cx/gpt-5.5"
CODEX_INSTALL_URL="https://chatgpt.com/codex/install.sh"
FALLBACK_CATALOG_URL="https://raw.githubusercontent.com/soxvip/codex-dgsis-installer/main/dgsis-model-catalog.json"

TOKEN=""
SELF_TEST=0
SKIP_DEPENDENCIES=0
SKIP_VSCODE=0
SKIP_LIVE_TESTS=0

usage() {
  cat <<'EOF'
Uso: install.sh [opcoes]

Instala Codex CLI, dependencias, VS Code extension e configuracao DGSIS no macOS/Linux.

Opcoes:
  --token TOKEN          Usa TOKEN como token DGSIS. Preferivel deixar o instalador pedir.
  --skip-dependencies   Nao instala Git, Node.js, Python, Homebrew ou VS Code.
  --skip-vscode         Nao instala VS Code nem extensao openai.chatgpt.
  --skip-live-tests     Nao valida token no gateway nem executa chamadas do Codex.
  --self-test           Executa autotestes locais sem instalar nada.
  -h, --help            Mostra esta ajuda.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --token)
      [ "$#" -ge 2 ] || { echo "Missing value for --token" >&2; exit 1; }
      TOKEN="$2"
      shift 2
      ;;
    --skip-dependencies)
      SKIP_DEPENDENCIES=1
      shift
      ;;
    --skip-vscode)
      SKIP_VSCODE=1
      shift
      ;;
    --skip-live-tests)
      SKIP_LIVE_TESTS=1
      shift
      ;;
    --self-test)
      SELF_TEST=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
CATALOG_DIR="$CODEX_HOME_DIR/model-catalogs"
BACKUP_DIR="$CODEX_HOME_DIR/backups"
CATALOG_PATH="$CATALOG_DIR/dgsis.json"
CONFIG_PATH="$CODEX_HOME_DIR/config.toml"
ENV_FILE="$CODEX_HOME_DIR/dgsis.env"
TOKEN_HELPER_PATH="$CODEX_HOME_DIR/dgsis-token.sh"

step() {
  printf '\n==> %s\n' "$1"
}

ok() {
  printf 'OK: %s\n' "$1"
}

warn() {
  printf 'Aviso: %s\n' "$1" >&2
}

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

refresh_paths() {
  CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
  CATALOG_DIR="$CODEX_HOME_DIR/model-catalogs"
  BACKUP_DIR="$CODEX_HOME_DIR/backups"
  CATALOG_PATH="$CATALOG_DIR/dgsis.json"
  CONFIG_PATH="$CODEX_HOME_DIR/config.toml"
  ENV_FILE="$CODEX_HOME_DIR/dgsis.env"
  TOKEN_HELPER_PATH="$CODEX_HOME_DIR/dgsis-token.sh"
}

toml_quote() {
  local value="${1//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
}

shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

pick_profile() {
  case "$(uname -s):${SHELL:-}" in
    Darwin:*/zsh) printf '%s\n' "$HOME/.zprofile" ;;
    Darwin:*/bash) printf '%s\n' "$HOME/.bash_profile" ;;
    Linux:*/zsh) printf '%s\n' "$HOME/.zshrc" ;;
    Linux:*/bash) printf '%s\n' "$HOME/.bashrc" ;;
    *) printf '%s\n' "$HOME/.profile" ;;
  esac
}

persist_profile_line() {
  local file="$1" line="$2"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  if ! grep -Fqx "$line" "$file"; then
    {
      printf '\n# Codex DGSIS\n'
      printf '%s\n' "$line"
    } >>"$file"
  fi
}

persist_codex_path() {
  local profile path_line file
  profile="$(pick_profile)"
  path_line='case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac'
  persist_profile_line "$profile" "$path_line"

  case "$(uname -s)" in
    Darwin)
      for file in "$HOME/.zprofile" "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.profile"; do
        persist_profile_line "$file" "$path_line"
      done
      ;;
    Linux)
      for file in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
        persist_profile_line "$file" "$path_line"
      done
      ;;
  esac

  export PATH="$HOME/.local/bin:$PATH"
}

find_codex_command() {
  local candidate
  if command -v codex >/dev/null 2>&1; then
    command -v codex
    return 0
  fi

  for candidate in \
    "${CODEX_INSTALL_DIR:-}/codex" \
    "$HOME/.local/bin/codex" \
    "/opt/homebrew/bin/codex" \
    "/usr/local/bin/codex"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

homebrew_shellenv_line() {
  if [ -x /opt/homebrew/bin/brew ]; then
    printf '%s\n' 'eval "$(/opt/homebrew/bin/brew shellenv)"'
    return 0
  fi
  if [ -x /usr/local/bin/brew ]; then
    printf '%s\n' 'eval "$(/usr/local/bin/brew shellenv)"'
    return 0
  fi
  return 1
}

setup_homebrew_path() {
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    return 0
  fi
  if [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
    return 0
  fi
  return 1
}

install_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    return 0
  fi

  setup_homebrew_path >/dev/null 2>&1 || true
  if command -v brew >/dev/null 2>&1; then
    local existing_profile existing_brew_line
    existing_profile="$(pick_profile)"
    existing_brew_line="$(homebrew_shellenv_line || true)"
    [ -n "$existing_brew_line" ] && persist_profile_line "$existing_profile" "$existing_brew_line"
    return 0
  fi

  [ -r /dev/tty ] || fail "Homebrew nao encontrado e instalacao sem terminal interativo. Instale Homebrew ou rode sem pipe."
  step "Instalando Homebrew"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  setup_homebrew_path >/dev/null 2>&1 || fail "Homebrew instalado, mas brew nao entrou no PATH."

  local profile brew_line
  profile="$(pick_profile)"
  brew_line="$(homebrew_shellenv_line || true)"
  [ -n "$brew_line" ] && persist_profile_line "$profile" "$brew_line"
}

brew_install_formula() {
  local formula="$1" tool="${2:-$1}"
  if command -v "$tool" >/dev/null 2>&1 && brew list --formula "$formula" >/dev/null 2>&1; then
    ok "$formula ja instalado"
    return 0
  fi

  if brew list --formula "$formula" >/dev/null 2>&1; then
    if command -v "$tool" >/dev/null 2>&1; then
      ok "$formula ja instalado"
      return 0
    fi
    fail "$formula ja esta instalado, mas comando $tool nao entrou no PATH. Feche e abra o Terminal e rode de novo."
  fi

  if brew install "$formula"; then
    if command -v "$tool" >/dev/null 2>&1; then
      ok "$formula instalado"
      return 0
    fi
    fail "$formula instalado, mas comando $tool nao entrou no PATH. Feche e abra o Terminal e rode de novo."
  fi

  if command -v "$tool" >/dev/null 2>&1; then
    warn "brew install $formula retornou erro, mas $tool ja esta disponivel; continuando."
    return 0
  fi

  fail "Falha ao instalar $formula via Homebrew. Rode manualmente: brew install $formula"
}

install_mac_dependencies() {
  command -v curl >/dev/null 2>&1 || fail "curl nao encontrado."
  install_homebrew
  brew_install_formula git git
  brew_install_formula node node
  brew_install_formula python python3
}

install_linux_dependencies() {
  if command -v apt-get >/dev/null 2>&1; then
    local sudo_cmd=""
    if [ "$(id -u)" -ne 0 ]; then
      command -v sudo >/dev/null 2>&1 || { warn "sudo nao encontrado; pulando dependencias Linux."; return 0; }
      sudo_cmd="sudo"
    fi
    $sudo_cmd apt-get update
    $sudo_cmd apt-get install -y curl git python3 nodejs npm
    return 0
  fi

  if command -v brew >/dev/null 2>&1; then
    brew_install_formula git git
    brew_install_formula node node
    brew_install_formula python python3
    return 0
  fi

  warn "Gerenciador de pacotes Linux nao detectado; confirme manualmente curl, git, node e python3."
}

install_dependencies() {
  if [ "$SKIP_DEPENDENCIES" = "1" ]; then
    warn "Instalacao de dependencias pulada por --skip-dependencies."
    return 0
  fi

  case "$(uname -s)" in
    Darwin) install_mac_dependencies ;;
    Linux) install_linux_dependencies ;;
  esac
}

detect_code_cmd() {
  if command -v code >/dev/null 2>&1; then
    command -v code
    return 0
  fi

  local candidate
  for candidate in \
    "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" \
    "$HOME/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

install_vscode_extension() {
  if [ "$SKIP_VSCODE" = "1" ]; then
    warn "Instalacao do VS Code pulada por --skip-vscode."
    return 0
  fi

  local code_cmd
  code_cmd="$(detect_code_cmd 2>/dev/null || true)"

  if [ -z "$code_cmd" ] && [ "$(uname -s)" = "Darwin" ] && [ "$SKIP_DEPENDENCIES" != "1" ]; then
    setup_homebrew_path >/dev/null 2>&1 || install_homebrew
    step "Instalando Visual Studio Code"
    brew install --cask visual-studio-code || fail "Falha ao instalar Visual Studio Code via Homebrew."
    code_cmd="$(detect_code_cmd 2>/dev/null || true)"
  fi

  if [ -z "$code_cmd" ]; then
    if [ "$(uname -s)" = "Darwin" ]; then
      fail "Nao encontrei VS Code. Instale Visual Studio Code ou rode com --skip-vscode."
    fi
    warn "VS Code nao encontrado; extensao openai.chatgpt nao foi instalada."
    return 0
  fi

  "$code_cmd" --install-extension openai.chatgpt --force >/dev/null || fail "Falha ao instalar extensao openai.chatgpt."
  ok "Extensao VS Code openai.chatgpt instalada"
}

embedded_fallback_catalog() {
  cat <<'JSON'
{
  "models": [
    {
      "slug": "cx/gpt-5.5",
      "display_name": "DGSIS GPT-5.5",
      "description": "Modelo GPT-5.5 via gateway DGSIS.",
      "default_reasoning_level": "medium",
      "supported_reasoning_levels": [
        { "effort": "low", "description": "Fast responses with lighter reasoning" },
        { "effort": "medium", "description": "Balances speed and reasoning depth for everyday tasks" },
        { "effort": "high", "description": "Greater reasoning depth for complex problems" },
        { "effort": "xhigh", "description": "Extra high reasoning depth for complex problems" }
      ],
      "shell_type": "shell_command",
      "visibility": "list",
      "supported_in_api": true,
      "priority": 0,
      "additional_speed_tiers": ["fast"],
      "service_tiers": [
        { "id": "priority", "name": "Fast", "description": "1.5x speed, increased usage" }
      ],
      "availability_nux": null,
      "upgrade": null,
      "base_instructions": "You are Codex, a coding agent based on GPT-5. You help the user with software development tasks, inspect code carefully, make scoped changes, and verify your work.",
      "supports_reasoning_summaries": true,
      "default_reasoning_summary": "none",
      "support_verbosity": true,
      "default_verbosity": "low",
      "apply_patch_tool_type": "freeform",
      "web_search_tool_type": "text_and_image",
      "truncation_policy": { "mode": "tokens", "limit": 10000 },
      "supports_parallel_tool_calls": true,
      "supports_image_detail_original": true,
      "context_window": 272000,
      "max_context_window": 272000,
      "effective_context_window_percent": 95,
      "experimental_supported_tools": [],
      "input_modalities": ["text", "image"],
      "supports_search_tool": true
    }
  ]
}
JSON
}

write_fallback_catalog() {
  local script_dir local_catalog
  mkdir -p "$CATALOG_DIR"
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd -P || pwd)"
  local_catalog="$script_dir/dgsis-model-catalog.json"

  if [ -f "$local_catalog" ]; then
    cp "$local_catalog" "$CATALOG_PATH"
    return
  fi

  if curl -fsSL "$FALLBACK_CATALOG_URL" -o "$CATALOG_PATH.tmp" 2>/dev/null; then
    mv "$CATALOG_PATH.tmp" "$CATALOG_PATH"
    return
  fi

  embedded_fallback_catalog >"$CATALOG_PATH"
}

validate_catalog_file() {
  if command -v python3 >/dev/null 2>&1 && python3 --version >/dev/null 2>&1; then
    if python3 - "$CATALOG_PATH" "$DGSIS_MODEL" <<'PY'
import json
import sys
path, model = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8-sig") as fh:
    data = json.load(fh)
matches = [m for m in data.get("models", []) if m.get("slug") == model]
if len(matches) != 1:
    raise SystemExit(1)
PY
    then
      return 0
    fi
    return 1
  fi

  grep -Eq '"slug"[[:space:]]*:[[:space:]]*"cx/gpt-5\.5"' "$CATALOG_PATH" || return 1
}

remove_section_from_file() {
  local section="$1" file="$2" tmp="$3"
  awk -v section="$section" '
    {
      line=$0
      sub(/^[ \t]+/, "", line)
      sub(/[ \t]+$/, "", line)
    }
    line == "[" section "]" { skip=1; next }
    skip && line ~ /^\[.+\]$/ { skip=0 }
    !skip { print }
  ' "$file" >"$tmp"
  mv "$tmp" "$file"
}

remove_top_level_keys_from_file() {
  local file="$1" tmp="$2"
  awk '
    BEGIN {
      split("model model_provider model_reasoning_effort model_catalog_json personality service_tier approvals_reviewer", keys, " ")
      for (i in keys) wanted[keys[i]] = 1
    }
    {
      line=$0
      sub(/^[ \t]+/, "", line)
      if (line ~ /^\[.+\]/) in_section=1
      if (!in_section) {
        for (key in wanted) {
          pattern="^" key "[ \t]*="
          if (line ~ pattern) next
        }
      }
      print
    }
  ' "$file" >"$tmp"
  mv "$tmp" "$file"
}

merge_config_file() {
  mkdir -p "$CODEX_HOME_DIR" "$BACKUP_DIR"

  if [ -f "$CONFIG_PATH" ]; then
    local backup_path
    backup_path="$BACKUP_DIR/config.$(date +%Y%m%d-%H%M%S).toml"
    cp "$CONFIG_PATH" "$backup_path"
    ok "Backup criado em $backup_path"
  else
    : >"$CONFIG_PATH"
  fi

  local tmp body catalog_toml helper_toml
  tmp="$(mktemp)"
  body="$(mktemp)"
  catalog_toml="$(toml_quote "$CATALOG_PATH")"
  helper_toml="$(toml_quote "$TOKEN_HELPER_PATH")"

  cp "$CONFIG_PATH" "$body"
  remove_top_level_keys_from_file "$body" "$tmp"
  remove_section_from_file "model_providers.dgsis.auth" "$body" "$tmp"
  remove_section_from_file "model_providers.dgsis" "$body" "$tmp"
  remove_section_from_file "plugins.\"cloudflare@openai-curated\"" "$body" "$tmp"
  remove_section_from_file "plugins.\"browser@openai-bundled\"" "$body" "$tmp"
  remove_section_from_file "plugins.\"chrome@openai-bundled\"" "$body" "$tmp"
  remove_section_from_file "plugins.\"computer-use@openai-bundled\"" "$body" "$tmp"

  {
    printf 'model = "cx/gpt-5.5"\n'
    printf 'model_provider = "dgsis"\n'
    printf 'model_reasoning_effort = "xhigh"\n'
    printf 'model_catalog_json = %s\n' "$catalog_toml"
    printf 'personality = "pragmatic"\n'
    printf 'service_tier = "fast"\n'
    printf 'approvals_reviewer = "user"\n'
    printf '\n'
    cat "$body"
    printf '\n[model_providers.dgsis]\n'
    printf 'name = "DGSIS Gateway"\n'
    printf 'base_url = "https://gtw.dgsis.com.br/v1"\n'
    printf 'wire_api = "responses"\n'
    printf '\n[model_providers.dgsis.auth]\n'
    printf 'command = %s\n' "$helper_toml"
    printf 'timeout_ms = 5000\n'
    printf 'refresh_interval_ms = 0\n'
    printf '\n[plugins."cloudflare@openai-curated"]\n'
    printf 'enabled = false\n'
    printf '\n[plugins."browser@openai-bundled"]\n'
    printf 'enabled = true\n'
    printf '\n[plugins."chrome@openai-bundled"]\n'
    printf 'enabled = true\n'
    printf '\n[plugins."computer-use@openai-bundled"]\n'
    printf 'enabled = true\n'
  } >"$CONFIG_PATH"

  rm -f "$body" "$tmp"
}

write_token_helper() {
  mkdir -p "$CODEX_HOME_DIR"
  cat >"$TOKEN_HELPER_PATH" <<'SH'
#!/bin/sh
set -eu
codex_home="${CODEX_HOME:-$HOME/.codex}"
env_file="$codex_home/dgsis.env"
[ -r "$env_file" ] || exit 1
. "$env_file"
[ -n "${DGSIS_API_KEY:-}" ] || exit 1
printf '%s\n' "$DGSIS_API_KEY"
SH
  chmod 700 "$TOKEN_HELPER_PATH"
}

persist_token() {
  local token="$1" quoted profile source_line
  mkdir -p "$CODEX_HOME_DIR"
  quoted="$(shell_quote "$token")"
  {
    printf '# Codex DGSIS token. Treat this file like a password.\n'
    printf 'export DGSIS_API_KEY=%s\n' "$quoted"
  } >"$ENV_FILE"
  chmod 600 "$ENV_FILE"
  write_token_helper
  export DGSIS_API_KEY="$token"

  profile="$(pick_profile)"
  source_line="[ -f $(shell_quote "$ENV_FILE") ] && . $(shell_quote "$ENV_FILE")"
  persist_profile_line "$profile" "$source_line"

  if [ "$(uname -s)" = "Darwin" ] && command -v launchctl >/dev/null 2>&1; then
    launchctl setenv DGSIS_API_KEY "$token" >/dev/null 2>&1 || true
  fi
}

read_token() {
  if [ -n "$TOKEN" ]; then
    printf '%s\n' "$TOKEN"
    return
  fi

  if [ -n "${DGSIS_API_KEY:-}" ]; then
    if [ -r /dev/tty ]; then
      printf 'Pressione Enter para manter o token DGSIS atual, ou cole um novo token: ' >/dev/tty
      IFS= read -r input </dev/tty || true
      if [ -n "$input" ]; then
        printf '%s\n' "$input"
      else
        printf '%s\n' "$DGSIS_API_KEY"
      fi
    else
      printf '%s\n' "$DGSIS_API_KEY"
    fi
    return
  fi

  if [ ! -r /dev/tty ]; then
    fail "Token DGSIS nao informado. Rode com DGSIS_API_KEY=seu_token antes do comando."
  fi

  printf 'Cole seu token DGSIS: ' >/dev/tty
  IFS= read -r input </dev/tty || true
  [ -n "$input" ] || fail "Token DGSIS nao informado."
  printf '%s\n' "$input"
}

validate_token() {
  local token="$1" response http_code
  response="$(mktemp)"
  http_code="$(curl -sS -o "$response" -w '%{http_code}' -H "Authorization: Bearer $token" "$DGSIS_BASE_URL/models" || true)"
  if [ "$http_code" != "200" ]; then
    rm -f "$response"
    fail "Nao foi possivel validar o token no gateway DGSIS. HTTP $http_code."
  fi
  if ! grep -Eq '"id"[[:space:]]*:[[:space:]]*"cx/gpt-5\.5"' "$response"; then
    rm -f "$response"
    fail "O token foi aceito, mas o modelo $DGSIS_MODEL nao apareceu em /models."
  fi
  rm -f "$response"
}

install_codex_cli() {
  local installer codex_cmd
  installer="$(mktemp)"
  curl -fsSL "$CODEX_INSTALL_URL" -o "$installer"
  CODEX_NON_INTERACTIVE=1 sh "$installer"
  rm -f "$installer"

  persist_codex_path
  codex_cmd="$(find_codex_command || true)"
  if [ -z "$codex_cmd" ]; then
    fail "Nao encontrei o comando codex apos a instalacao. Verifique se existe $HOME/.local/bin/codex e rode: export PATH=\"$HOME/.local/bin:\$PATH\""
  fi
  "$codex_cmd" --version >/dev/null
}

generate_catalog() {
  mkdir -p "$CATALOG_DIR"
  local codex_cmd models_source
  codex_cmd="$(find_codex_command || true)"
  models_source="$CATALOG_PATH.models"
  rm -f "$models_source"

  if [ "$SKIP_LIVE_TESTS" != "1" ] && [ -n "${DGSIS_API_KEY:-}" ]; then
    curl -fsSL -H "Authorization: Bearer $DGSIS_API_KEY" "$DGSIS_BASE_URL/models" -o "$models_source" 2>/dev/null || rm -f "$models_source"
  fi

  if command -v python3 >/dev/null 2>&1 && python3 --version >/dev/null 2>&1 && [ -n "$codex_cmd" ] && [ -f "$models_source" ] && "$codex_cmd" debug models --bundled >"$CATALOG_PATH.source" 2>/dev/null; then
    if python3 - "$CATALOG_PATH.source" "$models_source" "$CATALOG_PATH" "$DGSIS_MODEL" <<'PY'
import json
import re
import sys
src, models_src, dst, default_model = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

blocked = re.compile(r"claude|anthropic|gemini|deepseek|qwen|llama|mistral|kimi|glm|minimax|grok|oss", re.I)

def is_openai_model(model_id):
    return bool(re.match(r"^cx/(gpt-|o[0-9]|codex-|chatgpt-)", model_id or "")) and not blocked.search(model_id or "")

def candidates(model_id):
    slug = re.sub(r"^cx/", "", model_id)
    out = [slug]
    no_review = re.sub(r"-review$", "", slug)
    if no_review != slug:
        out.append(no_review)
    base = re.sub(r"-(none|low|medium|high|xhigh|spark)$", "", no_review)
    if base != no_review:
        out.append(base)
    for prefix, template in [
        ("gpt-5.3-codex", "gpt-5.3-codex"),
        ("gpt-5.4-mini", "gpt-5.4-mini"),
        ("gpt-5.4", "gpt-5.4"),
        ("gpt-5.5", "gpt-5.5"),
    ]:
        if slug.startswith(prefix):
            out.append(template)
    seen = set()
    return [item for item in out if item and not (item in seen or seen.add(item))]

def display_name(model_id):
    slug = re.sub(r"^cx/", "", model_id)
    parts = []
    for part in slug.split("-"):
        if not part:
            continue
        if part == "gpt" or part == "codex" or re.match(r"^o[0-9]", part):
            parts.append(part.upper())
        else:
            parts.append(part[:1].upper() + part[1:])
    return "DGSIS " + " ".join(parts)

with open(src, "r", encoding="utf-8-sig") as fh:
    bundled = json.load(fh)
with open(models_src, "r", encoding="utf-8-sig") as fh:
    api_models = json.load(fh)

model_ids = sorted({item.get("id", "") for item in api_models.get("data", []) if is_openai_model(item.get("id", ""))})
if default_model not in model_ids:
    raise SystemExit(1)

templates = {m.get("slug"): m for m in bundled.get("models", []) if m.get("slug")}
default_template = templates.get("gpt-5.5") or next(iter(templates.values()), None)
if default_template is None:
    raise SystemExit(1)

models = []
for index, model_id in enumerate(model_ids):
    template = None
    for candidate in candidates(model_id):
        if candidate in templates:
            template = templates[candidate]
            break
    if template is None:
        template = default_template
    model = json.loads(json.dumps(template))
    model["slug"] = model_id
    model["display_name"] = display_name(model_id)
    model["description"] = f"Modelo OpenAI {model_id} via gateway DGSIS."
    model["visibility"] = "list"
    model["supported_in_api"] = True
    model["priority"] = 0 if model_id == default_model else index + 10
    if "availability_nux" in model:
        model["availability_nux"] = None
    models.append(model)

with open(dst, "w", encoding="utf-8") as fh:
    json.dump({"models": models}, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
PY
    then
      rm -f "$CATALOG_PATH.source" "$models_source"
      validate_catalog_file || fail "Catalogo DGSIS gerado localmente e invalido."
      if grep -Eiq 'claude|anthropic|gemini|deepseek|qwen|llama|mistral|kimi|glm|minimax|grok|oss' "$CATALOG_PATH"; then
        fail "Catalogo DGSIS invalido: contem modelos que nao sao OpenAI."
      fi
      return
    fi
  fi

  rm -f "$CATALOG_PATH.source" "$models_source"
  warn "usando catalogo fallback DGSIS."
  write_fallback_catalog
  validate_catalog_file || fail "Catalogo fallback DGSIS invalido."
}

validate_codex_config() {
  local models_file err_file
  models_file="$(mktemp)"
  err_file="$(mktemp)"
  codex debug models >"$models_file" 2>"$err_file" || {
    cat "$err_file" >&2
    rm -f "$models_file" "$err_file"
    fail "O Codex nao carregou o catalogo DGSIS corretamente."
  }
  grep -Eq '"slug"[[:space:]]*:[[:space:]]*"cx/gpt-5\.5"' "$models_file" || {
    rm -f "$models_file" "$err_file"
    fail "O Codex nao carregou o modelo cx/gpt-5.5."
  }
  rm -f "$models_file" "$err_file"
}

validate_strict_config() {
  codex --strict-config --version >/dev/null 2>&1 || fail "codex --strict-config falhou. Revise config.toml."
}

run_doctor_test() {
  local doctor_file
  doctor_file="$(mktemp)"
  codex doctor --json >"$doctor_file" 2>&1 || {
    cat "$doctor_file" >&2
    rm -f "$doctor_file"
    fail "codex doctor falhou."
  }
  if grep -Eiq '"status"[[:space:]]*:[[:space:]]*"(warn|warning|fail|error)"' "$doctor_file"; then
    cat "$doctor_file" >&2
    rm -f "$doctor_file"
    fail "codex doctor retornou warning/fail."
  fi
  rm -f "$doctor_file"
}

run_final_test() {
  local last_file log_file
  last_file="$(mktemp)"
  log_file="$(mktemp)"
  if ! DGSIS_API_KEY="$DGSIS_API_KEY" codex exec --ephemeral --skip-git-repo-check -o "$last_file" "Responda exatamente CODEX_DGSIS_OK e nada mais." >"$log_file" 2>&1; then
    cat "$log_file" >&2
    rm -f "$last_file" "$log_file"
    fail "O teste final do Codex falhou."
  fi
  grep -Eq 'model:[[:space:]]*cx/gpt-5\.5' "$log_file" || {
    cat "$log_file" >&2
    rm -f "$last_file" "$log_file"
    fail "O Codex respondeu, mas nao iniciou com model: cx/gpt-5.5."
  }
  grep -Eq '^CODEX_DGSIS_OK[[:space:]]*$' "$last_file" || {
    cat "$last_file" >&2
    rm -f "$last_file" "$log_file"
    fail "O Codex respondeu, mas nao retornou CODEX_DGSIS_OK."
  }
  rm -f "$last_file" "$log_file"
}

run_shell_tool_test() {
  local jsonl_file last_file
  jsonl_file="$(mktemp)"
  last_file="$(mktemp)"
  if ! DGSIS_API_KEY="$DGSIS_API_KEY" codex exec --ephemeral --skip-git-repo-check --json -o "$last_file" "Use uma ferramenta de shell para executar um comando que imprime CODEX_DGSIS_SHELL_OK. Depois responda exatamente CODEX_DGSIS_SHELL_OK e nada mais." >"$jsonl_file" 2>&1; then
    cat "$jsonl_file" >&2
    rm -f "$jsonl_file" "$last_file"
    fail "Teste de shell tool falhou."
  fi
  grep -Eq '^CODEX_DGSIS_SHELL_OK[[:space:]]*$' "$last_file" || {
    cat "$last_file" >&2
    rm -f "$jsonl_file" "$last_file"
    fail "Shell tool executou, mas resposta final nao foi CODEX_DGSIS_SHELL_OK."
  }
  grep -Eq '"exit_code"[[:space:]]*:[[:space:]]*0|exit_code.:0' "$jsonl_file" || {
    cat "$jsonl_file" >&2
    rm -f "$jsonl_file" "$last_file"
    fail "JSONL nao confirmou shell command com exit_code 0."
  }
  if grep -Eiq 'sandbox: runner error|CreateProcessAsUserW failed|permission denied' "$jsonl_file"; then
    cat "$jsonl_file" >&2
    rm -f "$jsonl_file" "$last_file"
    fail "Shell tool retornou erro de sandbox/permissao."
  fi
  rm -f "$jsonl_file" "$last_file"
}

self_test() {
  step "Executando autotestes Unix"
  local tmp old_home old_codex_home old_path profile mode fakebin
  tmp="$(mktemp -d)"
  old_home="$HOME"
  old_codex_home="${CODEX_HOME:-}"
  HOME="$tmp/home"
  unset CODEX_HOME
  export HOME
  mkdir -p "$HOME"
  refresh_paths
  mkdir -p "$CODEX_HOME_DIR"
  cat >"$CONFIG_PATH" <<'EOF'
model = "gpt-5.5"
model_provider = "old"
service_tier = "standard"

[model_providers.dgsis]
name = "old"
env_key = "DGSIS_API_KEY"

[model_providers.dgsis.auth]
command = "/tmp/old"

[plugins."cloudflare@openai-curated"]
enabled = true

[plugins."browser@openai-bundled"]
enabled = false
EOF

  write_fallback_catalog
  validate_catalog_file
  persist_token "self-test-token"
  persist_token "self-test-token"
  merge_config_file
  merge_config_file

  [ "$(grep -Ec '^model = "cx/gpt-5\.5"$' "$CONFIG_PATH")" = "1" ] || fail "Autoteste falhou: model duplicado ou ausente."
  [ "$(grep -Ec '^model_provider = "dgsis"$' "$CONFIG_PATH")" = "1" ] || fail "Autoteste falhou: model_provider duplicado ou ausente."
  [ "$(grep -Ec '^\[model_providers\.dgsis\]$' "$CONFIG_PATH")" = "1" ] || fail "Autoteste falhou: provider duplicado ou ausente."
  [ "$(grep -Ec '^\[model_providers\.dgsis\.auth\]$' "$CONFIG_PATH")" = "1" ] || fail "Autoteste falhou: auth duplicado ou ausente."
  [ "$(grep -Ec '^\[plugins\."cloudflare@openai-curated"\]$' "$CONFIG_PATH")" = "1" ] || fail "Autoteste falhou: cloudflare duplicado ou ausente."
  [ "$(grep -Ec '^\[plugins\."browser@openai-bundled"\]$' "$CONFIG_PATH")" = "1" ] || fail "Autoteste falhou: browser plugin duplicado ou ausente."
  [ "$(grep -Ec '^\[plugins\."chrome@openai-bundled"\]$' "$CONFIG_PATH")" = "1" ] || fail "Autoteste falhou: chrome plugin duplicado ou ausente."
  [ "$(grep -Ec '^\[plugins\."computer-use@openai-bundled"\]$' "$CONFIG_PATH")" = "1" ] || fail "Autoteste falhou: computer-use plugin duplicado ou ausente."
  ! grep -Eq '^env_key[[:space:]]*=' "$CONFIG_PATH" || fail "Autoteste falhou: env_key permaneceu no provider DGSIS."
  [ -f "$ENV_FILE" ] || fail "Autoteste falhou: dgsis.env nao criado."
  [ -x "$TOKEN_HELPER_PATH" ] || fail "Autoteste falhou: helper de token nao executavel."
  [ "$("$TOKEN_HELPER_PATH")" = "self-test-token" ] || fail "Autoteste falhou: helper nao retornou token."

  case "$(uname -s)" in
    Darwin|Linux)
      mode="$(stat -c '%a' "$ENV_FILE" 2>/dev/null || stat -f '%Lp' "$ENV_FILE")"
      [ "$mode" = "600" ] || fail "Autoteste falhou: dgsis.env sem permissao 600."
      ;;
  esac

  profile="$(pick_profile)"
  [ "$(grep -Fc 'dgsis.env' "$profile")" = "1" ] || fail "Autoteste falhou: profile com source duplicado."
  persist_codex_path
  [ "$(grep -Fc '.local/bin' "$profile")" -ge "1" ] || fail "Autoteste falhou: PATH do Codex nao foi salvo no profile."

  fakebin="$tmp/bin"
  old_path="$PATH"
  mkdir -p "$fakebin"
  cat >"$fakebin/brew" <<'SH'
#!/bin/sh
case "$1" in
  list) exit 1 ;;
  install) exit 1 ;;
  *) exit 1 ;;
esac
SH
  cat >"$fakebin/python3" <<'SH'
#!/bin/sh
exit 0
SH
  chmod 755 "$fakebin/brew" "$fakebin/python3"
  PATH="$fakebin:$PATH"
  brew_install_formula python python3
  PATH="$old_path"

  HOME="$old_home"
  export HOME
  if [ -n "$old_codex_home" ]; then
    CODEX_HOME="$old_codex_home"
    export CODEX_HOME
  else
    unset CODEX_HOME
  fi
  refresh_paths
  rm -rf "$tmp"
  ok "Autotestes Unix passaram"
}

if [ "$SELF_TEST" = "1" ]; then
  self_test
  exit 0
fi

case "$(uname -s)" in
  Darwin|Linux) ;;
  *) fail "Este instalador e somente para macOS/Linux. No Windows use install.ps1." ;;
esac

step "Solicitando token DGSIS"
token="$(read_token)"

if [ "$SKIP_LIVE_TESTS" = "1" ]; then
  warn "Validacao viva do token pulada por --skip-live-tests."
  persist_token "$token"
else
  step "Validando token e modelo no gateway DGSIS"
  validate_token "$token"
  persist_token "$token"
  ok "Token validado e salvo em $ENV_FILE"
fi

step "Instalando dependencias do sistema"
install_dependencies
ok "Dependencias verificadas"

step "Instalando ou atualizando Codex CLI standalone"
install_codex_cli
codex_cmd="$(find_codex_command || true)"
[ -n "$codex_cmd" ] || fail "Codex CLI instalado, mas comando nao foi encontrado."
ok "Codex CLI pronto: $("$codex_cmd" --version)"

step "Instalando Codex no VS Code"
install_vscode_extension

step "Gerando catalogo local DGSIS para o seletor de modelos"
generate_catalog
ok "Catalogo criado em $CATALOG_PATH"

step "Mesclando configuracao do Codex"
merge_config_file
ok "config.toml atualizado em $CONFIG_PATH"

step "Validando configuracao local do Codex"
validate_codex_config
validate_strict_config
ok "Catalogo DGSIS carregado pelo Codex"

if [ "$SKIP_LIVE_TESTS" = "1" ]; then
  warn "Testes vivos do Codex pulados por --skip-live-tests."
else
  step "Executando codex doctor"
  run_doctor_test
  ok "codex doctor sem warning/fail"

  step "Executando teste final do Codex CLI com gateway DGSIS"
  run_final_test
  ok "Codex respondeu com model: cx/gpt-5.5"

  step "Executando teste real de shell tool"
  run_shell_tool_test
  ok "Shell tool executou comando real sem erro"
fi

printf '\nInstalacao concluida.\n'
printf 'Feche e abra um novo Terminal e execute: codex\n'
printf 'No topo do Codex deve aparecer: model: cx/gpt-5.5\n'
printf 'No VS Code, abra a barra lateral Codex/ChatGPT. A extensao usa a mesma configuracao local.\n'
