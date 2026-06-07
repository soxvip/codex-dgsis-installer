# Codex DGSIS Installer

Instaladores Windows e macOS para deixar Codex CLI, Codex Desktop, Codex no VS Code e gateway DGSIS prontos para uso com token do cliente.

O cliente nao precisa fazer login no site da OpenAI. Durante a instalacao, ele informa o token DGSIS. Depois disso, Codex CLI e extensao do VS Code usam a configuracao local em `.codex`.

## Instalacao rapida no Windows

Abra PowerShell e rode:

```powershell
irm https://raw.githubusercontent.com/soxvip/codex-dgsis-installer/main/install.ps1 | iex
```

Quando pedir, cole o token DGSIS do cliente.

## Instalacao rapida no macOS

Abra Terminal e rode:

```bash
curl -fsSL https://raw.githubusercontent.com/soxvip/codex-dgsis-installer/main/install.sh | bash
```

Quando pedir, cole o token DGSIS do cliente. Se o Mac pedir senha, e a senha local de administrador para instalar Homebrew, dependencias ou VS Code.

## O que o instalador Windows faz

- Instala dependencias via `winget`: Git, Node.js LTS, Python e VS Code.
- Instala ou atualiza o Codex CLI pelo instalador oficial da OpenAI.
- Instala ou abre o Codex Desktop com `codex app`.
- Instala a extensao VS Code `openai.chatgpt`.
- Salva o token em `DGSIS_API_KEY` no ambiente do usuario.
- Configura `~\.codex\config.toml` para usar o provider `dgsis` e o modelo `cx/gpt-5.5`.
- Cria o catalogo local `~\.codex\model-catalogs\dgsis.json` com modelos OpenAI disponiveis em `/models`.
- Filtra modelos externos como Claude, Gemini, DeepSeek, Qwen, Llama, Mistral e similares.
- Habilita plugins bundled OpenAI: Browser, Chrome e Computer Use.
- Corrige o bug do `pwsh.exe` da Microsoft Store que pode quebrar o sandbox no Windows.
- Ajusta profiles PowerShell para novas sessoes priorizarem `Codex\bin`.
- Executa validacoes: `codex --strict-config`, catalogo, `codex doctor`, resposta do Codex e shell tool real.

## O que o instalador macOS faz

- Instala ou verifica Homebrew.
- Instala Git, Node.js e Python via Homebrew.
- Instala ou atualiza o Codex CLI pelo instalador oficial da OpenAI.
- Instala Visual Studio Code se necessario e adiciona a extensao `openai.chatgpt`.
- Salva o token em `~/.codex/dgsis.env` com permissao `600`.
- Cria `~/.codex/dgsis-token.sh` e configura `auth.command`, evitando depender de variavel de ambiente do Terminal para o VS Code.
- Configura `~/.codex/config.toml` para usar provider `dgsis` e modelo `cx/gpt-5.5`.
- Cria o catalogo local `~/.codex/model-catalogs/dgsis.json` com modelos OpenAI disponiveis em `/models`.
- Filtra modelos externos como Claude, Gemini, DeepSeek, Qwen, Llama, Mistral e similares.
- Habilita plugins bundled OpenAI: Browser, Chrome e Computer Use.
- Executa validacoes: catalogo, `codex --strict-config`, `codex doctor`, resposta do Codex e shell tool real.

## Arquivos principais

- `install.ps1`: instalador PowerShell para Windows.
- `install.sh`: instalador Bash para macOS/Linux.
- `TUTORIAL-CLIENTE.md`: passo a passo humano para Windows.
- `TUTORIAL-CLIENTE-MAC.md`: passo a passo humano para macOS.
- `IA-INSTALACAO-CODEX-DGSIS.md`: roteiro para IA instalar no Windows.
- `IA-INSTALACAO-CODEX-DGSIS-MAC.md`: roteiro para IA instalar no macOS.
- `IA-VSCODE-CODEX.md`: roteiro VS Code para Windows.
- `IA-VSCODE-CODEX-MAC.md`: roteiro VS Code para macOS.
- `dgsis-model-catalog.json`: template fallback para gerar catalogo DGSIS quando o catalogo embutido do Codex nao estiver disponivel.

## Parametros uteis Windows

```powershell
.\install.ps1 -Token "TOKEN_DGSIS_AQUI"
.\install.ps1 -SkipDependencies
.\install.ps1 -SkipVSCode
.\install.ps1 -SkipDesktop
.\install.ps1 -SkipLiveTests
.\install.ps1 -SelfTest
```

## Parametros uteis macOS

```bash
bash install.sh --token "TOKEN_DGSIS_AQUI"
bash install.sh --skip-dependencies
bash install.sh --skip-vscode
bash install.sh --skip-live-tests
bash install.sh --self-test
```

Com pipe remoto, passe parametros assim:

```bash
curl -fsSL https://raw.githubusercontent.com/soxvip/codex-dgsis-installer/main/install.sh | bash -s -- --skip-vscode
```

Use `--skip-live-tests` apenas quando a maquina nao puder consumir tokens durante instalacao. Para entrega final a cliente, deixe os testes vivos ligados.

## Validacao esperada

No final, o instalador deve mostrar:

```text
codex doctor sem warning/fail
Codex respondeu com model: cx/gpt-5.5
Shell tool executou comando real sem erro
Codex Desktop acionado com CODEX_HOME=
Instalacao concluida.
```

Depois, feche e abra Terminal/PowerShell, VS Code e Codex Desktop. No VS Code, abra a barra lateral Codex/ChatGPT e envie uma mensagem. Deve funcionar sem login no site, usando o token DGSIS salvo localmente.

O seletor de modelos deve mostrar apenas modelos OpenAI do gateway DGSIS, como `cx/gpt-5.5`, `cx/gpt-5.4`, `cx/gpt-5.4-mini` e variantes `cx/gpt-5.3-codex`. Modelos Claude/Gemini/etc nao devem aparecer no catalogo local.
