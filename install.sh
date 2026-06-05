#!/usr/bin/env bash
set -euo pipefail

DGSIS_BASE_URL="https://gtw.dgsis.com.br/v1"
DGSIS_MODEL="cx/gpt-5.5"
ENV_KEY_NAME="DGSIS_API_KEY"
CODEX_INSTALL_URL="https://chatgpt.com/codex/install.sh"
FALLBACK_CATALOG_URL="https://raw.githubusercontent.com/soxvip/codex-dgsis-installer/main/dgsis-model-catalog.json"
TOKEN=""
SELF_TEST=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --token)
      [ "$#" -ge 2 ] || { echo "Missing value for --token" >&2; exit 1; }
      TOKEN="$2"
      shift 2
      ;;
    --self-test)
      SELF_TEST=1
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
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

step() {
  printf '\n==> %s\n' "$1"
}

ok() {
  printf 'OK: %s\n' "$1"
}

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

refresh_paths() {
  CATALOG_DIR="$CODEX_HOME_DIR/model-catalogs"
  BACKUP_DIR="$CODEX_HOME_DIR/backups"
  CATALOG_PATH="$CATALOG_DIR/dgsis.json"
  CONFIG_PATH="$CODEX_HOME_DIR/config.toml"
  ENV_FILE="$CODEX_HOME_DIR/dgsis.env"
}

toml_quote() {
  local value="${1//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
}

shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
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
      return
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

