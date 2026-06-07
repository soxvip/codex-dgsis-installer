# Roteiro para IA instalar Codex DGSIS no Windows do cliente

Use este arquivo como instrucao operacional para outro agente de IA que esteja controlando a maquina do cliente.

Objetivo: deixar Codex CLI, Codex Desktop e Codex no VS Code funcionando com gateway DGSIS, sem login OpenAI pelo site, usando token DGSIS informado pelo cliente.

## Regra de seguranca sobre token

Peca o token DGSIS ao cliente apenas no momento da instalacao.

Nao registre o token em logs, prints, respostas finais, README, issue, commit, historico compartilhado ou arquivo do projeto. O token deve ser colado no prompt seguro do instalador ou passado como variavel local temporaria apenas se o cliente autorizar.

Frase sugerida ao cliente:

```text
Cole agora seu token DGSIS. Ele sera salvo como variavel de usuario DGSIS_API_KEY nesta maquina e nao sera enviado para mim em texto final.
```

## Pre-checagem

Execute em PowerShell:

```powershell
$PSVersionTable.PSVersion
[Environment]::Is64BitOperatingSystem
Get-Command winget -ErrorAction SilentlyContinue
```

Se `winget` nao existir, oriente o cliente a instalar ou atualizar `App Installer` pela Microsoft Store. Depois continue.

## Instalacao padrao

Execute:

```powershell
irm https://raw.githubusercontent.com/soxvip/codex-dgsis-installer/main/install.ps1 | iex
```

Quando o instalador pedir, o cliente deve colar o token DGSIS.

Nao pule os testes vivos. Eles confirmam que o gateway, o modelo e a ferramenta shell estao funcionando.

## Token durante a instalacao

Preferencia: deixe o proprio instalador pedir o token. Nao passe o token na linha de comando, porque comandos podem ficar no historico do terminal.

Se precisar reinstalar ou trocar token, rode o mesmo comando de instalacao e deixe o cliente colar o novo token quando solicitado.

## O instalador deve fazer

- Instalar Git, Node.js LTS, Python e VS Code via `winget`.
- Instalar Codex CLI oficial.
- Instalar ou abrir Codex Desktop via `codex app`.
- Instalar extensao VS Code `openai.chatgpt`.
- Salvar token em variavel de usuario `DGSIS_API_KEY`.
- Criar `%USERPROFILE%\.codex\model-catalogs\dgsis.json` com modelos OpenAI retornados por `/models`.
- Excluir modelos Claude, Gemini, DeepSeek, Qwen, Llama, Mistral e similares do catalogo local.
- Atualizar `%USERPROFILE%\.codex\config.toml` com provider `dgsis` e modelo `cx/gpt-5.5`.
- Habilitar plugins bundled OpenAI: Browser, Chrome e Computer Use.
- Configurar `[windows] sandbox = "elevated"`.
- Configurar `[shell_environment_policy]` com PATH estavel.
- Criar shim `pwsh.exe` em `%LOCALAPPDATA%\Programs\OpenAI\Codex\bin`.
- Ajustar profiles PowerShell para evitar `pwsh.exe` da Microsoft Store.
- Rodar `codex doctor`, testes vivos e acionar Codex Desktop com `CODEX_HOME` correto.

## Validacao obrigatoria apos instalacao

Feche e abra uma nova janela PowerShell. Execute:

```powershell
codex --version
codex doctor --json
where.exe codex
where.exe pwsh
```

Criterios:

- `codex --version` retorna versao.
- `codex doctor --json` mostra todos checks com `status = ok`.
- `where.exe codex` aponta para `%LOCALAPPDATA%\Programs\OpenAI\Codex\bin\codex.exe` ou caminho equivalente do instalador oficial.
- `where.exe pwsh` deve mostrar primeiro `%LOCALAPPDATA%\Programs\OpenAI\Codex\bin\pwsh.exe` se existir `pwsh` da Microsoft Store.

Teste resposta do modelo:

```powershell
$out = Join-Path $env:TEMP "codex-dgsis-final.txt"
codex exec --ephemeral --skip-git-repo-check -o $out "Responda exatamente CODEX_DGSIS_OK e nada mais."
Get-Content $out
Remove-Item $out -Force
```

