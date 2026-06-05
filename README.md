# Codex DGSIS Installer

Instalador PowerShell para configurar o Codex CLI no Windows usando o gateway DGSIS.

Ele instala ou atualiza o Codex CLI standalone oficial, configura o provider `dgsis`, define o modelo `cx/gpt-5.5`, cria o catalogo local `DGSIS GPT-5.5`, salva o token em `DGSIS_API_KEY`, desativa o plugin Cloudflare e executa um teste final.

## Instalar

Abra o PowerShell e execute:

```powershell
irm https://raw.githubusercontent.com/soxvip/codex-dgsis-installer/main/install.ps1 | iex
```

Durante a instalacao, cole seu token DGSIS quando o terminal pedir. O token nao fica no GitHub e nao deve ser colocado no script.

## Depois de instalar

Feche e abra uma nova janela do PowerShell:

```powershell
codex
```

No topo do Codex deve aparecer:

```text
model: cx/gpt-5.5
```

Se usar `/model`, escolha `DGSIS GPT-5.5`.

## O que o instalador altera

- Instala ou atualiza o Codex CLI standalone oficial.
- Salva o token em `DGSIS_API_KEY` no ambiente do usuario.
- Cria `%USERPROFILE%\.codex\model-catalogs\dgsis.json`.
- Faz backup de `%USERPROFILE%\.codex\config.toml` em `%USERPROFILE%\.codex\backups`.
- Atualiza a configuracao para usar:

```toml
model = "cx/gpt-5.5"
model_provider = "dgsis"
model_reasoning_effort = "xhigh"
service_tier = "fast"
approvals_reviewer = "user"

[model_providers.dgsis]
name = "DGSIS Gateway"
base_url = "https://gtw.dgsis.com.br/v1"
wire_api = "responses"
env_key = "DGSIS_API_KEY"
```

## Reexecutar

O instalador e idempotente. Voce pode roda-lo novamente para atualizar o Codex CLI, trocar o token ou corrigir a configuracao.

## Requisitos

- Windows
- PowerShell
- Acesso a internet
- Token DGSIS com acesso ao modelo `cx/gpt-5.5`
