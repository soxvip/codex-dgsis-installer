param(
    [string]$Token = "",
    [ValidateSet("", "X64", "Arm64")]
    [string]$ArchitectureOverride = "",
    [switch]$SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$DgsisBaseUrl = "https://gtw.dgsis.com.br/v1"
$DgsisModel = "cx/gpt-5.5"
$DgsisProvider = "dgsis"
$EnvKeyName = "DGSIS_API_KEY"
$CodexInstallUrl = "https://chatgpt.com/codex/install.ps1"
$FallbackCatalogUrl = "https://raw.githubusercontent.com/soxvip/codex-dgsis-installer/main/dgsis-model-catalog.json"

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

function Get-EmbeddedFallbackCatalogJson {
    return @'
{
  "models": [
    {
      "slug": "cx/gpt-5.5",
      "display_name": "DGSIS GPT-5.5",
      "description": "Modelo GPT-5.5 via gateway DGSIS.",
      "default_reasoning_level": "medium",
      "supported_reasoning_levels": [
        { "effort": "low", "description": "Fast responses with lighter reasoning" },
        { "effort": "medium", "description": "Balances speed and reasoning depth for everyday tasks" },
        { "effort": "high", "description": "Greater reasoning depth for complex problems" },
        { "effort": "xhigh", "description": "Extra high reasoning depth for complex problems" }
      ],
      "shell_type": "shell_command",
      "visibility": "list",
      "supported_in_api": true,
      "priority": 0,
      "additional_speed_tiers": ["fast"],
      "service_tiers": [
        { "id": "priority", "name": "Fast", "description": "1.5x speed, increased usage" }
      ],
      "availability_nux": null,
      "upgrade": null,
      "base_instructions": "You are Codex, a coding agent based on GPT-5. You help the user with software development tasks, inspect code carefully, make scoped changes, and verify your work.",
      "supports_reasoning_summaries": true,
      "default_reasoning_summary": "none",
      "support_verbosity": true,
      "default_verbosity": "low",
      "apply_patch_tool_type": "freeform",
      "web_search_tool_type": "text_and_image",
      "truncation_policy": { "mode": "tokens", "limit": 10000 },
      "supports_parallel_tool_calls": true,
      "supports_image_detail_original": true,
      "context_window": 272000,
      "max_context_window": 272000,
      "effective_context_window_percent": 95,
      "experimental_supported_tools": [],
      "input_modalities": ["text", "image"],
      "supports_search_tool": true
    }
  ]
}
'@
}

function Get-FallbackCatalogJson {
    $localCatalogPath = Join-Path (Get-Location) "dgsis-model-catalog.json"
    if (Test-Path -LiteralPath $localCatalogPath) {
        return Get-Content -LiteralPath $localCatalogPath -Raw
    }

    try {
        $response = Invoke-WebRequest -Uri $FallbackCatalogUrl -UseBasicParsing -TimeoutSec 30
        $content = $response.Content
        if ($content -is [byte[]]) {
            $content = [System.Text.Encoding]::UTF8.GetString($content)
        }
        if (-not [string]::IsNullOrWhiteSpace($content)) {
            return [string]$content
        }
    }
    catch {
    }

    return Get-EmbeddedFallbackCatalogJson
}

function Get-WindowsCodexArchitecture {
    param([string]$Override = "")

    if (-not [string]::IsNullOrWhiteSpace($Override)) {
        return $Override
    }

    $processorArchitecture = $null
    try {
        $processor = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        if ($null -ne $processor) {
            $processorArchitecture = [int]$processor.Architecture
        }
    }
    catch {
    }

    if ($null -eq $processorArchitecture) {
        try {
            $wmicOutput = & wmic cpu get Architecture /value 2>$null
            $architectureLine = @($wmicOutput | Where-Object { $_ -match '^Architecture=' } | Select-Object -First 1)
            if ($architectureLine.Count -gt 0) {
                $processorArchitecture = [int](($architectureLine[0] -split '=', 2)[1])
            }
        }
        catch {
        }
    }

    switch ($processorArchitecture) {
        9 { return "X64" }
        12 { return "Arm64" }
    }

    $envArchitectures = @(
        [Environment]::GetEnvironmentVariable("PROCESSOR_ARCHITECTURE"),
        [Environment]::GetEnvironmentVariable("PROCESSOR_ARCHITEW6432")
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    if (@($envArchitectures | Where-Object { $_ -match 'ARM64|AARCH64' }).Count -gt 0) {
        return "Arm64"
    }
    if (@($envArchitectures | Where-Object { $_ -match 'AMD64|X64' }).Count -gt 0) {
        return "X64"
    }

    try {
        $runtimeArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
        if ($runtimeArchitecture -match 'Arm64') {
            return "Arm64"
        }
        if ($runtimeArchitecture -match 'X64') {
            return "X64"
        }
    }
    catch {
    }

    if ([Environment]::Is64BitOperatingSystem) {
        return "X64"
    }

    Fail "Arquitetura Windows nao suportada. O Codex CLI requer Windows 64-bit x64 ou ARM64."
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

function Invoke-InstallerSelfTest {
    Write-Step "Executando autotestes do instalador Windows"

    if ((Get-WindowsCodexArchitecture -Override "X64") -ne "X64") {
        Fail "Autoteste falhou: override X64 nao retornou X64."
    }
    if ((Get-WindowsCodexArchitecture -Override "Arm64") -ne "Arm64") {
        Fail "Autoteste falhou: override Arm64 nao retornou Arm64."
    }

    $sampleLines = @(
        'model = "gpt-5.5"',
        'personality = "friendly"',
        '',
        '[windows]',
        'sandbox = "workspace-write"',
        '',
        '[model_providers.dgsis]',
        'name = "old"',
        '',
        '[plugins."cloudflare@openai-curated"]',
        'enabled = true'
    )

    $sampleLines = Set-TopLevelKey $sampleLines "model" 'model = "cx/gpt-5.5"'
    $sampleLines = Set-TopLevelKey $sampleLines "model_provider" 'model_provider = "dgsis"'
    $sampleLines = Remove-Section $sampleLines "model_providers.dgsis"
    $sampleLines = Remove-Section $sampleLines 'plugins."cloudflare@openai-curated"'
    $sampleLines = Set-SectionKey $sampleLines "windows" "sandbox" 'sandbox = "elevated"'
    $sampleLines = @($sampleLines + "" + "[model_providers.dgsis]" + 'name = "DGSIS Gateway"' + "" + '[plugins."cloudflare@openai-curated"]' + 'enabled = false')
    $sampleText = $sampleLines -join "`n"

    foreach ($pattern in @('(?m)^model = "cx/gpt-5\.5"$', '(?m)^model_provider = "dgsis"$', '(?m)^\[model_providers\.dgsis\]$', '(?m)^\[plugins\."cloudflare@openai-curated"\]$')) {
        if (@([regex]::Matches($sampleText, $pattern)).Count -ne 1) {
            Fail "Autoteste falhou: padrao duplicado ou ausente: $pattern"
        }
    }
    if ($sampleText -notmatch '(?m)^sandbox = "elevated"$') {
        Fail "Autoteste falhou: sandbox elevated nao foi aplicado."
    }

    $catalog = Get-EmbeddedFallbackCatalogJson | ConvertFrom-Json
    if (@($catalog.models | Where-Object { $_.slug -eq "cx/gpt-5.5" }).Count -ne 1) {
        Fail "Autoteste falhou: catalogo fallback invalido."
    }

    $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-dgsis-selftest-{0}.json" -f ([Guid]::NewGuid().ToString("N")))
    try {
        Set-TextFileUtf8NoBom -Path $tempFile -Content (Get-EmbeddedFallbackCatalogJson)
        $bytes = [System.IO.File]::ReadAllBytes($tempFile)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) {
            Fail "Autoteste falhou: arquivo UTF-8 foi gravado com BOM."
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempFile) {
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Ok "Autotestes Windows passaram"
}

$isWindowsRuntime = $env:OS -eq "Windows_NT"
$isWindowsVariable = Get-Variable -Name IsWindows -Scope Global -ErrorAction SilentlyContinue
if ($null -ne $isWindowsVariable) {
    $isWindowsRuntime = [bool]$isWindowsVariable.Value
}

if (-not $isWindowsRuntime) {
    Fail "Este instalador e somente para Windows PowerShell/PowerShell no Windows."
}

if ($SelfTest) {
    Invoke-InstallerSelfTest
    exit 0
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Step "Instalando ou atualizando o Codex CLI standalone"
$codexArchitecture = Get-WindowsCodexArchitecture -Override $ArchitectureOverride
Write-Ok "Arquitetura detectada para Codex: Windows $codexArchitecture"

$oldNonInteractive = $env:CODEX_NON_INTERACTIVE
$patchedInstallerPath = $null
try {
    $env:CODEX_NON_INTERACTIVE = "1"
    $installerResponse = Invoke-WebRequest -Uri $CodexInstallUrl -UseBasicParsing -TimeoutSec 120
    $installerContent = $installerResponse.Content
    if ($installerContent -is [byte[]]) {
        $installerContent = [System.Text.Encoding]::UTF8.GetString($installerContent)
    }

    $compatibleArchitectureLine = '$architecture = "' + $codexArchitecture + '"'
    $architectureAssignmentPattern = '(?m)^\s*\$architecture\s*=\s*\[System\.Runtime\.InteropServices\.RuntimeInformation\]::OSArchitecture\s*$'
    if ($installerContent -notmatch $architectureAssignmentPattern) {
        Fail "Nao consegui preparar o instalador oficial para Windows $codexArchitecture. O formato do instalador oficial mudou."
    }
    $installerContent = [regex]::Replace($installerContent, $architectureAssignmentPattern, $compatibleArchitectureLine)

    $patchedInstallerPath = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-install-patched-{0}.ps1" -f ([Guid]::NewGuid().ToString("N")))
    Set-TextFileUtf8NoBom -Path $patchedInstallerPath -Content $installerContent
    & $patchedInstallerPath
}
finally {
    $env:CODEX_NON_INTERACTIVE = $oldNonInteractive
    if ($patchedInstallerPath -and (Test-Path -LiteralPath $patchedInstallerPath)) {
        Remove-Item -LiteralPath $patchedInstallerPath -Force -ErrorAction SilentlyContinue
    }
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
$catalogJson = $null
try {
    $bundledJson = & $preferredCodexExe debug models --bundled
    $bundledCatalog = $bundledJson | ConvertFrom-Json
    $model = @($bundledCatalog.models | Where-Object { $_.slug -eq "gpt-5.5" })[0]

    if ($null -eq $model) {
        throw "O catalogo embutido do Codex nao contem gpt-5.5."
    }

    $model.slug = $DgsisModel
    $model.display_name = "DGSIS GPT-5.5"
    $model.description = "Modelo GPT-5.5 via gateway DGSIS."
    $model.availability_nux = $null

    $catalog = [pscustomobject]@{ models = @($model) }
    $catalogJson = $catalog | ConvertTo-Json -Depth 100
}
catch {
    Write-Host "Aviso: nao foi possivel transformar o catalogo embutido; usando fallback DGSIS." -ForegroundColor Yellow
    $catalogJson = Get-FallbackCatalogJson
}

if ([string]::IsNullOrWhiteSpace($catalogJson)) {
    Fail "Nao foi possivel gerar nem carregar o catalogo DGSIS."
}

$catalogCheck = $catalogJson | ConvertFrom-Json
if (@($catalogCheck.models | Where-Object { $_.slug -eq $DgsisModel }).Count -ne 1) {
    Fail "Catalogo DGSIS invalido: modelo $DgsisModel ausente."
}

Set-TextFileUtf8NoBom -Path $catalogPath -Content $catalogJson
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
