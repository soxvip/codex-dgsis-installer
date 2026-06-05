# Codex DGSIS Installer

Instalador multiplataforma para configurar o Codex CLI com o gateway DGSIS.

Ele instala ou atualiza o Codex CLI standalone oficial, configura o provider `dgsis`, define o modelo `cx/gpt-5.5`, cria o catalogo local `DGSIS GPT-5.5`, desativa o plugin Cloudflare e executa um teste final.

## Instalar no Windows

Abra o PowerShell e execute:

```powershell
irm https://raw.githubusercontent.com/soxvip/codex-dgsis-installer/main/install.ps1 | iex
```

O instalador suporta Windows x64 e Windows ARM64. Ele funciona no Windows PowerShell 5.1, no PowerShell 7, como administrador ou como usuario comum.

## Instalar no macOS ou Linux

Abra o Terminal e execute:

```bash
curl -fsSL https://raw.githubusercontent.com/soxvip/codex-dgsis-installer/main/install.sh | bash
```

O instalador suporta macOS Intel, macOS Apple Silicon, Linux x64 e Linux ARM64, desde que a plataforma seja suportada pelo instalador oficial do Codex.

## Token DGSIS

Durante a instalacao, cole seu proprio token DGSIS quando o terminal pedir. O token nao fica no GitHub, nao aparece no README e nao deve ser colocado no script.

No Windows, o token e salvo como variavel de usuario `DGSIS_API_KEY`.

No macOS/Linux, o token e salvo em `~/.codex/dgsis.env` com permissao `600`, e o profile do shell recebe uma linha idempotente para carregar esse arquivo.

## Depois de instalar

Feche e abra uma nova janela do terminal e execute:

```bash
codex
```

No topo do Codex deve aparecer:

```text
model: cx/gpt-5.5
```

Se usar `/model`, escolha `DGSIS GPT-5.5`.

## O que o instalador altera

- Instala ou atualiza o Codex CLI standalone oficial.
- Valida o token em `https://gtw.dgsis.com.br/v1/models`.
- Confirma que o modelo `cx/gpt-5.5` existe para o token.
- Cria `~/.codex/model-catalogs/dgsis.json`.
- Faz backup de `~/.codex/config.toml` em `~/.codex/backups`.
- Gera o catalogo local a partir de `codex debug models --bundled` quando possivel.
- Usa `dgsis-model-catalog.json` como fallback quando a transformacao local falha.
- Atualiza a configuracao para usar:

```toml
model = "cx/gpt-5.5"
model_provider = "dgsis"
model_reasoning_effort = "xhigh"
model_catalog_json = "..."
personality = "pragmatic"
service_tier = "fast"
approvals_reviewer = "user"

[model_providers.dgsis]
name = "DGSIS Gateway"
base_url = "https://gtw.dgsis.com.br/v1"
wire_api = "responses"
env_key = "DGSIS_API_KEY"

[windows]
sandbox = "elevated"

[plugins."cloudflare@openai-curated"]
enabled = false
```

## Reexecutar

O instalador e idempotente. Voce pode roda-lo novamente para atualizar o Codex CLI, trocar o token ou corrigir a configuracao sem duplicar blocos TOML.

## Requisitos

- Acesso a internet.
- Token DGSIS com acesso ao modelo `cx/gpt-5.5`.
- Windows, macOS ou Linux 64-bit suportado pelo Codex CLI oficial.
