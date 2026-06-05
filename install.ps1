param(
    [string]$Token = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$DgsisBaseUrl = "https://gtw.dgsis.com.br/v1"
$DgsisModel = "cx/gpt-5.5"
$DgsisProvider = "dgsis"
$EnvKeyName = "DGSIS_API_KEY"
$CodexInstallUrl = "https://chatgpt.com/codex/install.ps1"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "OK: $Message" -ForegroundColor Green
}

function Fail {
    param([string]$Message)
    Write-Error $Message
    exit 1
}

function ConvertFrom-SecureStringPlainText {
    param([System.Security.SecureString]$SecureValue)

    if ($null -eq $SecureValue) {
        return ""
    }

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

function ConvertTo-TomlString {
    param([string]$Value)

    $escaped = $Value.Replace("\", "\\").Replace('"', '\"')
    return '"' + $escaped + '"'
}

function Set-TextFileUtf8NoBom {
    param(
        [string]$Path,
        [string]$Content
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Set-LinesFileUtf8NoBom {
    param(
        [string]$Path,
        [string[]]$Lines
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($Path, $Lines, $encoding)
}

function Quote-ProcessArgument {
    param([string]$Value)

    if ($Value -notmatch '[\s"]') {
        return $Value
    }

    return '"' + ($Value -replace '"', '\"') + '"'
}

function Remove-Section {
    param(
        [string[]]$Lines,
        [string]$SectionName
    )

    $output = New-Object System.Collections.Generic.List[string]
    $skip = $false
    $sectionPattern = '^\s*\[' + [regex]::Escape($SectionName) + '\]\s*$'
    $anySectionPattern = '^\s*\[.+\]\s*$'

    foreach ($line in $Lines) {
        if ($line -match $sectionPattern) {
            $skip = $true
            continue
        }

        if ($skip -and $line -match $anySectionPattern) {
            $skip = $false
        }

        if (-not $skip) {
            [void]$output.Add($line)
        }
    }

    return $output.ToArray()
}

function Set-TopLevelKey {
    param(
        [string[]]$Lines,
        [string]$Key,
        [string]$ValueLine
    )

    $firstSection = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^\s*\[.+\]\s*$') {
            $firstSection = $i
            break
        }
    }

    if ($firstSection -lt 0) {
        $top = @($Lines)
        $rest = @()
    }
    elseif ($firstSection -eq 0) {
        $top = @()
        $rest = @($Lines)
    }
    else {
        $top = @($Lines[0..($firstSection - 1)])
        $rest = @($Lines[$firstSection..($Lines.Count - 1)])
    }

    $keyPattern = '^\s*' + [regex]::Escape($Key) + '\s*='
    $newTop = @($top | Where-Object { $_ -notmatch $keyPattern })
    $newTop = @($ValueLine) + $newTop

    return @($newTop + $rest)
}

function Set-SectionKey {
    param(
        [string[]]$Lines,
        [string]$SectionName,
        [string]$Key,
        [string]$ValueLine
    )

    $sectionPattern = '^\s*\[' + [regex]::Escape($SectionName) + '\]\s*$'
    $keyPattern = '^\s*' + [regex]::Escape($Key) + '\s*='
    $start = -1

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match $sectionPattern) {
            $start = $i
            break
        }
    }

    if ($start -lt 0) {
        return @($Lines + "" + "[$SectionName]" + $ValueLine)
    }

    $end = $Lines.Count
    for ($i = $start + 1; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^\s*\[.+\]\s*$') {
            $end = $i
            break
        }
    }

    $output = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -le $start; $i++) {
        [void]$output.Add($Lines[$i])
    }

    $updated = $false
    for ($i = $start + 1; $i -lt $end; $i++) {
        if ($Lines[$i] -match $keyPattern) {
            if (-not $updated) {
                [void]$output.Add($ValueLine)
                $updated = $true
            }
            continue
        }
        [void]$output.Add($Lines[$i])
    }

    if (-not $updated) {
        [void]$output.Add($ValueLine)
    }

    for ($i = $end; $i -lt $Lines.Count; $i++) {
        [void]$output.Add($Lines[$i])
    }

    return $output.ToArray()
}

