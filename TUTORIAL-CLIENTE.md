# Tutorial para cliente: instalar Codex DGSIS no Windows

Este tutorial instala Codex CLI, dependencias de desenvolvimento, extensao do VS Code e configuracao DGSIS. O login em conta OpenAI pelo site nao e necessario. O acesso usa o token DGSIS do cliente.

## Antes de comecar

Tenha em maos:

- Windows 10 ou Windows 11 64-bit.
- Internet liberada.
- PowerShell aberto pelo usuario que vai usar o Codex.
- Token DGSIS com acesso ao modelo `cx/gpt-5.5`.

Nao envie o token por chat publico. Cole o token apenas quando o terminal pedir.

## Instalacao automatica

Abra PowerShell e execute:

```powershell
irm https://raw.githubusercontent.com/soxvip/codex-dgsis-installer/main/install.ps1 | iex
```

Quando aparecer `Cole seu token DGSIS`, cole o token e pressione Enter.

O instalador pode demorar porque baixa dependencias e instala o Codex CLI.

## O que sera instalado

- Git
- Node.js LTS
- Python
- Visual Studio Code
- Extensao VS Code `openai.chatgpt`
- Codex CLI oficial
- Configuracao DGSIS em `%USERPROFILE%\.codex\config.toml`

## Resultado esperado

No final, deve aparecer algo parecido com:

```text
OK: codex doctor: todos checks ok
OK: Codex respondeu com model: cx/gpt-5.5
OK: Shell tool executou comando real sem erro de sandbox
Instalacao concluida.
```

Se algum erro aparecer, copie a mensagem completa e envie ao suporte.

## Testar no PowerShell

Feche o PowerShell, abra de novo e rode:

```powershell
codex --version
codex doctor
codex
```

Dentro do Codex, confira se o topo mostra:

```text
model: cx/gpt-5.5
```

Envie uma mensagem simples:

```text
Responda apenas: ok
```

Resposta esperada:

```text
ok
```

## Testar no VS Code

1. Feche e abra o VS Code.
2. Abra uma pasta de projeto.
3. Procure o icone Codex/ChatGPT na barra lateral direita.
4. Abra o chat do Codex.
5. Envie uma mensagem simples.

O chat deve funcionar sem abrir login no site. Ele usa a configuracao local criada pelo instalador e o token `DGSIS_API_KEY` salvo no ambiente do usuario.

## Reinstalar ou trocar token

Execute o instalador de novo:

```powershell
irm https://raw.githubusercontent.com/soxvip/codex-dgsis-installer/main/install.ps1 | iex
```

Cole o novo token quando o terminal pedir. A configuracao anterior recebe backup em `%USERPROFILE%\.codex\backups`.

## Problemas comuns

### `winget` nao encontrado

Instale `App Installer` pela Microsoft Store ou atualize Windows. Depois rode o comando de instalacao de novo.

### VS Code nao abriu o chat Codex

Feche o VS Code e abra de novo. Se ainda nao aparecer, rode:

```powershell
code --install-extension openai.chatgpt --force
```

### Erro `CreateProcessAsUserW failed: 1312`

Rode o instalador novamente. Ele cria um shim `pwsh.exe` e ajusta o profile PowerShell para evitar o `pwsh.exe` da Microsoft Store.

### `codex doctor` mostra warning ou fail

Rode:

```powershell
codex doctor --json
```

Envie a saida completa ao suporte.