set_section_key_in_file() {
  local section="$1" key="$2" value_line="$3" file="$4" tmp="$5"
  awk -v section="$section" -v key="$key" -v value_line="$value_line" '
    function trim(value) {
      sub(/^[ \t]+/, "", value)
      sub(/[ \t]+$/, "", value)
      return value
    }
    BEGIN {
      found_section=0
      in_section=0
      wrote_key=0
    }
    {
      line=$0
      clean=trim(line)
      if (clean == "[" section "]") {
        found_section=1
        in_section=1
        wrote_key=0
        print
        next
      }
      if (in_section && clean ~ /^\[.+\]$/) {
        if (!wrote_key) {
          print value_line
          wrote_key=1
        }
        in_section=0
      }
      if (in_section) {
        pattern="^" key "[ \t]*="
        if (clean ~ pattern) {
          if (!wrote_key) {
            print value_line
            wrote_key=1
          }
          next
        }
      }
      print
    }
    END {
      if (in_section && !wrote_key) {
        print value_line
      }
      if (!found_section) {
        print ""
        print "[" section "]"
        print value_line
      }
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

  local tmp body catalog_toml
  tmp="$(mktemp)"
  body="$(mktemp)"
  catalog_toml="$(toml_quote "$CATALOG_PATH")"

  cp "$CONFIG_PATH" "$body"
  remove_top_level_keys_from_file "$body" "$tmp"
  remove_section_from_file "model_providers.dgsis" "$body" "$tmp"
  remove_section_from_file "plugins.\"cloudflare@openai-curated\"" "$body" "$tmp"
  set_section_key_in_file "windows" "sandbox" 'sandbox = "elevated"' "$body" "$tmp"

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
    printf 'env_key = "DGSIS_API_KEY"\n'
    printf '\n[plugins."cloudflare@openai-curated"]\n'
    printf 'enabled = false\n'
  } >"$CONFIG_PATH"

  rm -f "$body" "$tmp"
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

persist_token() {
  local token="$1" quoted profile source_line
  mkdir -p "$CODEX_HOME_DIR"
  quoted="$(shell_quote "$token")"
  {
    printf '# Codex DGSIS token. Treat this file like a password.\n'
    printf 'export DGSIS_API_KEY=%s\n' "$quoted"
  } >"$ENV_FILE"
  chmod 600 "$ENV_FILE"
  export DGSIS_API_KEY="$token"

  profile="$(pick_profile)"
  source_line='[ -f "$HOME/.codex/dgsis.env" ] && . "$HOME/.codex/dgsis.env"'
  touch "$profile"
  if ! grep -Fqx "$source_line" "$profile"; then
    {
      printf '\n# Codex DGSIS\n'
      printf '%s\n' "$source_line"
    } >>"$profile"
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
  local installer
  installer="$(mktemp)"
  curl -fsSL "$CODEX_INSTALL_URL" -o "$installer"
  CODEX_NON_INTERACTIVE=1 bash "$installer"
  rm -f "$installer"

  export PATH="$HOME/.local/bin:$PATH"
  if ! command -v codex >/dev/null 2>&1; then
    fail "Nao encontrei o comando codex apos a instalacao."
  fi
  codex --version >/dev/null
}

generate_catalog() {
  mkdir -p "$CATALOG_DIR"
  if command -v python3 >/dev/null 2>&1 && python3 --version >/dev/null 2>&1 && codex debug models --bundled >"$CATALOG_PATH.source" 2>/dev/null; then
    if python3 - "$CATALOG_PATH.source" "$CATALOG_PATH" "$DGSIS_MODEL" <<'PY'
import json
import sys
src, dst, model_slug = sys.argv[1], sys.argv[2], sys.argv[3]
with open(src, "r", encoding="utf-8-sig") as fh:
    data = json.load(fh)
matches = [m for m in data.get("models", []) if m.get("slug") == "gpt-5.5"]
if not matches:
    raise SystemExit(1)
model = matches[0]
model["slug"] = model_slug
model["display_name"] = "DGSIS GPT-5.5"
model["description"] = "Modelo GPT-5.5 via gateway DGSIS."
model["availability_nux"] = None
with open(dst, "w", encoding="utf-8") as fh:
    json.dump({"models": [model]}, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
PY
    then
      rm -f "$CATALOG_PATH.source"
      validate_catalog_file || fail "Catalogo DGSIS gerado localmente e invalido."
      return
    fi
  fi

  rm -f "$CATALOG_PATH.source"
  printf 'Aviso: usando catalogo fallback DGSIS.\n' >&2
  write_fallback_catalog
  validate_catalog_file || fail "Catalogo fallback DGSIS invalido."
}

validate_codex_config() {
  codex debug models >/tmp/codex-dgsis-models.$$ 2>/tmp/codex-dgsis-models.err.$$ || {
    cat /tmp/codex-dgsis-models.err.$$ >&2
    rm -f /tmp/codex-dgsis-models.$$ /tmp/codex-dgsis-models.err.$$
    fail "O Codex nao carregou o catalogo DGSIS corretamente."
  }
  grep -Eq '"slug"[[:space:]]*:[[:space:]]*"cx/gpt-5\.5"' /tmp/codex-dgsis-models.$$ || {
    rm -f /tmp/codex-dgsis-models.$$ /tmp/codex-dgsis-models.err.$$
    fail "O Codex nao carregou o modelo cx/gpt-5.5."
  }
  rm -f /tmp/codex-dgsis-models.$$ /tmp/codex-dgsis-models.err.$$
}

run_final_test() {
  local output
  output="$(DGSIS_API_KEY="$DGSIS_API_KEY" codex exec --skip-git-repo-check --sandbox read-only "Responda apenas: ok" </dev/null 2>&1)" || {
    printf '%s\n' "$output" >&2
    fail "O teste final do Codex falhou."
  }
  printf '%s\n' "$output" | grep -Eq 'model:[[:space:]]*cx/gpt-5\.5' || fail "O Codex respondeu, mas nao iniciou com model: cx/gpt-5.5."
  printf '%s\n' "$output" | grep -Eq '(^|[[:space:]])ok([[:space:]]|$)' || fail "O Codex respondeu, mas nao retornou ok."
}

self_test() {
  step "Executando autotestes Unix"
  local tmp old_home
  tmp="$(mktemp -d)"
  old_home="$HOME"
  HOME="$tmp/home"
  mkdir -p "$HOME"
  CODEX_HOME_DIR="$tmp/.codex"
  refresh_paths
  mkdir -p "$CODEX_HOME_DIR"
  cat >"$CONFIG_PATH" <<'EOF'
model = "gpt-5.5"

[model_providers.dgsis]
name = "old"

[plugins."cloudflare@openai-curated"]
enabled = true

[windows]
sandbox = "workspace-write"
EOF
  write_fallback_catalog
  validate_catalog_file
  merge_config_file
  [ "$(grep -Ec '^model = "cx/gpt-5\.5"$' "$CONFIG_PATH")" = "1" ] || fail "Autoteste falhou: model duplicado ou ausente."
  [ "$(grep -Ec '^\[model_providers\.dgsis\]$' "$CONFIG_PATH")" = "1" ] || fail "Autoteste falhou: provider duplicado ou ausente."
  [ "$(grep -Ec '^\[plugins\."cloudflare@openai-curated"\]$' "$CONFIG_PATH")" = "1" ] || fail "Autoteste falhou: cloudflare duplicado ou ausente."
  [ "$(grep -Ec '^sandbox = "elevated"$' "$CONFIG_PATH")" = "1" ] || fail "Autoteste falhou: windows sandbox duplicado ou ausente."
  persist_token "self-test-token"
  [ -f "$ENV_FILE" ] || fail "Autoteste falhou: dgsis.env nao criado."
  case "$(uname -s)" in
    Darwin|Linux)
      [ "$(stat -c '%a' "$ENV_FILE" 2>/dev/null || stat -f '%Lp' "$ENV_FILE")" = "600" ] || fail "Autoteste falhou: dgsis.env sem permissao 600."
      ;;
  esac
  HOME="$old_home"
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

step "Instalando ou atualizando o Codex CLI standalone"
install_codex_cli
ok "Codex CLI pronto: $(codex --version)"

step "Solicitando token DGSIS"
token="$(read_token)"

step "Validando token e modelo no gateway DGSIS"
validate_token "$token"
persist_token "$token"
ok "Token validado e salvo em $ENV_FILE"

step "Gerando catalogo local DGSIS para o seletor de modelos"
generate_catalog
ok "Catalogo criado em $CATALOG_PATH"

step "Mesclando configuracao do Codex"
merge_config_file
ok "Config.toml atualizado em $CONFIG_PATH"

step "Validando configuracao do catalogo"
validate_codex_config
ok "Catalogo DGSIS carregado pelo Codex"

step "Executando teste final do Codex CLI com o gateway DGSIS"
run_final_test
ok "Codex respondeu com model: cx/gpt-5.5"

printf '\nInstalacao concluida.\n'
printf 'Feche e abra um novo terminal e execute: codex\n'
printf 'No topo do Codex deve aparecer: model: cx/gpt-5.5\n'
