# Roteiro para IA instalar Codex DGSIS no macOS do cliente

Use este arquivo como instrucao operacional para outro agente de IA que esteja controlando o Mac do cliente.

Objetivo: deixar Codex CLI e Codex no VS Code funcionando com gateway DGSIS, sem login OpenAI pelo site, usando token DGSIS informado pelo cliente.

## Regra de seguranca sobre token

Peca o token DGSIS ao cliente apenas no momento da instalacao.

Nao registre o token em logs, prints, respostas finais, README, issue, commit, historico compartilhado ou arquivo do projeto. O token deve ser colado no prompt seguro do instalador. Evite passar token na linha de comando, porque comandos podem ficar no historico do Terminal.

Frase sugerida ao cliente:

```text
Cole agora seu token DGSIS no Terminal. Ele sera salvo localmente em ~/.codex/dgsis.env com permissao 600 e nao sera enviado para mim em texto final.
```

## Pre-checagem

Execute no Terminal:

```bash
sw_vers
uname -m
command -v curl
command -v brew || true
command -v code || true
```

Se Homebrew nao existir, o instalador tenta instalar. O cliente pode precisar digitar a senha local de administrador.

## Instalacao padrao

Execute:

```bash
curl -fsSL https://raw.githubusercontent.com/soxvip/codex-dgsis-installer/main/install.sh | bash
```

Quando o instalador pedir, o cliente deve colar o token DGSIS.

Nao pule os testes vivos. Eles confirmam que gateway, modelo, Codex CLI, `codex doctor` e ferramenta shell estao funcionando.

## O instalador deve fazer

- Instalar Homebrew se necessario.
- Instalar Git, Node.js e Python via Homebrew.
- Instalar Visual Studio Code se necessario.
- Instalar extensao VS Code `openai.chatgpt`.
- Instalar Codex CLI oficial via `https://chatgpt.com/codex/install.sh`.
- Salvar token em `~/.codex/dgsis.env` com permissao `600`.
- Criar helper `~/.codex/dgsis-token.sh` com permissao executavel.
- Atualizar `~/.codex/config.toml` com provider `dgsis`, modelo `cx/gpt-5.5` e `[model_providers.dgsis.auth]`.
- Criar `~/.codex/model-catalogs/dgsis.json` com modelos OpenAI retornados por `/models`.
- Atualizar `~/.codex/models_cache.json` para o seletor do Codex Desktop.
- Excluir modelos Claude, Gemini, DeepSeek, Qwen, Llama, Mistral e similares do catalogo local.
- Habilitar plugins bundled OpenAI: Browser, Chrome e Computer Use.
- Rodar `codex --strict-config`, `codex doctor`, resposta do modelo e shell tool real.

## Validacao obrigatoria apos instalacao

Feche e abra uma nova janela Terminal. Execute:

```bash
codex --version
codex doctor --json
command -v codex
grep -n 'model = "cx/gpt-5.5"' ~/.codex/config.toml
grep -n 'model_provider = "dgsis"' ~/.codex/config.toml
grep -nF '[model_providers.dgsis.auth]' ~/.codex/config.toml
grep -nF '[plugins."browser@openai-bundled"]' ~/.codex/config.toml
grep -nF '[plugins."chrome@openai-bundled"]' ~/.codex/config.toml
grep -nF '[plugins."computer-use@openai-bundled"]' ~/.codex/config.toml
ls -l ~/.codex/dgsis.env ~/.codex/dgsis-token.sh
~/.codex/dgsis-token.sh >/dev/null && echo TOKEN_HELPER_OK
```

Criterios:

- `codex --version` retorna versao.
- `codex doctor --json` nao mostra warning/fail.
- `command -v codex` aponta para `~/.local/bin/codex` ou caminho equivalente do instalador oficial.
- `config.toml` mostra modelo `cx/gpt-5.5`, provider `dgsis` e auth command.
- `config.toml` mostra plugins Browser, Chrome e Computer Use habilitados.
- `dgsis.env` esta com permissao `600`.
- `dgsis-token.sh` esta executavel.
- `TOKEN_HELPER_OK` aparece sem imprimir token.

Teste resposta do modelo:

```bash
out="$(mktemp)"
codex exec --ephemeral --skip-git-repo-check -o "$out" "Responda exatamente CODEX_DGSIS_OK e nada mais."
cat "$out"
rm -f "$out"
```

Esperado:

```text
CODEX_DGSIS_OK
```

Teste shell tool real:

