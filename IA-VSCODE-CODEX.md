# Roteiro para IA deixar Codex funcionando no VS Code

Use este arquivo quando o cliente quer usar Codex pela lateral do VS Code. O objetivo e abrir o chat Codex/ChatGPT no VS Code ja funcionando com DGSIS, sem login OpenAI pelo site.

## Premissa

O instalador principal deve ser executado primeiro:

```powershell
irm https://raw.githubusercontent.com/soxvip/codex-dgsis-installer/main/install.ps1 | iex
```

Ele instala VS Code, extensao `openai.chatgpt`, Codex CLI, token `DGSIS_API_KEY` e configuracao `%USERPROFILE%\.codex\config.toml`.

## Checagem do VS Code

Execute:

```powershell
Get-Command code -ErrorAction SilentlyContinue
code --version
code --list-extensions | Select-String -Pattern "openai.chatgpt"
```

Se `code` nao existir, instale VS Code:

```powershell
winget install --id Microsoft.VisualStudioCode --exact --accept-package-agreements --accept-source-agreements --disable-interactivity
```

Feche e abra PowerShell. Depois instale extensao:

```powershell
code --install-extension openai.chatgpt --force
```

## Checagem do Codex local

Execute em nova janela PowerShell:

```powershell
codex --version
codex doctor --json
[Environment]::GetEnvironmentVariable("DGSIS_API_KEY", "User") -ne $null
Get-Content "$env:USERPROFILE\.codex\config.toml"
```

Confirme no `config.toml`:

```toml
model = "cx/gpt-5.5"
model_provider = "dgsis"

[model_providers.dgsis]
base_url = "https://gtw.dgsis.com.br/v1"
wire_api = "responses"
env_key = "DGSIS_API_KEY"
```

Nao mostre o token na resposta final.

## Abrir VS Code do jeito certo

Para garantir que VS Code herde o ambiente atualizado, abra por uma nova janela PowerShell:

```powershell
mkdir "$env:USERPROFILE\codex-test-project" -Force | Out-Null
cd "$env:USERPROFILE\codex-test-project"
code .
```

No VS Code:

1. Aguarde extensoes carregarem.
2. Procure Codex/ChatGPT na barra lateral direita.
3. Abra chat.
4. Envie: `Responda apenas: ok`.

Esperado: resposta `ok` sem login pelo site.

## Se VS Code pedir login

1. Feche todas as janelas VS Code.
2. Confirme que token existe:

```powershell
[Environment]::GetEnvironmentVariable("DGSIS_API_KEY", "User")
```

3. Abra VS Code a partir de nova sessao PowerShell:

```powershell
code .
```

4. Confirme que Codex CLI funciona fora do VS Code:

```powershell
$out = Join-Path $env:TEMP "codex-vscode-check.txt"
codex exec --ephemeral --skip-git-repo-check -o $out "Responda exatamente CODEX_VSCODE_OK e nada mais."
Get-Content $out
Remove-Item $out -Force
```

Se CLI funciona e VS Code ainda pede login, reinstale extensao:

```powershell
code --uninstall-extension openai.chatgpt
code --install-extension openai.chatgpt --force
```

Depois reinicie VS Code.

## Se ferramenta shell falhar no VS Code

Erro comum:

```text
CreateProcessAsUserW failed: 1312
```

Correcao:

```powershell
irm https://raw.githubusercontent.com/soxvip/codex-dgsis-installer/main/install.ps1 | iex
where.exe pwsh
```

O primeiro resultado de `where.exe pwsh` deve ser:

```text
%LOCALAPPDATA%\Programs\OpenAI\Codex\bin\pwsh.exe
```

## Checklist final para IA

- `code --list-extensions` contem `openai.chatgpt`.
- `codex doctor --json` sem warning/fail.
- `codex exec` responde com `cx/gpt-5.5`.
- VS Code foi aberto de nova sessao PowerShell.
- Chat lateral responde sem login pelo site.
- Token nao foi exibido na resposta final.
