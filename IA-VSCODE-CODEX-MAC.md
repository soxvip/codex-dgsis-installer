# Roteiro para IA deixar Codex funcionando no VS Code no macOS

Use este arquivo quando o cliente quer usar Codex pela lateral do VS Code no Mac. O objetivo e abrir o chat Codex/ChatGPT no VS Code ja funcionando com DGSIS, sem login OpenAI pelo site.

## Premissa

O instalador principal deve ser executado primeiro:

```bash
curl -fsSL https://raw.githubusercontent.com/soxvip/codex-dgsis-installer/main/install.sh | bash
```

Ele instala VS Code, extensao `openai.chatgpt`, Codex CLI, token em `~/.codex/dgsis.env` e configuracao `~/.codex/config.toml`.

## Checagem do VS Code

Execute:

```bash
command -v code || true
code --version || "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" --version
code --list-extensions | grep -i '^openai.chatgpt$' || "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" --list-extensions | grep -i '^openai.chatgpt$'
```

Se `code` nao existir e o caminho direto tambem falhar, instale VS Code:

```bash
brew install --cask visual-studio-code
```

Depois instale a extensao:

```bash
code --install-extension openai.chatgpt --force || "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" --install-extension openai.chatgpt --force
```

## Checagem do Codex local

Execute em nova janela Terminal:

```bash
codex --version
codex doctor --json
grep -n 'model = "cx/gpt-5.5"' ~/.codex/config.toml
grep -n 'model_provider = "dgsis"' ~/.codex/config.toml
grep -nF '[model_providers.dgsis.auth]' ~/.codex/config.toml
~/.codex/dgsis-token.sh >/dev/null && echo TOKEN_HELPER_OK
```

Confirme no `config.toml`:

```toml
model = "cx/gpt-5.5"
model_provider = "dgsis"

[model_providers.dgsis]
base_url = "https://gtw.dgsis.com.br/v1"
wire_api = "responses"

[model_providers.dgsis.auth]
command = "/Users/CLIENTE/.codex/dgsis-token.sh"
timeout_ms = 5000
refresh_interval_ms = 0
```

Nao mostre o token na resposta final. Nao execute `cat ~/.codex/dgsis.env`.

## Abrir VS Code do jeito certo

Abra VS Code normalmente ou pelo Terminal:

```bash
mkdir -p "$HOME/codex-test-project"
cd "$HOME/codex-test-project"
code . || "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" .
```

No VS Code:

1. Aguarde extensoes carregarem.
2. Procure Codex/ChatGPT na barra lateral.
3. Abra chat.
4. Envie: `Responda apenas: ok`.

Esperado: resposta `ok` sem login pelo site.

## Se VS Code pedir login

1. Feche todas as janelas VS Code.
2. Confirme que o helper funciona sem imprimir token:

```bash
~/.codex/dgsis-token.sh >/dev/null && echo TOKEN_HELPER_OK
```

3. Confirme que Codex CLI funciona fora do VS Code:

```bash
out="$(mktemp)"
codex exec --ephemeral --skip-git-repo-check -o "$out" "Responda exatamente CODEX_VSCODE_OK e nada mais."
cat "$out"
rm -f "$out"
```

4. Abra VS Code novamente pelo Terminal:

```bash
code . || "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" .
```

Se CLI funciona e VS Code ainda pede login, reinstale extensao:

```bash
code --uninstall-extension openai.chatgpt || true
code --install-extension openai.chatgpt --force || "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" --install-extension openai.chatgpt --force
```

Depois reinicie VS Code.

## Checklist final para IA

- `code --list-extensions` contem `openai.chatgpt`.
- `codex doctor --json` sem warning/fail.
- `codex exec` responde usando `cx/gpt-5.5`.
- `~/.codex/dgsis-token.sh >/dev/null` retorna sucesso.
- Chat lateral responde sem login pelo site.
- Token nao foi exibido na resposta final.
