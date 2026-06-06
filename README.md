# Codex DGSIS Installer

Instalador Windows para deixar Codex CLI, Codex no VS Code e gateway DGSIS prontos para uso com token do cliente.

O cliente nao precisa fazer login no site da OpenAI. Durante a instalacao, ele informa o token DGSIS. Depois disso, o Codex CLI e a extensao do VS Code usam a configuracao local em `%USERPROFILE%\.codex` e a variavel de usuario `DGSIS_API_KEY`.

## Instalacao rapida no Windows

Abra PowerShell e rode:

```powershell
irm https://raw.githubusercontent.com/soxvip/codex-dgsis-installer/main/install.ps1 | iex
```

Quando pedir, cole o token DGSIS do cliente.

## O que o instalador faz

- Instala dependencias via `winget`: Git, Node.js LTS, Python e VS Code.
- Instala ou atualiza o Codex CLI pelo instalador oficial da OpenAI.
- Instala a extensao VS Code `openai.chatgpt`.
- Salva o token em `DGSIS_API_KEY` no ambiente do usuario.
- Configura `~\.codex\config.toml` para usar o provider `dgsis` e o modelo `cx/gpt-5.5`.
- Cria o catalogo local `~\.codex\model-catalogs\dgsis.json`.
- Corrige o bug do `pwsh.exe` da Microsoft Store que pode quebrar o sandbox no Windows.
- Ajusta profiles PowerShell para novas sessoes priorizarem `Codex\bin`.
- Executa validacoes: `codex --strict-config`, catalogo, `codex doctor`, resposta do Codex e shell tool real.

## Arquivos principais

- `install.ps1`: instalador PowerShell para cliente Windows.
- `TUTORIAL-CLIENTE.md`: passo a passo humano para enviar ao cliente.
- `IA-INSTALACAO-CODEX-DGSIS.md`: roteiro para outro agente de IA instalar tudo para o cliente.
- `IA-VSCODE-CODEX.md`: roteiro especifico para deixar VS Code pronto.
- `dgsis-model-catalog.json`: catalogo fallback do modelo `cx/gpt-5.5`.

## Parametros uteis

```powershell
.\install.ps1 -Token "TOKEN_DGSIS_AQUI"
.\install.ps1 -SkipDependencies
.\install.ps1 -SkipVSCode
.\install.ps1 -SkipLiveTests
.\install.ps1 -SelfTest
```

Use `-SkipLiveTests` apenas quando a maquina nao puder consumir tokens durante instalacao. Para entrega final a cliente, deixe os testes vivos ligados.

## Validacao esperada

No final, o instalador deve mostrar:

```text
codex doctor: todos checks ok
Codex respondeu com model: cx/gpt-5.5
Shell tool executou comando real sem erro de sandbox
Instalacao concluida.
```

Depois, feche e abra PowerShell e VS Code. No VS Code, abra a barra lateral Codex/ChatGPT e envie uma mensagem. Deve funcionar sem login no site, usando o token DGSIS salvo localmente.
