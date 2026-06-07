# Tutorial para cliente: instalar Codex DGSIS no macOS

Este tutorial instala Codex CLI, dependencias de desenvolvimento, Visual Studio Code, extensao Codex/ChatGPT e configuracao DGSIS. O login em conta OpenAI pelo site nao e necessario. O acesso usa o token DGSIS do cliente.

## Antes de comecar

Tenha em maos:

- Mac com macOS atual, Intel ou Apple Silicon.
- Internet liberada.
- Terminal aberto pelo usuario que vai usar o Codex.
- Senha local de administrador do Mac, se o sistema pedir.
- Token DGSIS com acesso ao modelo `cx/gpt-5.5`.

Nao envie o token por chat publico. Cole o token apenas quando o Terminal pedir.

## Instalacao automatica

Abra Terminal e execute:

```bash
curl -fsSL https://raw.githubusercontent.com/soxvip/codex-dgsis-installer/main/install.sh | bash
```

Quando aparecer `Cole seu token DGSIS`, cole o token e pressione Enter.

O instalador pode demorar porque baixa Homebrew, Git, Node.js, Python, VS Code e Codex CLI quando necessario.

## O que sera instalado

- Homebrew, se ainda nao existir.
- Git.
- Node.js.
- Python.
- Visual Studio Code.
- Extensao VS Code `openai.chatgpt`.
- Codex CLI oficial.
- Configuracao DGSIS em `~/.codex/config.toml`.
- Token em `~/.codex/dgsis.env` com permissao `600`.
- Helper seguro `~/.codex/dgsis-token.sh` para o VS Code ler o token sem depender do Terminal.

## Resultado esperado

No final, deve aparecer algo parecido com:

```text
OK: codex doctor sem warning/fail
OK: Codex respondeu com model: cx/gpt-5.5
OK: Shell tool executou comando real sem erro
Instalacao concluida.
```

Se algum erro aparecer, copie a mensagem completa e envie ao suporte. Nao copie nem envie o token.

## Testar no Terminal

Feche o Terminal, abra de novo e rode:

```bash
codex --version
codex doctor --json
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
3. Procure o icone Codex/ChatGPT na barra lateral.
4. Abra o chat do Codex.
5. Envie uma mensagem simples.

O chat deve funcionar sem abrir login no site. Ele usa a configuracao local criada pelo instalador e o token salvo em `~/.codex/dgsis.env`.

Se o chat nao aparecer, rode no Terminal:

```bash
code --install-extension openai.chatgpt --force
```

Se `code` nao existir, rode:

```bash
"/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" --install-extension openai.chatgpt --force
```

## Reinstalar ou trocar token

Execute o instalador de novo:

```bash
curl -fsSL https://raw.githubusercontent.com/soxvip/codex-dgsis-installer/main/install.sh | bash
```

Cole o novo token quando o Terminal pedir. A configuracao anterior recebe backup em `~/.codex/backups`.

## Problemas comuns

### Homebrew pede senha

Digite a senha local do Mac. O Terminal nao mostra os caracteres enquanto voce digita.

### VS Code nao abriu o chat Codex

Feche o VS Code e abra de novo. Se ainda nao aparecer, rode:

```bash
code --install-extension openai.chatgpt --force
```

Ou use o caminho direto:

```bash
"/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" --install-extension openai.chatgpt --force
```

### VS Code pede login

Nao faca login pelo site. Rode no Terminal:

```bash
codex --version
codex doctor --json
grep -n 'model_provider = "dgsis"' ~/.codex/config.toml
~/.codex/dgsis-token.sh >/dev/null && echo TOKEN_HELPER_OK
```

Se `TOKEN_HELPER_OK` aparecer e o CLI funcionar, feche todas as janelas do VS Code e abra de novo.

### Modelo nao aparece

Rode:

```bash
codex debug models | grep 'cx/gpt-5.5'
```

Se nao aparecer, rode o instalador novamente. Se continuar, confirme com suporte DGSIS que o token tem acesso ao modelo `cx/gpt-5.5`.