```bash
jsonl="$(mktemp)"
last="$(mktemp)"
codex exec --ephemeral --skip-git-repo-check --json -o "$last" "Use uma ferramenta de shell para executar um comando que imprime CODEX_DGSIS_SHELL_OK. Depois responda exatamente CODEX_DGSIS_SHELL_OK e nada mais." >"$jsonl" 2>&1
cat "$last"
grep -E '"exit_code"[[:space:]]*:[[:space:]]*0|CODEX_DGSIS_SHELL_OK' "$jsonl"
rm -f "$jsonl" "$last"
```

Criterios:

- Arquivo `$last` contem `CODEX_DGSIS_SHELL_OK`.
- JSONL mostra shell command com `exit_code:0`.
- JSONL nao mostra erro de sandbox ou permissao.

## Validacao VS Code

Execute:

```bash
code --list-extensions | grep -i '^openai.chatgpt$' || "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" --list-extensions | grep -i '^openai.chatgpt$'
```

Se nao aparecer:

```bash
code --install-extension openai.chatgpt --force || "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" --install-extension openai.chatgpt --force
```

Depois:

1. Reinicie VS Code.
2. Abra uma pasta de projeto.
3. Abra barra lateral Codex/ChatGPT.
4. Envie mensagem simples.

Nao deve pedir login OpenAI. A extensao usa a mesma configuracao local do CLI e o helper `~/.codex/dgsis-token.sh`.

## Falhas conhecidas e correcao

### Homebrew falhou

Rode novamente em Terminal interativo e deixe o cliente digitar a senha local. Se continuar falhando, instale Homebrew manualmente pelo site oficial e rode o instalador de novo.

### Aviso do Python/Homebrew e prompt voltou

Avisos como `Unversioned symlinks python`, `idle3.14 requires tkinter`, `dbm.gnu is available separately` e link `Homebrew-and-Python` sao caveats normais do Homebrew.

Se o prompt voltou sem pedir token ou sem `Instalacao concluida`, rode novamente o comando principal. A versao atual pede token antes das dependencias e mostra `ERROR:` com linha/status se algum comando interromper o instalador.

```bash
curl -fsSL https://raw.githubusercontent.com/soxvip/codex-dgsis-installer/main/install.sh | bash
```

Se repetir, envie ao suporte o trecho desde `==>` ate `ERROR:`. Nao envie token.

### `codex: command not found`

Primeiro confira se e so PATH:

```bash
export PATH="$HOME/.local/bin:$PATH"
test -x "$HOME/.local/bin/codex" && "$HOME/.local/bin/codex" --version
```

Se existir, abra novo Terminal e rode:

```bash
codex --version
```

Se `~/.local/bin/codex` nao existir, reinstale pelo instalador principal:

```bash
curl -fsSL https://raw.githubusercontent.com/soxvip/codex-dgsis-installer/main/install.sh | bash
```

Depois valide:

```bash
command -v codex
codex --version
grep -F '.local/bin' ~/.zprofile ~/.zshrc ~/.bash_profile ~/.bashrc ~/.profile 2>/dev/null
```

### Token invalido

Rode o instalador de novo e peca token correto:

```bash
curl -fsSL https://raw.githubusercontent.com/soxvip/codex-dgsis-installer/main/install.sh | bash
```

### Modelo nao aparece

Confirme com suporte DGSIS que token tem acesso a `cx/gpt-5.5`.

Tambem confira o catalogo local:

```bash
grep -E 'cx/gpt' ~/.codex/model-catalogs/dgsis.json
grep -Ei 'claude|gemini|qwen|llama|deepseek|mistral' ~/.codex/model-catalogs/dgsis.json || echo OK_APENAS_OPENAI
grep -E 'cx/gpt' ~/.codex/models_cache.json
grep -Ei 'claude|gemini|qwen|llama|deepseek|mistral' ~/.codex/models_cache.json || echo OK_CACHE_APENAS_OPENAI
```

Esperado: deve aparecer `cx/gpt...`, `OK_APENAS_OPENAI` e `OK_CACHE_APENAS_OPENAI`.

### VS Code pede login

Nao faca login. Verifique CLI e helper:

```bash
codex --version
codex doctor --json
~/.codex/dgsis-token.sh >/dev/null && echo TOKEN_HELPER_OK
```

Se CLI funcionar, feche todas as janelas VS Code e abra novamente.

## Resposta final ao cliente

Ao terminar, reporte somente:

- Codex CLI instalado.
- VS Code extension instalada.
- `codex doctor` sem problemas.
- Modelo ativo `cx/gpt-5.5`.
- Catalogo de modelos contem apenas modelos OpenAI DGSIS.
- Plugins OpenAI Browser/Chrome/Computer Use habilitados.
- Shell tool testado sem erro.

Nao inclua token.