Esperado:

```text
CODEX_DGSIS_OK
```

Teste shell tool real:

```powershell
$jsonl = Join-Path $env:TEMP "codex-dgsis-shell.jsonl"
$last = Join-Path $env:TEMP "codex-dgsis-shell-last.txt"
codex exec --ephemeral --skip-git-repo-check --json -o $last "Use uma ferramenta de shell para executar um comando que imprime CODEX_DGSIS_SHELL_OK. Depois responda exatamente CODEX_DGSIS_SHELL_OK e nada mais." *> $jsonl
Get-Content $last
Select-String -LiteralPath $jsonl -Pattern "CreateProcessAsUserW failed|windows sandbox: runner error|exit_code.:0|CODEX_DGSIS_SHELL_OK"
Remove-Item $jsonl,$last -Force
```

Criterios:

- Arquivo `$last` contem `CODEX_DGSIS_SHELL_OK`.
- JSONL mostra comando com `exit_code:0`.
- JSONL nao mostra `CreateProcessAsUserW failed`.
- JSONL nao mostra `windows sandbox: runner error`.

## Validacao Codex Desktop

Execute em nova janela PowerShell:

```powershell
codex app "$env:USERPROFILE"
```

No Codex Desktop:

1. Selecione `Local`.
2. Abra workspace do usuario.
3. Envie `Responda exatamente CODEX_DESKTOP_READY e nada mais.`
4. Confirme resposta `CODEX_DESKTOP_READY`.
5. Confirme que seletor de modelos mostra apenas modelos OpenAI do gateway DGSIS, como `cx/gpt-5.5`, `cx/gpt-5.4`, `cx/gpt-5.4-mini` e variantes `cx/gpt-5.3-codex`.
6. Confirme que modelos Claude/Gemini/etc nao aparecem no catalogo local.
7. Confirme plugins/ferramentas Browser, Chrome e Computer Use quando interface mostrar plugins disponiveis.

Se pedir login OpenAI, feche o app e abra pelo PowerShell com `codex app "$env:USERPROFILE"` para herdar o ambiente configurado.

## Validacao VS Code

Execute:

```powershell
code --list-extensions | Select-String -Pattern "openai.chatgpt"
```

Se nao aparecer:

```powershell
code --install-extension openai.chatgpt --force
```

Depois:

1. Reinicie VS Code.
2. Abra uma pasta de projeto.
3. Abra barra lateral Codex/ChatGPT.
4. Envie mensagem simples.

Nao deve pedir login OpenAI se a extensao estiver usando ambiente local configurado pelo instalador. Se pedir login, reinicie VS Code a partir de uma nova sessao PowerShell para herdar `DGSIS_API_KEY`:

```powershell
code .
```

## Falhas conhecidas e correcao

### Erro 1312 no sandbox

Rode o instalador novamente. Verifique:

```powershell
where.exe pwsh
Get-Content "$env:USERPROFILE\Documents\PowerShell\profile.ps1"
```

Primeiro `pwsh.exe` deve ser o shim em `Codex\bin`.

### Token invalido

Rode de novo e peca token correto:

```powershell
irm https://raw.githubusercontent.com/soxvip/codex-dgsis-installer/main/install.ps1 | iex
```

### Modelo nao aparece

Confirme com suporte DGSIS que token tem acesso a `cx/gpt-5.5`.

Tambem confira o catalogo local:

```powershell
Get-Content "$env:USERPROFILE\.codex\model-catalogs\dgsis.json" -Raw | Select-String -Pattern 'cx/gpt|claude|gemini|qwen|llama'
```

Esperado: deve aparecer `cx/gpt...`; nao deve aparecer `claude`, `gemini`, `qwen` ou `llama`.

## Resposta final ao cliente

Ao terminar, reporte somente:

- Codex CLI instalado.
- Codex Desktop acionado.
- Plugins OpenAI Browser/Chrome/Computer Use habilitados.
- VS Code extension instalada.
- `codex doctor` sem problemas.
- Modelo ativo `cx/gpt-5.5`.
- Catalogo de modelos contem apenas modelos OpenAI DGSIS.
- Shell tool testado sem erro de sandbox.

Nao inclua token.