function Invoke-CodexExecTest {
    param(
        [string]$CodexExe
    )

    $args = @(
        "exec",
        "--skip-git-repo-check",
        "--sandbox",
        "read-only",
        "Responda apenas: ok"
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $CodexExe
    $psi.Arguments = ($args | ForEach-Object { Quote-ProcessArgument $_ }) -join " "
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables[$EnvKeyName] = $env:DGSIS_API_KEY

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi

    [void]$process.Start()
    $process.StandardInput.Close()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()

    if (-not $process.WaitForExit(180000)) {
        try {
            $process.Kill()
        }
        catch {
        }
        Fail "O teste final do Codex excedeu 180 segundos."
    }

    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result

    $combined = ($stdout + "`n" + $stderr).Trim()
    if ($process.ExitCode -ne 0) {
        Fail "O teste final do Codex falhou. Saida: $combined"
    }

    if ($combined -notmatch 'model:\s*cx/gpt-5\.5') {
        Fail "O Codex respondeu, mas nao iniciou com model: cx/gpt-5.5. Saida: $combined"
    }

    if ($combined -notmatch '(?m)^\s*ok\s*$') {
        Fail "O Codex respondeu, mas nao retornou 'ok' no teste final. Saida: $combined"
    }
}

$isWindowsRuntime = $env:OS -eq "Windows_NT"
$isWindowsVariable = Get-Variable -Name IsWindows -Scope Global -ErrorAction SilentlyContinue
if ($null -ne $isWindowsVariable) {
    $isWindowsRuntime = [bool]$isWindowsVariable.Value
}

if (-not $isWindowsRuntime) {
    Fail "Este instalador e somente para Windows PowerShell/PowerShell no Windows."
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Step "Instalando ou atualizando o Codex CLI standalone"
$oldNonInteractive = $env:CODEX_NON_INTERACTIVE
try {
    $env:CODEX_NON_INTERACTIVE = "1"
    if (-not $PSVersionTable.ContainsKey("OSArchitecture")) {
        $PSVersionTable["OSArchitecture"] = if ([Environment]::Is64BitOperatingSystem) { "X64" } else { "X86" }
    }
    Invoke-RestMethod -Uri $CodexInstallUrl -TimeoutSec 120 | Invoke-Expression
}
finally {
    $env:CODEX_NON_INTERACTIVE = $oldNonInteractive
}

$preferredBinDir = Join-Path $env:LOCALAPPDATA "Programs\OpenAI\Codex\bin"
$preferredCodexExe = Join-Path $preferredBinDir "codex.exe"

if (-not (Test-Path -LiteralPath $preferredCodexExe)) {
    $fallback = Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA "OpenAI\Codex\bin") -Recurse -Filter "codex.exe" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($null -eq $fallback) {
        Fail "Nao encontrei codex.exe apos a instalacao."
    }

    $preferredCodexExe = $fallback.FullName
    $preferredBinDir = Split-Path -Parent $preferredCodexExe
}

$currentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
$pathParts = @()
if (-not [string]::IsNullOrWhiteSpace($currentUserPath)) {
    $pathParts = @($currentUserPath -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

if ($pathParts -notcontains $preferredBinDir) {
    $newUserPath = (@($preferredBinDir) + $pathParts) -join ";"
    [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
}

if (($env:Path -split ";") -notcontains $preferredBinDir) {
    $env:Path = "$preferredBinDir;$env:Path"
}

$codexVersion = & $preferredCodexExe --version
Write-Ok "Codex CLI pronto: $codexVersion"

Write-Step "Solicitando token DGSIS"
$existingToken = [Environment]::GetEnvironmentVariable($EnvKeyName, "User")
if (-not [string]::IsNullOrWhiteSpace($Token)) {
    $token = $Token
}
else {
    if ([string]::IsNullOrWhiteSpace($existingToken)) {
        $secureToken = Read-Host "Cole seu token DGSIS" -AsSecureString
    }
    else {
        $secureToken = Read-Host "Cole seu token DGSIS ou pressione Enter para manter o token atual" -AsSecureString
    }

    $token = ConvertFrom-SecureStringPlainText $secureToken
    if ([string]::IsNullOrWhiteSpace($token)) {
        $token = $existingToken
    }
}

if ([string]::IsNullOrWhiteSpace($token)) {
    Fail "Token DGSIS nao informado."
}

Write-Step "Validando token e modelo no gateway DGSIS"
try {
    $models = Invoke-RestMethod -Method Get -Uri "$DgsisBaseUrl/models" -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 30
}
catch {
    Fail "Nao foi possivel validar o token no gateway DGSIS. Verifique o token e a conexao."
}

$availableModel = @($models.data | Where-Object { $_.id -eq $DgsisModel }).Count -gt 0
if (-not $availableModel) {
    Fail "O token foi aceito, mas o modelo $DgsisModel nao apareceu em /models."
}

[Environment]::SetEnvironmentVariable($EnvKeyName, $token, "User")
$env:DGSIS_API_KEY = $token
Write-Ok "Token validado e salvo em $EnvKeyName"

$codexHome = Join-Path $env:USERPROFILE ".codex"
$catalogDir = Join-Path $codexHome "model-catalogs"
$backupDir = Join-Path $codexHome "backups"
$catalogPath = Join-Path $catalogDir "dgsis.json"
$configPath = Join-Path $codexHome "config.toml"

New-Item -ItemType Directory -Force -Path $catalogDir | Out-Null
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

Write-Step "Gerando catalogo local DGSIS para o seletor de modelos"
try {
    $bundledJson = & $preferredCodexExe debug models --bundled
    $bundledCatalog = $bundledJson | ConvertFrom-Json
    $model = @($bundledCatalog.models | Where-Object { $_.slug -eq "gpt-5.5" })[0]
}
catch {
    Fail "Nao foi possivel ler o catalogo embutido do Codex CLI."
}

if ($null -eq $model) {
    Fail "O catalogo embutido do Codex nao contem gpt-5.5."
}

$model.slug = $DgsisModel
$model.display_name = "DGSIS GPT-5.5"
$model.description = "Modelo GPT-5.5 via gateway DGSIS."
$model.availability_nux = $null

$catalog = [pscustomobject]@{ models = @($model) }
Set-TextFileUtf8NoBom -Path $catalogPath -Content ($catalog | ConvertTo-Json -Depth 100)
Write-Ok "Catalogo criado em $catalogPath"

Write-Step "Mesclando configuracao do Codex"
if (Test-Path -LiteralPath $configPath) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = Join-Path $backupDir "config.$timestamp.toml"
    Copy-Item -LiteralPath $configPath -Destination $backupPath -Force
    $lines = @(Get-Content -LiteralPath $configPath)
    Write-Ok "Backup criado em $backupPath"
}
else {
    New-Item -ItemType Directory -Force -Path $codexHome | Out-Null
    $lines = @()
}

$catalogTomlPath = ConvertTo-TomlString $catalogPath
$lines = Set-TopLevelKey $lines "approvals_reviewer" 'approvals_reviewer = "user"'
$lines = Set-TopLevelKey $lines "service_tier" 'service_tier = "fast"'
$lines = Set-TopLevelKey $lines "personality" 'personality = "pragmatic"'
$lines = Set-TopLevelKey $lines "model_catalog_json" "model_catalog_json = $catalogTomlPath"
$lines = Set-TopLevelKey $lines "model_reasoning_effort" 'model_reasoning_effort = "xhigh"'
$lines = Set-TopLevelKey $lines "model_provider" 'model_provider = "dgsis"'
$lines = Set-TopLevelKey $lines "model" 'model = "cx/gpt-5.5"'

$lines = Remove-Section $lines "model_providers.dgsis"
$lines = Remove-Section $lines 'plugins."cloudflare@openai-curated"'
$lines = Set-SectionKey $lines "windows" "sandbox" 'sandbox = "elevated"'

$lines = @($lines + "" + "[model_providers.dgsis]" +
    'name = "DGSIS Gateway"' +
    'base_url = "https://gtw.dgsis.com.br/v1"' +
    'wire_api = "responses"' +
    'env_key = "DGSIS_API_KEY"' +
    "" +
    '[plugins."cloudflare@openai-curated"]' +
    'enabled = false')

Set-LinesFileUtf8NoBom -Path $configPath -Lines $lines
Write-Ok "Config.toml atualizado em $configPath"

Write-Step "Validando configuracao do catalogo"
$debugModels = & $preferredCodexExe debug models
if ($LASTEXITCODE -ne 0 -or $debugModels -notmatch '"slug"\s*:\s*"cx/gpt-5\.5"') {
    Fail "O Codex nao carregou o catalogo DGSIS corretamente."
}
Write-Ok "Catalogo DGSIS carregado pelo Codex"

Write-Step "Executando teste final do Codex CLI com o gateway DGSIS"
Invoke-CodexExecTest -CodexExe $preferredCodexExe
Write-Ok "Codex respondeu com model: cx/gpt-5.5"

Write-Host ""
Write-Host "Instalacao concluida." -ForegroundColor Green
Write-Host "Feche e abra uma nova janela do PowerShell e execute: codex"
Write-Host "No topo do Codex deve aparecer: model: cx/gpt-5.5"
