param(
    [string]$Token = "",
    [ValidateSet("", "X64", "Arm64")]
    [string]$ArchitectureOverride = "",
    [switch]$SkipDependencies,
    [switch]$SkipVSCode,
    [switch]$SkipDesktop,
    [switch]$SkipLiveTests,
    [switch]$SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$DgsisBaseUrl = "https://gtw.dgsis.com.br/v1"
$DgsisModel = "cx/gpt-5.5"
$DgsisProvider = "dgsis"
$EnvKeyName = "DGSIS_API_KEY"
$CodexHomeEnvName = "CODEX_HOME"
$CodexInstallUrl = "https://chatgpt.com/codex/install.ps1"
$FallbackCatalogUrl = "https://raw.githubusercontent.com/soxvip/codex-dgsis-installer/main/dgsis-model-catalog.json"
$CodexVSCodeExtensionId = "openai.chatgpt"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "OK: $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "Aviso: $Message" -ForegroundColor Yellow
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

function Get-NormalizedPathEntry {
    param([string]$Entry)

    if ([string]::IsNullOrWhiteSpace($Entry)) {
        return ""
    }

    try {
        return [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Entry)).TrimEnd("\")
    }
    catch {
        return $Entry.TrimEnd("\")
    }
}

function Prepend-PathEntry {
    param(
        [string]$PathValue,
        [string]$Entry
    )

    $normalizedEntry = Get-NormalizedPathEntry -Entry $Entry
    $parts = New-Object System.Collections.Generic.List[string]
    [void]$parts.Add($Entry)

    if (-not [string]::IsNullOrWhiteSpace($PathValue)) {
        foreach ($part in ($PathValue -split ";")) {
            if ([string]::IsNullOrWhiteSpace($part)) {
                continue
            }

            if ((Get-NormalizedPathEntry -Entry $part) -ieq $normalizedEntry) {
                continue
            }

            [void]$parts.Add($part)
        }
    }

    return ($parts.ToArray() -join ";")
}

function Remove-PathEntriesByRegex {
    param(
        [string]$PathValue,
        [string[]]$Patterns
    )

    $parts = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return ""
    }

    foreach ($part in ($PathValue -split ";")) {
        if ([string]::IsNullOrWhiteSpace($part)) {
            continue
        }

        $drop = $false
        foreach ($pattern in $Patterns) {
            if ($part -match $pattern) {
                $drop = $true
                break
            }
        }

        if (-not $drop) {
            [void]$parts.Add($part)
        }
    }

    return ($parts.ToArray() -join ";")
}

function Refresh-ProcessPathFromRegistry {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $combined = @($machinePath, $userPath) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if ($combined.Count -gt 0) {
        $env:Path = $combined -join ";"
    }
}

function Test-CommandAvailable {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-NativeProcessCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [string[]]$ArgumentList = @()
    )

    $stdoutPath = Join-Path $env:TEMP ("codex-dgsis-stdout-{0}.txt" -f ([Guid]::NewGuid().ToString("N")))
    $stderrPath = Join-Path $env:TEMP ("codex-dgsis-stderr-{0}.txt" -f ([Guid]::NewGuid().ToString("N")))

    try {
        $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        $stdout = @()
        $stderr = @()

        if (Test-Path -LiteralPath $stdoutPath) {
            $stdout = @(Get-Content -LiteralPath $stdoutPath -ErrorAction SilentlyContinue)
        }
        if (Test-Path -LiteralPath $stderrPath) {
            $stderr = @(Get-Content -LiteralPath $stderrPath -ErrorAction SilentlyContinue)
        }

        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Stdout = $stdout
            Stderr = $stderr
        }
    }
    finally {
        Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
    }
}

function Install-WingetPackage {
    param(
        [string]$Id,
        [string]$DisplayName,
        [string[]]$CommandNames = @()
    )

    foreach ($commandName in @($CommandNames)) {
        if (Test-CommandAvailable -Name $commandName) {
            Write-Ok "$DisplayName ja disponivel ($commandName)"
            return
        }
    }

    if (-not (Test-CommandAvailable -Name "winget")) {
        Fail "winget nao encontrado. Instale o App Installer da Microsoft Store ou instale $DisplayName manualmente."
    }

    Write-Step "Instalando $DisplayName via winget"
    $wingetArgs = @(
        "install",
        "--id", $Id,
        "--exact",
        "--accept-package-agreements",
        "--accept-source-agreements",
        "--disable-interactivity"
    )

    $output = & winget @wingetArgs 2>&1
    $exitCode = $LASTEXITCODE
    foreach ($line in $output) {
        Write-Host $line
    }

    if ($exitCode -ne 0) {
        $text = ($output | Out-String)
        if ($text -notmatch 'already installed|No available upgrade|Ja.*instalado|Nenhuma atualizacao') {
            Fail "winget falhou ao instalar $DisplayName. Saida: $text"
        }
    }

    Refresh-ProcessPathFromRegistry
    foreach ($commandName in @($CommandNames)) {
        if (Test-CommandAvailable -Name $commandName) {
            Write-Ok "$DisplayName pronto ($commandName)"
            return
        }
    }

    Write-Host "Aviso: $DisplayName foi instalado, mas o comando ainda nao apareceu nesta sessao. Uma nova janela do PowerShell deve resolver." -ForegroundColor Yellow
}

function Install-ClientDependencies {
    if ($SkipDependencies) {
        Write-Host "Pulando instalacao de dependencias por -SkipDependencies." -ForegroundColor Yellow
        return
    }

    Install-WingetPackage -Id "Git.Git" -DisplayName "Git" -CommandNames @("git")
    Install-WingetPackage -Id "OpenJS.NodeJS.LTS" -DisplayName "Node.js LTS" -CommandNames @("node", "npm")
    Install-WingetPackage -Id "Python.Python.3.14" -DisplayName "Python" -CommandNames @("python", "py")

    if (-not $SkipVSCode) {
        Install-WingetPackage -Id "Microsoft.VisualStudioCode" -DisplayName "Visual Studio Code" -CommandNames @("code")
    }
}

function Install-CodexVSCodeExtensionWithCapture {
    $codeCommand = Get-Command code -ErrorAction SilentlyContinue
    if ($null -eq $codeCommand) {
        Write-Host "Aviso: comando code nao encontrado. VS Code pode precisar ser aberto uma vez ou PATH atualizado." -ForegroundColor Yellow
        return
    }

    $result = Invoke-NativeProcessCapture -FilePath $codeCommand.Source -ArgumentList @("--install-extension", $CodexVSCodeExtensionId, "--force")
    foreach ($line in @($result.Stdout)) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            Write-Host $line
        }
    }
    foreach ($line in @($result.Stderr)) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            Write-Host $line -ForegroundColor Yellow
        }
    }

    $listResult = Invoke-NativeProcessCapture -FilePath $codeCommand.Source -ArgumentList @("--list-extensions")
    $installedExtensions = New-Object System.Collections.Generic.List[string]
    foreach ($line in @($listResult.Stdout)) {
        [void]$installedExtensions.Add($line.Trim())
    }

    if ($result.ExitCode -ne 0 -and -not $installedExtensions.Contains($CodexVSCodeExtensionId)) {
        Fail "Falha ao instalar extensao VS Code $CodexVSCodeExtensionId."
    }
    if ($listResult.ExitCode -eq 0 -and -not $installedExtensions.Contains($CodexVSCodeExtensionId)) {
        Fail "VS Code nao confirmou a extensao $CodexVSCodeExtensionId apos a instalacao."
    }

    Write-Ok "Extensao VS Code pronta: $CodexVSCodeExtensionId"
}

function Install-CodexVSCodeExtension {
    if ($SkipVSCode) {
        Write-Host "Pulando VS Code por -SkipVSCode." -ForegroundColor Yellow
        return
    }

    if (-not (Test-CommandAvailable -Name "code")) {
        Write-Host "Aviso: comando code nao encontrado. VS Code pode precisar ser aberto uma vez ou PATH atualizado." -ForegroundColor Yellow
        return
    }

    Write-Step "Instalando extensao Codex/ChatGPT no VS Code"
    Install-CodexVSCodeExtensionWithCapture
    return
}

function Install-CodexDesktopApp {
    param(
        [string]$CodexExe,
        [string]$CodexHome,
        [string]$WorkspacePath
    )

    if ($SkipDesktop) {
        Write-Host "Pulando Codex Desktop por -SkipDesktop." -ForegroundColor Yellow
        return
    }

    if (-not (Test-Path -LiteralPath $CodexExe -PathType Leaf)) {
        Fail "Nao encontrei codex.exe para instalar/abrir Codex Desktop."
    }

    if ($WorkspacePath.Contains('"')) {
        Fail "Caminho do workspace contem aspas e nao pode ser passado para codex app: $WorkspacePath"
    }

    Write-Step "Instalando ou abrindo Codex Desktop"
    if (-not $SelfTest) {
        $desktopProcesses = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -ceq "Codex" })
        if ($desktopProcesses.Count -gt 0) {
            Write-Host "Fechando Codex Desktop para recarregar catalogo e plugins." -ForegroundColor Yellow
            foreach ($desktopProcess in $desktopProcesses) {
                try {
                    Stop-Process -Id $desktopProcess.Id -Force -ErrorAction Stop
                }
                catch {
                }
            }
            Start-Sleep -Seconds 2
        }
    }

    $oldCodexHome = $env:CODEX_HOME
    $process = $null
    $completed = $false
    try {
        $env:CODEX_HOME = $CodexHome
        $workspaceArg = '"' + $WorkspacePath + '"'
        $process = Start-Process -FilePath $CodexExe -ArgumentList @("app", $workspaceArg) -WorkingDirectory $WorkspacePath -WindowStyle Hidden -PassThru
        $completed = $process.WaitForExit(45000)
    }
    catch {
        Fail "Falha ao iniciar Codex Desktop: $($_.Exception.Message)"
    }
    finally {
        $env:CODEX_HOME = $oldCodexHome
    }

    if ($completed -and $process.ExitCode -ne 0) {
        Fail "Falha ao instalar ou abrir Codex Desktop. Codigo: $($process.ExitCode)"
    }

    if (-not $completed) {
        Write-Host "Codex Desktop ainda inicializando em segundo plano." -ForegroundColor Yellow
    }

    Write-Ok "Codex Desktop acionado com CODEX_HOME=$CodexHome"
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

function Test-DgsisOpenAIModelId {
    param([string]$ModelId)

    if ([string]::IsNullOrWhiteSpace($ModelId)) {
        return $false
    }

    if ($ModelId -notmatch '^cx\/(gpt-|o[0-9]|codex-|chatgpt-)') {
        return $false
    }

    return $ModelId -notmatch '(?i)claude|anthropic|gemini|deepseek|qwen|llama|mistral|kimi|glm|minimax|grok|oss'
}

function Get-DgsisOpenAIModelIds {
    param([object]$ModelsResponse)

    $ids = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($ModelsResponse.data)) {
        $id = [string]$item.id
        if (Test-DgsisOpenAIModelId -ModelId $id) {
            [void]$ids.Add($id)
        }
    }

    return @($ids.ToArray() | Sort-Object -Unique)
}

function Get-DgsisTemplateSlugCandidates {
    param([string]$ModelId)

    $slug = $ModelId -replace '^cx/', ''
    $candidates = New-Object System.Collections.Generic.List[string]
    [void]$candidates.Add($slug)

    $withoutReview = $slug -replace '-review$', ''
    if ($withoutReview -ne $slug) {
        [void]$candidates.Add($withoutReview)
    }

    $base = $withoutReview -replace '-(none|low|medium|high|xhigh|spark)$', ''
    if ($base -ne $withoutReview) {
        [void]$candidates.Add($base)
    }

    if ($slug -match '^gpt-5\.3-codex') {
        [void]$candidates.Add('gpt-5.3-codex')
    }
    if ($slug -match '^gpt-5\.4-mini') {
        [void]$candidates.Add('gpt-5.4-mini')
    }
    if ($slug -match '^gpt-5\.4') {
        [void]$candidates.Add('gpt-5.4')
    }
    if ($slug -match '^gpt-5\.5') {
        [void]$candidates.Add('gpt-5.5')
    }

    return @($candidates.ToArray() | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

function Get-DgsisModelDisplayName {
    param([string]$ModelId)

    $name = $ModelId -replace '^cx/', ''
    $parts = @($name -split '-' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $displayParts = foreach ($part in $parts) {
        if ($part -match '^(gpt|codex|o[0-9].*)$') {
            $part.ToUpperInvariant()
        }
        else {
            $part.Substring(0, 1).ToUpperInvariant() + $part.Substring(1)
        }
    }

    return "DGSIS " + ($displayParts -join ' ')
}

function Copy-ModelTemplate {
    param([object]$Template)

    return ($Template | ConvertTo-Json -Depth 100 | ConvertFrom-Json)
}

function New-DgsisModelCatalogJson {
    param(
        [object]$ModelsResponse,
        [object]$BundledCatalog,
        [string]$DefaultModel
    )

    $openAiModelIds = @(Get-DgsisOpenAIModelIds -ModelsResponse $ModelsResponse)
    if (@($openAiModelIds | Where-Object { $_ -eq $DefaultModel }).Count -ne 1) {
        Fail "O token foi aceito, mas o modelo OpenAI padrao $DefaultModel nao apareceu em /models."
    }

    $templates = @{}
    foreach ($model in @($BundledCatalog.models)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$model.slug)) {
            $templates[[string]$model.slug] = $model
        }
    }

    $fallbackCatalog = Get-FallbackCatalogJson | ConvertFrom-Json
    foreach ($model in @($fallbackCatalog.models)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$model.slug)) {
            $templates[[string]$model.slug] = $model
            $templates[([string]$model.slug -replace '^cx/', '')] = $model
        }
    }

    $defaultTemplate = $null
    foreach ($candidate in @('gpt-5.5', $DefaultModel, 'cx/gpt-5.5')) {
        if ($templates.ContainsKey($candidate)) {
            $defaultTemplate = $templates[$candidate]
            break
        }
    }
    if ($null -eq $defaultTemplate) {
        Fail "Nao encontrei template de modelo OpenAI para montar catalogo DGSIS."
    }

    $catalogModels = New-Object System.Collections.Generic.List[object]
    $priority = 0
    foreach ($modelId in $openAiModelIds) {
        $template = $null
        foreach ($candidate in @(Get-DgsisTemplateSlugCandidates -ModelId $modelId)) {
            if ($templates.ContainsKey($candidate)) {
                $template = $templates[$candidate]
                break
            }
        }
        if ($null -eq $template) {
            $template = $defaultTemplate
        }

        $model = Copy-ModelTemplate -Template $template
        $model.slug = $modelId
        $model.display_name = Get-DgsisModelDisplayName -ModelId $modelId
        $model.description = "Modelo OpenAI $modelId via gateway DGSIS."
        $model.visibility = "list"
        $model.supported_in_api = $true
        $model.priority = if ($modelId -eq $DefaultModel) { 0 } else { $priority + 10 }
        if ($model.PSObject.Properties.Name -contains "availability_nux") {
            $model.availability_nux = $null
        }
        [void]$catalogModels.Add($model)
        $priority += 1
    }

    return ([pscustomobject]@{ models = @($catalogModels.ToArray()) } | ConvertTo-Json -Depth 100)
}

function Write-CodexModelsCache {
    param(
        [string]$CatalogJson,
        [string]$ModelsCachePath,
        [string]$BackupDir,
        [string]$CodexVersion
    )

    if (Test-Path -LiteralPath $ModelsCachePath -PathType Leaf) {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $cacheBackupPath = Join-Path $BackupDir "models_cache.$timestamp.json"
        Copy-Item -LiteralPath $ModelsCachePath -Destination $cacheBackupPath -Force
    }

    $catalog = $CatalogJson | ConvertFrom-Json
    $clientVersion = ($CodexVersion -replace '^codex-cli\s*', '').Trim()
    $cache = [pscustomobject]@{
        fetched_at = (Get-Date).ToUniversalTime().ToString("o")
        etag = "dgsis-local-openai-only"
        client_version = $clientVersion
        models = @($catalog.models)
    }

    Set-TextFileUtf8NoBom -Path $ModelsCachePath -Content (($cache | ConvertTo-Json -Depth 100) + [Environment]::NewLine)
}

function Get-WindowsCodexArchitecture {
    param([string]$Override = "")

    if (-not [string]::IsNullOrWhiteSpace($Override)) {
        return $Override
    }

    $machineArchitectureValues = @(
        [Environment]::GetEnvironmentVariable("PROCESSOR_ARCHITECTURE", "Machine"),
        [Environment]::GetEnvironmentVariable("PROCESSOR_IDENTIFIER", "Machine")
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    try {
        $machineEnvironment = Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" -ErrorAction Stop
        $machineArchitectureValues += @(
            $machineEnvironment.PROCESSOR_ARCHITECTURE,
            $machineEnvironment.PROCESSOR_IDENTIFIER
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }
    catch {
    }

    if (@($machineArchitectureValues | Where-Object { $_ -match 'ARM64|AARCH64' }).Count -gt 0) {
        return "Arm64"
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

function Get-AlternateCodexArchitecture {
    param([string]$Architecture)

    if ($Architecture -eq "X64") {
        return "Arm64"
    }

    return "X64"
}

function Test-ArchitectureInstallFailure {
    param([string]$Message)

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return $false
    }

    return $Message -match 'not a valid application for this OS platform|not a valid Win32 application|NativeCommandFailed|Installed Codex command failed verification|This version of .* is not compatible|Bad CPU type'
}

function Get-CurrentPowerShellPath {
    try {
        $processPath = (Get-Process -Id $PID -ErrorAction Stop).Path
        if (-not [string]::IsNullOrWhiteSpace($processPath) -and (Test-Path -LiteralPath $processPath)) {
            return $processPath
        }
    }
    catch {
    }

    $windowsPowerShell = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path -LiteralPath $windowsPowerShell) {
        return $windowsPowerShell
    }

    return "powershell.exe"
}

function Get-CodexInstallerContent {
    $installerResponse = Invoke-WebRequest -Uri $CodexInstallUrl -UseBasicParsing -TimeoutSec 120
    $installerContent = $installerResponse.Content
    if ($installerContent -is [byte[]]) {
        $installerContent = [System.Text.Encoding]::UTF8.GetString($installerContent)
    }

    return [string]$installerContent
}

function Invoke-CodexOfficialInstaller {
    param(
        [string]$Architecture,
        [string]$InstallerContent
    )

    $compatibleArchitectureLine = '$architecture = "' + $Architecture + '"'
    $architectureAssignmentPattern = '(?m)^\s*\$architecture\s*=\s*\[System\.Runtime\.InteropServices\.RuntimeInformation\]::OSArchitecture\s*$'
    if ($InstallerContent -notmatch $architectureAssignmentPattern) {
        Fail "Nao consegui preparar o instalador oficial para Windows $Architecture. O formato do instalador oficial mudou."
    }

    $patchedInstallerContent = [regex]::Replace($InstallerContent, $architectureAssignmentPattern, $compatibleArchitectureLine)
    $patchedInstallerPath = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-install-patched-{0}.ps1" -f ([Guid]::NewGuid().ToString("N")))

    try {
        Set-TextFileUtf8NoBom -Path $patchedInstallerPath -Content $patchedInstallerContent
        $powerShellPath = Get-CurrentPowerShellPath
        $installerOutput = & $powerShellPath -NoProfile -ExecutionPolicy Bypass -File $patchedInstallerPath 2>&1
        $installerExitCode = $LASTEXITCODE

        foreach ($line in $installerOutput) {
            Write-Host $line
        }

        $installerOutputText = ($installerOutput | Out-String)
        if ($installerExitCode -ne 0) {
            throw "Falha no instalador oficial para Windows $Architecture. $installerOutputText"
        }

        return $installerOutputText
    }
    finally {
        if (Test-Path -LiteralPath $patchedInstallerPath) {
            Remove-Item -LiteralPath $patchedInstallerPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-FirstExistingFile {
    param([string[]]$Paths)

    foreach ($path in @($Paths)) {
        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path -PathType Leaf)) {
            return $path
        }
    }

    return $null
}

function Sync-CodexWindowsHelperFiles {
    param(
        [string]$PreferredBinDir,
        [string]$StandaloneCurrentDir = ""
    )

    if ([string]::IsNullOrWhiteSpace($StandaloneCurrentDir)) {
        $StandaloneCurrentDir = Join-Path $env:USERPROFILE ".codex\packages\standalone\current"
    }

    New-Item -ItemType Directory -Force -Path $PreferredBinDir | Out-Null

    $resourceDir = Join-Path $StandaloneCurrentDir "codex-resources"
    $pathDir = Join-Path $StandaloneCurrentDir "codex-path"
    $appRuntimeBin = Join-Path $env:LOCALAPPDATA "OpenAI\Codex\bin"

    $helpers = @(
        [pscustomobject]@{
            Name = "codex-windows-sandbox-setup.exe"
            Sources = @(
                (Join-Path $resourceDir "codex-windows-sandbox-setup.exe"),
                (Join-Path $appRuntimeBin "codex-windows-sandbox-setup.exe")
            )
            Required = $true
        },
        [pscustomobject]@{
            Name = "codex-command-runner.exe"
            Sources = @(
                (Join-Path $resourceDir "codex-command-runner.exe"),
                (Join-Path $appRuntimeBin "codex-command-runner.exe")
            )
            Required = $false
        },
        [pscustomobject]@{
            Name = "rg.exe"
            Sources = @(
                (Join-Path $pathDir "rg.exe"),
                (Join-Path $appRuntimeBin "rg.exe")
            )
            Required = $false
        }
    )

    foreach ($helper in $helpers) {
        $destination = Join-Path $PreferredBinDir $helper.Name
        if (Test-Path -LiteralPath $destination -PathType Leaf) {
            continue
        }

        $source = Get-FirstExistingFile -Paths ([string[]]$helper.Sources)
        if ([string]::IsNullOrWhiteSpace($source)) {
            if ($helper.Required) {
                Fail "O Codex CLI foi instalado, mas nao encontrei $($helper.Name). Rode o instalador novamente ou verifique se o antivirus bloqueou o arquivo."
            }
            continue
        }

        Copy-Item -LiteralPath $source -Destination $destination -Force
    }

    if (-not (Test-Path -LiteralPath (Join-Path $PreferredBinDir "codex-windows-sandbox-setup.exe") -PathType Leaf)) {
        Fail "O auxiliar de sandbox do Windows nao ficou disponivel em $PreferredBinDir."
    }
}

function Get-PwshShimSource {
    return @'
using System;
using System.Diagnostics;
using System.Text;

internal static class PwshShim
{
    private static int Main(string[] args)
    {
        string target = Environment.ExpandEnvironmentVariables(@"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe");
        var startInfo = new ProcessStartInfo(target)
        {
            UseShellExecute = false,
            Arguments = JoinArguments(args)
        };

        using (var process = Process.Start(startInfo))
        {
            process.WaitForExit();
            return process.ExitCode;
        }
    }

    private static string JoinArguments(string[] args)
    {
        var builder = new StringBuilder();
        for (int i = 0; i < args.Length; i++)
        {
            if (i > 0) builder.Append(' ');
            builder.Append(QuoteArgument(args[i]));
        }
        return builder.ToString();
    }

    private static string QuoteArgument(string value)
    {
        if (value.Length == 0) return "\"\"";
        bool needsQuotes = value.IndexOfAny(new[] { ' ', '\t', '\n', '\v', '"' }) >= 0;
        if (!needsQuotes) return value;

        var builder = new StringBuilder();
        builder.Append('"');
        int backslashes = 0;
        foreach (char c in value)
        {
            if (c == '\\')
            {
                backslashes++;
                continue;
            }
            if (c == '"')
            {
                builder.Append('\\', backslashes * 2 + 1);
                builder.Append('"');
                backslashes = 0;
                continue;
            }
            builder.Append('\\', backslashes);
            backslashes = 0;
            builder.Append(c);
        }
        builder.Append('\\', backslashes * 2);
        builder.Append('"');
        return builder.ToString();
    }
}
'@
}

function Get-CSharpCompilerPath {
    $candidates = @(
        (Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"),
        (Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    $command = Get-Command csc.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $command) {
        return $command.Source
    }

    return $null
}

function Install-PwshShim {
    param([string]$PreferredBinDir)

    $shimPath = Join-Path $PreferredBinDir "pwsh.exe"
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-pwsh-shim-{0}" -f ([Guid]::NewGuid().ToString("N")))
    $sourcePath = Join-Path $tempDir "PwshShim.cs"
    $compiledShimPath = Join-Path $tempDir "pwsh.exe"
    $compiler = Get-CSharpCompilerPath

    if (Test-Path -LiteralPath $shimPath -PathType Leaf) {
        $existingOutput = & $shimPath -NoProfile -Command "Write-Output CODEX_PWSH_SHIM_OK" 2>&1
        if ($LASTEXITCODE -eq 0 -and (($existingOutput | Out-String) -match "CODEX_PWSH_SHIM_OK")) {
            Write-Ok "Shim pwsh.exe ja pronto em $shimPath"
            return
        }
    }

    if ([string]::IsNullOrWhiteSpace($compiler)) {
        Write-Host "Aviso: csc.exe nao encontrado; nao foi possivel gerar shim pwsh.exe. Se o cliente usa PowerShell da Microsoft Store, instale .NET Framework Developer Pack ou remova o alias pwsh da Store." -ForegroundColor Yellow
        return
    }

    try {
        New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
        Set-TextFileUtf8NoBom -Path $sourcePath -Content (Get-PwshShimSource)
        $compileOutput = & $compiler /nologo /target:exe /platform:anycpu /optimize+ /out:$compiledShimPath $sourcePath 2>&1
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0 -or -not (Test-Path -LiteralPath $compiledShimPath -PathType Leaf)) {
            Fail "Falha ao compilar shim pwsh.exe. Saida: $($compileOutput | Out-String)"
        }

        try {
            Copy-Item -LiteralPath $compiledShimPath -Destination $shimPath -Force -ErrorAction Stop
        }
        catch {
            if (Test-Path -LiteralPath $shimPath -PathType Leaf) {
                $existingOutput = & $shimPath -NoProfile -Command "Write-Output CODEX_PWSH_SHIM_OK" 2>&1
                if ($LASTEXITCODE -eq 0 -and (($existingOutput | Out-String) -match "CODEX_PWSH_SHIM_OK")) {
                    Write-Host "Aviso: shim pwsh.exe esta em uso; mantendo shim existente valido." -ForegroundColor Yellow
                    Write-Ok "Shim pwsh.exe pronto em $shimPath"
                    return
                }
            }

            Fail "Falha ao atualizar shim pwsh.exe em $shimPath. Feche Codex/terminais usando pwsh.exe e rode novamente. Erro: $($_.Exception.Message)"
        }

        $testOutput = & $shimPath -NoProfile -Command "Write-Output CODEX_PWSH_SHIM_OK" 2>&1
        if ($LASTEXITCODE -ne 0 -or (($testOutput | Out-String) -notmatch "CODEX_PWSH_SHIM_OK")) {
            Fail "Shim pwsh.exe foi criado, mas nao executou corretamente. Saida: $($testOutput | Out-String)"
        }

        Write-Ok "Shim pwsh.exe pronto em $shimPath"
    }
    finally {
        if (Test-Path -LiteralPath $tempDir) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Set-CodexPowerShellProfilePathFix {
    param([string]$PreferredBinDir)

    $profileCodexBin = $PreferredBinDir.Replace("'", "''")
    $profileBlock = @"
# BEGIN CODEX_DGSIS_PATH_FIX
`$codexBin = '$profileCodexBin'
`$pathParts = `$env:PATH -split ';' | Where-Object {
    `$_ -and
    (`$_ -notmatch '^C:\\Program Files\\WindowsApps\\Microsoft\.PowerShell_') -and
    (`$_ -ne `$codexBin)
}
if (Test-Path -LiteralPath `$codexBin) {
    `$env:PATH = (@(`$codexBin) + `$pathParts) -join ';'
} else {
    `$env:PATH = `$pathParts -join ';'
}
# END CODEX_DGSIS_PATH_FIX
"@

    $profilePaths = @(
        (Join-Path $env:USERPROFILE "Documents\PowerShell\profile.ps1"),
        (Join-Path $env:USERPROFILE "Documents\WindowsPowerShell\profile.ps1")
    )

    foreach ($profilePath in $profilePaths) {
        $profileDir = Split-Path -Parent $profilePath
        New-Item -ItemType Directory -Force -Path $profileDir | Out-Null

        $existing = ""
        if (Test-Path -LiteralPath $profilePath -PathType Leaf) {
            $existing = Get-Content -LiteralPath $profilePath -Raw
        }

        $clean = [regex]::Replace($existing, '(?s)\r?\n?# BEGIN CODEX_DGSIS_PATH_FIX.*?# END CODEX_DGSIS_PATH_FIX\r?\n?', "`r`n")
        $newContent = ($clean.TrimEnd() + "`r`n`r`n" + $profileBlock + "`r`n").TrimStart()
        Set-TextFileUtf8NoBom -Path $profilePath -Content $newContent
    }

    $env:Path = Prepend-PathEntry -PathValue (Remove-PathEntriesByRegex -PathValue $env:Path -Patterns @('^C:\\Program Files\\WindowsApps\\Microsoft\.PowerShell_')) -Entry $PreferredBinDir
    Write-Ok "Perfis PowerShell ajustados para priorizar Codex\\bin"
}

function Get-StableCodexPathValue {
    param([string]$PreferredBinDir)

    Refresh-ProcessPathFromRegistry
    $cleanPath = Remove-PathEntriesByRegex -PathValue $env:Path -Patterns @('^C:\\Program Files\\WindowsApps\\Microsoft\.PowerShell_')
    return Prepend-PathEntry -PathValue $cleanPath -Entry $PreferredBinDir
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
    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
        $psi.EnvironmentVariables[$CodexHomeEnvName] = $env:CODEX_HOME
    }

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

function Invoke-CodexDoctorCheck {
    param([string]$CodexExe)

    Write-Step "Executando codex doctor"

    $lastOutput = ""
    $lastBadText = ""
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $doctorOutput = & $CodexExe doctor --json 2>&1
        $exitCode = $LASTEXITCODE
        $outputText = ($doctorOutput | Out-String)
        $lastOutput = $outputText

        try {
            $doctor = $outputText | ConvertFrom-Json
        }
        catch {
            if ($attempt -lt 3) {
                Write-Warn "codex doctor nao retornou JSON valido na tentativa $attempt; tentando novamente."
                Start-Sleep -Seconds 2
                continue
            }
            Fail "codex doctor nao retornou JSON valido. Saida: $lastOutput"
        }

        $bad = @($doctor.checks.PSObject.Properties | Where-Object { $_.Value.status -ne "ok" })
        $lastBadText = ($bad | ForEach-Object { "$($_.Name): $($_.Value.status) $($_.Value.summary)" }) -join "; "

        if ($exitCode -eq 0 -and $bad.Count -eq 0) {
            Write-Ok "codex doctor: todos checks ok"
            return
        }

        $onlyProviderReachability = ($bad.Count -eq 1 -and [string]$bad[0].Name -eq "network.provider_reachability")
        if ($onlyProviderReachability) {
            if ($attempt -lt 3) {
                Write-Warn "network.provider_reachability falhou na tentativa $attempt; tentando novamente."
                Start-Sleep -Seconds 2
                continue
            }

            Write-Warn "codex doctor ainda acusa network.provider_reachability, mas token, catalogo e model/list do Desktop ja passaram. Continuando."
            return
        }

        if ($attempt -lt 3) {
            Write-Warn "codex doctor falhou na tentativa $attempt; tentando novamente."
            Start-Sleep -Seconds 2
            continue
        }

        if ($bad.Count -gt 0) {
            Fail "codex doctor encontrou problemas: $lastBadText"
        }

        Fail "codex doctor falhou. Saida: $lastOutput"
    }
}

function Invoke-CodexShellToolTest {
    param([string]$CodexExe)

    Write-Step "Testando ferramenta shell do Codex"
    $tag = "CODEX_DGSIS_SHELL_TOOL_OK"
    $jsonlPath = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-dgsis-shell-{0}.jsonl" -f ([Guid]::NewGuid().ToString("N")))
    $lastPath = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-dgsis-shell-last-{0}.txt" -f ([Guid]::NewGuid().ToString("N")))

    try {
        $prompt = "Use uma ferramenta de shell para executar um comando que imprime $tag. Depois responda exatamente $tag e nada mais."
        $args = @("exec", "--ephemeral", "--skip-git-repo-check", "--json", "-o", $lastPath, $prompt)
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $CodexExe
        $psi.Arguments = ($args | ForEach-Object { Quote-ProcessArgument $_ }) -join " "
        $psi.UseShellExecute = $false
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $psi.EnvironmentVariables[$EnvKeyName] = $env:DGSIS_API_KEY
        if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
            $psi.EnvironmentVariables[$CodexHomeEnvName] = $env:CODEX_HOME
        }

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
            Fail "Teste shell tool excedeu 180 segundos."
        }

        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result
        Set-TextFileUtf8NoBom -Path $jsonlPath -Content $stdout
        $exitCode = $process.ExitCode
        $lines = @($stdout -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $diagnosticLines = @($lines + @($stderr -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }))

        $final = ""
        if (Test-Path -LiteralPath $lastPath) {
            $final = (Get-Content -LiteralPath $lastPath -Raw).Trim()
        }

        $commandOk = $false
        $failed = $false
        $lastCommand = ""

        foreach ($line in $diagnosticLines) {
            $lineText = [string]$line
            if ($lineText -match 'CreateProcessAsUserW failed|windows sandbox: runner error') {
                $failed = $true
            }

            if ($lineText.TrimStart().StartsWith("{")) {
                try {
                    $event = $lineText | ConvertFrom-Json
                    if ($event.type -eq "item.completed" -and $event.item.type -eq "command_execution") {
                        $lastCommand = $event.item.command
                        if ($event.item.status -eq "failed" -or $event.item.exit_code -ne 0) {
                            $failed = $true
                        }
                        if ($event.item.exit_code -eq 0 -and $event.item.aggregated_output -match [regex]::Escape($tag)) {
                            $commandOk = $true
                        }
                    }
                }
                catch {
                }
            }
        }

        if ($exitCode -ne 0 -or $final -ne $tag -or -not $commandOk -or $failed) {
            $sample = ($diagnosticLines | Where-Object { $_ -match 'command_execution|CreateProcess|windows sandbox|pwsh|powershell|cmd.exe|CODEX_DGSIS_SHELL_TOOL_OK|Reading additional input' } | Select-Object -First 20) -join "`n"
            Fail "Teste shell tool falhou. exit=$exitCode final='$final' commandOk=$commandOk failed=$failed command='$lastCommand' amostra=$sample"
        }

        Write-Ok "Shell tool executou comando real sem erro de sandbox"
    }
    finally {
        if (Test-Path -LiteralPath $jsonlPath) {
            Remove-Item -LiteralPath $jsonlPath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $lastPath) {
            Remove-Item -LiteralPath $lastPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-CodexAppServerModelListTest {
    param(
        [string]$CodexExe,
        [string]$CodexHome,
        [string]$DefaultModel
    )

    Write-Step "Validando seletor de modelos do Codex Desktop"

    $initId = "init-" + [Guid]::NewGuid().ToString("N")
    $requestId = "model-list-" + [Guid]::NewGuid().ToString("N")
    $failure = $null
    $modelCount = 0
    $process = $null
    $stderrTask = $null

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $CodexExe
        $psi.Arguments = "app-server --stdio"
        $psi.UseShellExecute = $false
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $psi.EnvironmentVariables[$CodexHomeEnvName] = $CodexHome
        $psi.EnvironmentVariables[$EnvKeyName] = $env:DGSIS_API_KEY

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        [void]$process.Start()
        $stderrTask = $process.StandardError.ReadToEndAsync()

        $messages = @(
            [pscustomobject]@{
                id     = $initId
                method = "initialize"
                params = [pscustomobject]@{
                    clientInfo   = [pscustomobject]@{ name = "codex-dgsis-installer"; title = "DGSIS Installer"; version = "1.0.0" }
                    capabilities = [pscustomobject]@{ experimentalApi = $true; requestAttestation = $false; optOutNotificationMethods = @() }
                }
            },
            [pscustomobject]@{ method = "initialized" },
            [pscustomobject]@{
                id     = $requestId
                method = "model/list"
                params = [pscustomobject]@{ includeHidden = $true; cursor = $null; limit = 100 }
            }
        )

        foreach ($message in $messages) {
            $process.StandardInput.WriteLine(($message | ConvertTo-Json -Depth 20 -Compress))
        }
        $process.StandardInput.Flush()

        $deadline = (Get-Date).AddSeconds(30)
        $readTask = $process.StandardOutput.ReadLineAsync()
        $modelResponse = $null

        while ((Get-Date) -lt $deadline) {
            if ($readTask.Wait(250)) {
                $line = $readTask.Result
                if ($null -eq $line) {
                    break
                }

                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    try {
                        $event = $line | ConvertFrom-Json
                        if (($event.PSObject.Properties.Name -contains "id") -and [string]$event.id -eq $requestId) {
                            $modelResponse = $event
                            break
                        }
                    }
                    catch {
                    }
                }

                $readTask = $process.StandardOutput.ReadLineAsync()
            }

            if ($process.HasExited) {
                break
            }
        }

        if ($null -eq $modelResponse) {
            $failure = "Codex Desktop app-server nao respondeu model/list em 30 segundos."
        }
        elseif ($modelResponse.PSObject.Properties.Name -contains "error") {
            $failure = "Codex Desktop app-server retornou erro em model/list: $($modelResponse.error | ConvertTo-Json -Depth 20 -Compress)"
        }
        elseif (($modelResponse.PSObject.Properties.Name -notcontains "result") -or $null -eq $modelResponse.result -or ($modelResponse.result.PSObject.Properties.Name -notcontains "data")) {
            $failure = "Codex Desktop app-server retornou model/list sem campo data."
        }
        else {
            $uiModels = @($modelResponse.result.data)
            $modelCount = $uiModels.Count
            $defaultMatches = @($uiModels | Where-Object { [string]$_.model -eq $DefaultModel })
            $badModels = @($uiModels | Where-Object { -not (Test-DgsisOpenAIModelId -ModelId ([string]$_.model)) })
            $hiddenDefault = @($defaultMatches | Where-Object { $_.hidden -ne $false })
            $missingDisplayName = @($defaultMatches | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.displayName) })

            if ($defaultMatches.Count -ne 1) {
                $failure = "Codex Desktop app-server nao retornou $DefaultModel em model/list. A UI cairia em Personalizado."
            }
            elseif ($badModels.Count -ne 0) {
                $badText = ($badModels | Select-Object -First 5 | ForEach-Object { [string]$_.model }) -join ", "
                $failure = "Codex Desktop app-server retornou modelos nao OpenAI/DGSIS: $badText"
            }
            elseif ($hiddenDefault.Count -ne 0) {
                $failure = "Codex Desktop app-server retornou $DefaultModel como hidden=true; a UI pode ocultar o modelo."
            }
            elseif ($missingDisplayName.Count -ne 0) {
                $failure = "Codex Desktop app-server retornou $DefaultModel sem displayName; a UI mostraria Personalizado."
            }
        }
    }
    catch {
        $failure = "Falha ao validar model/list do Codex Desktop: $($_.Exception.Message)"
    }
    finally {
        if ($null -ne $process -and -not $process.HasExited) {
            try {
                $process.Kill()
            }
            catch {
            }
        }
        if ($null -ne $process) {
            try {
                [void]$process.WaitForExit(5000)
            }
            catch {
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($failure)) {
        $stderr = ""
        if ($null -ne $stderrTask) {
            try {
                $stderr = $stderrTask.Result
            }
            catch {
            }
        }
        $stderrSample = ($stderr -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 6) -join " | "
        if (-not [string]::IsNullOrWhiteSpace($stderrSample)) {
            $failure = "$failure Stderr: $stderrSample"
        }
        Fail $failure
    }

    Write-Ok "Codex Desktop model/list retornou $modelCount modelos DGSIS para a UI"
}

function Test-CodexConfigStrict {
    param([string]$CodexExe)

    $strictOutput = & $CodexExe --strict-config --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        Fail "config.toml contem chave invalida. Saida: $($strictOutput | Out-String)"
    }

    Write-Ok "config.toml aceito em modo strict"
}

function Invoke-InstallerSelfTest {
    Write-Step "Executando autotestes do instalador Windows"

    if ((Get-WindowsCodexArchitecture -Override "X64") -ne "X64") {
        Fail "Autoteste falhou: override X64 nao retornou X64."
    }
    if ((Get-WindowsCodexArchitecture -Override "Arm64") -ne "Arm64") {
        Fail "Autoteste falhou: override Arm64 nao retornou Arm64."
    }
    if ((Get-AlternateCodexArchitecture -Architecture "X64") -ne "Arm64") {
        Fail "Autoteste falhou: alternativa de X64 deveria ser Arm64."
    }
    if ((Get-AlternateCodexArchitecture -Architecture "Arm64") -ne "X64") {
        Fail "Autoteste falhou: alternativa de Arm64 deveria ser X64."
    }
    if (-not (Test-ArchitectureInstallFailure -Message "The specified executable is not a valid application for this OS platform.")) {
        Fail "Autoteste falhou: erro de plataforma invalida nao foi reconhecido."
    }
    if (Test-ArchitectureInstallFailure -Message "Could not resolve latest release version.") {
        Fail "Autoteste falhou: erro de rede foi reconhecido como erro de arquitetura."
    }

    $pathSample = "C:\Program Files\WindowsApps\Microsoft.PowerShell_7.6.2.0_x64__8wekyb3d8bbwe;C:\Tools;C:\Users\Cliente\AppData\Local\Microsoft\WindowsApps"
    $pathClean = Remove-PathEntriesByRegex -PathValue $pathSample -Patterns @('^C:\\Program Files\\WindowsApps\\Microsoft\.PowerShell_')
    if ($pathClean -match 'Microsoft\.PowerShell_' -or $pathClean -notmatch 'C:\\Tools') {
        Fail "Autoteste falhou: limpeza de PATH PowerShell Store invalida."
    }

    $shimSource = Get-PwshShimSource
    if ($shimSource -notmatch 'WindowsPowerShell\\v1\.0\\powershell\.exe' -or $shimSource -notmatch 'QuoteArgument') {
        Fail "Autoteste falhou: fonte do shim pwsh.exe invalida."
    }

    $helperTemp = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-dgsis-helper-selftest-{0}" -f ([Guid]::NewGuid().ToString("N")))
    try {
        $helperBin = Join-Path $helperTemp "bin"
        $helperCurrent = Join-Path $helperTemp "current"
        $helperResources = Join-Path $helperCurrent "codex-resources"
        New-Item -ItemType Directory -Force -Path $helperBin, $helperResources | Out-Null
        Set-TextFileUtf8NoBom -Path (Join-Path $helperResources "codex-windows-sandbox-setup.exe") -Content "self-test"
        Sync-CodexWindowsHelperFiles -PreferredBinDir $helperBin -StandaloneCurrentDir $helperCurrent
        if (-not (Test-Path -LiteralPath (Join-Path $helperBin "codex-windows-sandbox-setup.exe") -PathType Leaf)) {
            Fail "Autoteste falhou: auxiliar de sandbox nao foi copiado para bin."
        }
    }
    finally {
        if (Test-Path -LiteralPath $helperTemp) {
            Remove-Item -LiteralPath $helperTemp -Recurse -Force -ErrorAction SilentlyContinue
        }
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
        'enabled = true',
        '',
        '[plugins."browser@openai-bundled"]',
        'enabled = false'
    )

    $sampleLines = Set-TopLevelKey $sampleLines "model" 'model = "cx/gpt-5.5"'
    $sampleLines = Set-TopLevelKey $sampleLines "model_provider" 'model_provider = "dgsis"'
    $sampleLines = Remove-Section $sampleLines "model_providers.dgsis"
    $sampleLines = Remove-Section $sampleLines 'plugins."cloudflare@openai-curated"'
    $sampleLines = Remove-Section $sampleLines 'plugins."browser@openai-bundled"'
    $sampleLines = Set-SectionKey $sampleLines "windows" "sandbox" 'sandbox = "elevated"'
    $sampleLines = @($sampleLines + "" + "[model_providers.dgsis]" + 'name = "DGSIS Gateway"' + "" + '[plugins."cloudflare@openai-curated"]' + 'enabled = false' + "" + '[plugins."browser@openai-bundled"]' + 'enabled = true')
    $sampleText = $sampleLines -join "`n"

    foreach ($pattern in @('(?m)^model = "cx/gpt-5\.5"$', '(?m)^model_provider = "dgsis"$', '(?m)^\[model_providers\.dgsis\]$', '(?m)^\[plugins\."cloudflare@openai-curated"\]$', '(?m)^\[plugins\."browser@openai-bundled"\]$')) {
        if (@([regex]::Matches($sampleText, $pattern)).Count -ne 1) {
            Fail "Autoteste falhou: padrao duplicado ou ausente: $pattern"
        }
    }
    if ($sampleText -notmatch '(?m)^sandbox = "elevated"$') {
        Fail "Autoteste falhou: sandbox elevated nao foi aplicado."
    }

    $sampleLines = Remove-Section $sampleLines "shell_environment_policy"
    $sampleLines = @($sampleLines + "" + "[shell_environment_policy]" + 'inherit = "all"' + 'set = { PATH = "C:\\Codex\\bin;C:\\Windows\\System32" }')
    $sampleText = $sampleLines -join "`n"
    if (@([regex]::Matches($sampleText, '(?m)^\[shell_environment_policy\]$')).Count -ne 1) {
        Fail "Autoteste falhou: shell_environment_policy duplicado ou ausente."
    }

    $catalog = Get-EmbeddedFallbackCatalogJson | ConvertFrom-Json
    if (@($catalog.models | Where-Object { $_.slug -eq "cx/gpt-5.5" }).Count -ne 1) {
        Fail "Autoteste falhou: catalogo fallback invalido."
    }

    $sampleModelsResponse = [pscustomobject]@{
        data = @(
            [pscustomobject]@{ id = "cx/gpt-5.5" },
            [pscustomobject]@{ id = "cx/gpt-5.4-mini" },
            [pscustomobject]@{ id = "cx/gpt-5.3-codex-high-review" },
            [pscustomobject]@{ id = "kr/claude-opus-4.8" },
            [pscustomobject]@{ id = "ag/gemini-3.1-pro-low" },
            [pscustomobject]@{ id = "cf/@cf/qwen/qwen2.5-coder-32b-instruct" }
        )
    }
    $sampleCatalogJson = New-DgsisModelCatalogJson -ModelsResponse $sampleModelsResponse -BundledCatalog $catalog -DefaultModel "cx/gpt-5.5"
    $sampleCatalog = $sampleCatalogJson | ConvertFrom-Json
    if (@($sampleCatalog.models).Count -ne 3) {
        Fail "Autoteste falhou: catalogo dinamico nao filtrou modelos OpenAI corretamente."
    }
    if (@($sampleCatalog.models | Where-Object { $_.slug -match '(?i)claude|gemini|qwen' }).Count -ne 0) {
        Fail "Autoteste falhou: catalogo dinamico deixou modelo nao OpenAI passar."
    }
    if (@($sampleCatalog.models | Where-Object { $_.slug -eq "cx/gpt-5.3-codex-high-review" }).Count -ne 1) {
        Fail "Autoteste falhou: catalogo dinamico removeu variante OpenAI valida."
    }

    $cacheTemp = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-dgsis-cache-selftest-{0}" -f ([Guid]::NewGuid().ToString("N")))
    try {
        New-Item -ItemType Directory -Force -Path $cacheTemp | Out-Null
        $cachePath = Join-Path $cacheTemp "models_cache.json"
        Write-CodexModelsCache -CatalogJson $sampleCatalogJson -ModelsCachePath $cachePath -BackupDir $cacheTemp -CodexVersion "codex-cli 0.137.0"
        $cache = Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json
        if (@($cache.models).Count -ne 3 -or $cache.client_version -ne "0.137.0") {
            Fail "Autoteste falhou: cache de modelos do Desktop invalido."
        }
        if (@($cache.models | Where-Object { $_.slug -match '(?i)claude|gemini|qwen' }).Count -ne 0) {
            Fail "Autoteste falhou: cache de modelos deixou modelo nao OpenAI passar."
        }
    }
    finally {
        if (Test-Path -LiteralPath $cacheTemp) {
            Remove-Item -LiteralPath $cacheTemp -Recurse -Force -ErrorAction SilentlyContinue
        }
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

    $nativeTemp = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-dgsis-native-selftest-{0}" -f ([Guid]::NewGuid().ToString("N")))
    try {
        New-Item -ItemType Directory -Force -Path $nativeTemp | Out-Null
        $stderrScript = Join-Path $nativeTemp "stderr-test.ps1"
        Set-TextFileUtf8NoBom -Path $stderrScript -Content "[Console]::Out.WriteLine('STDOUT_OK')`n[Console]::Error.WriteLine('STDERR_WARNING')`nexit 0"
        $powershellCommand = Get-Command powershell -ErrorAction SilentlyContinue
        if ($null -ne $powershellCommand) {
            $nativeResult = Invoke-NativeProcessCapture -FilePath $powershellCommand.Source -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $stderrScript)
            if ($nativeResult.ExitCode -ne 0 -or @($nativeResult.Stdout) -notcontains "STDOUT_OK" -or @($nativeResult.Stderr) -notcontains "STDERR_WARNING") {
                Fail "Autoteste falhou: captura de stderr nativo invalida."
            }
        }
    }
    finally {
        if (Test-Path -LiteralPath $nativeTemp) {
            Remove-Item -LiteralPath $nativeTemp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $desktopTemp = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-dgsis-desktop-selftest-{0}" -f ([Guid]::NewGuid().ToString("N")))
    try {
        $desktopWorkspace = Join-Path $desktopTemp "workspace com espaco"
        New-Item -ItemType Directory -Force -Path $desktopWorkspace | Out-Null
        $fakeCodex = Join-Path $desktopTemp "codex.cmd"
        $desktopResult = Join-Path $desktopTemp "desktop-result.txt"
        $fakeCodexScript = @(
            '@echo off',
            'if not "%~1"=="app" exit /b 11',
            ('if not "%~2"=="{0}" exit /b 12' -f $desktopWorkspace),
            ('if not "%CODEX_HOME%"=="{0}" exit /b 13' -f $desktopTemp),
            ('> "{0}" echo DESKTOP_SELFTEST_OK' -f $desktopResult),
            'exit /b 0'
        ) -join "`r`n"
        Set-TextFileUtf8NoBom -Path $fakeCodex -Content $fakeCodexScript
        Install-CodexDesktopApp -CodexExe $fakeCodex -CodexHome $desktopTemp -WorkspacePath $desktopWorkspace
        if (-not (Test-Path -LiteralPath $desktopResult) -or ((Get-Content -LiteralPath $desktopResult -Raw).Trim() -ne "DESKTOP_SELFTEST_OK")) {
            Fail "Autoteste falhou: simulacao do Codex Desktop nao confirmou argumentos e CODEX_HOME."
        }
    }
    finally {
        if (Test-Path -LiteralPath $desktopTemp) {
            Remove-Item -LiteralPath $desktopTemp -Recurse -Force -ErrorAction SilentlyContinue
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

Install-ClientDependencies

Write-Step "Instalando ou atualizando o Codex CLI standalone"
$codexArchitecture = Get-WindowsCodexArchitecture -Override $ArchitectureOverride
Write-Ok "Arquitetura detectada para Codex: Windows $codexArchitecture"

$oldNonInteractive = $env:CODEX_NON_INTERACTIVE
$installerSucceeded = $false
$lastInstallerError = $null
try {
    $env:CODEX_NON_INTERACTIVE = "1"
    $installerContent = Get-CodexInstallerContent
    $attemptArchitectures = @($codexArchitecture)
    if ([string]::IsNullOrWhiteSpace($ArchitectureOverride)) {
        $attemptArchitectures += (Get-AlternateCodexArchitecture -Architecture $codexArchitecture)
    }

    foreach ($attemptArchitecture in $attemptArchitectures) {
        try {
            if ($attemptArchitecture -ne $codexArchitecture) {
                Write-Step "Tentando arquitetura alternativa: Windows $attemptArchitecture"
            }

            [void](Invoke-CodexOfficialInstaller -Architecture $attemptArchitecture -InstallerContent $installerContent)
            $codexArchitecture = $attemptArchitecture
            $installerSucceeded = $true
            break
        }
        catch {
            $lastInstallerError = $_
            $lastInstallerMessage = $_.Exception.Message
            if ($attemptArchitecture -eq $attemptArchitectures[-1] -or -not (Test-ArchitectureInstallFailure -Message $lastInstallerMessage)) {
                Fail "O instalador oficial do Codex falhou para Windows $attemptArchitecture. $lastInstallerMessage"
            }

            Write-Host "Aviso: o binario Windows $attemptArchitecture nao executou nesta maquina; tentando a outra arquitetura suportada." -ForegroundColor Yellow
        }
    }
}
finally {
    $env:CODEX_NON_INTERACTIVE = $oldNonInteractive
}

if (-not $installerSucceeded) {
    Fail "Nao foi possivel instalar o Codex CLI. Ultimo erro: $lastInstallerError"
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
$newUserPath = Prepend-PathEntry -PathValue $currentUserPath -Entry $preferredBinDir
if ($newUserPath -cne $currentUserPath) {
    [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
}

$env:Path = Prepend-PathEntry -PathValue $env:Path -Entry $preferredBinDir

Sync-CodexWindowsHelperFiles -PreferredBinDir $preferredBinDir
Install-PwshShim -PreferredBinDir $preferredBinDir
Set-CodexPowerShellProfilePathFix -PreferredBinDir $preferredBinDir
Install-CodexVSCodeExtension

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
$modelsCachePath = Join-Path $codexHome "models_cache.json"
$configPath = Join-Path $codexHome "config.toml"

[Environment]::SetEnvironmentVariable($CodexHomeEnvName, $codexHome, "User")
$env:CODEX_HOME = $codexHome
Write-Ok "$CodexHomeEnvName definido para $codexHome"

New-Item -ItemType Directory -Force -Path $catalogDir | Out-Null
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

Write-Step "Gerando catalogo local DGSIS para o seletor de modelos"
$catalogJson = $null
try {
    $bundledJson = & $preferredCodexExe debug models --bundled
    $bundledCatalog = $bundledJson | ConvertFrom-Json
    $catalogJson = New-DgsisModelCatalogJson -ModelsResponse $models -BundledCatalog $bundledCatalog -DefaultModel $DgsisModel
}
catch {
    Write-Host "Aviso: nao foi possivel transformar o catalogo embutido; usando fallback DGSIS. $($_.Exception.Message)" -ForegroundColor Yellow
    $fallbackCatalog = Get-FallbackCatalogJson | ConvertFrom-Json
    $catalogJson = New-DgsisModelCatalogJson -ModelsResponse $models -BundledCatalog $fallbackCatalog -DefaultModel $DgsisModel
}

if ([string]::IsNullOrWhiteSpace($catalogJson)) {
    Fail "Nao foi possivel gerar nem carregar o catalogo DGSIS."
}

$catalogCheck = $catalogJson | ConvertFrom-Json
if (@($catalogCheck.models | Where-Object { $_.slug -eq $DgsisModel }).Count -ne 1) {
    Fail "Catalogo DGSIS invalido: modelo $DgsisModel ausente."
}
if (@($catalogCheck.models | Where-Object { $_.slug -match '(?i)claude|anthropic|gemini|deepseek|qwen|llama|mistral|kimi|glm|minimax|grok|oss' }).Count -ne 0) {
    Fail "Catalogo DGSIS invalido: contem modelos que nao sao OpenAI."
}
Write-Ok "Catalogo DGSIS OpenAI com $(@($catalogCheck.models).Count) modelos"

Set-TextFileUtf8NoBom -Path $catalogPath -Content $catalogJson
Write-Ok "Catalogo criado em $catalogPath"

Write-CodexModelsCache -CatalogJson $catalogJson -ModelsCachePath $modelsCachePath -BackupDir $backupDir -CodexVersion $codexVersion
Write-Ok "Cache de modelos do Desktop atualizado em $modelsCachePath"

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
$lines = Remove-Section $lines 'plugins."browser@openai-bundled"'
$lines = Remove-Section $lines 'plugins."chrome@openai-bundled"'
$lines = Remove-Section $lines 'plugins."computer-use@openai-bundled"'
$lines = Remove-Section $lines "shell_environment_policy"
$lines = Set-SectionKey $lines "windows" "sandbox" 'sandbox = "elevated"'

$stablePath = Get-StableCodexPathValue -PreferredBinDir $preferredBinDir
$stablePathToml = ConvertTo-TomlString $stablePath

$lines = @($lines + "" + "[shell_environment_policy]" +
    'inherit = "all"' +
    "set = { PATH = $stablePathToml }" +
    "" +
    "[model_providers.dgsis]" +
    'name = "DGSIS Gateway"' +
    'base_url = "https://gtw.dgsis.com.br/v1"' +
    'wire_api = "responses"' +
    'env_key = "DGSIS_API_KEY"' +
    "" +
    '[plugins."cloudflare@openai-curated"]' +
    'enabled = false' +
    "" +
    '[plugins."browser@openai-bundled"]' +
    'enabled = true' +
    "" +
    '[plugins."chrome@openai-bundled"]' +
    'enabled = true' +
    "" +
    '[plugins."computer-use@openai-bundled"]' +
    'enabled = true')

Set-LinesFileUtf8NoBom -Path $configPath -Lines $lines
Write-Ok "Config.toml atualizado em $configPath"

Test-CodexConfigStrict -CodexExe $preferredCodexExe

Write-Step "Validando configuracao do catalogo"
$debugModels = & $preferredCodexExe debug models
if ($LASTEXITCODE -ne 0 -or $debugModels -notmatch '"slug"\s*:\s*"cx/gpt-5\.5"') {
    Fail "O Codex nao carregou o catalogo DGSIS corretamente."
}
Write-Ok "Catalogo DGSIS carregado pelo Codex"

Invoke-CodexAppServerModelListTest -CodexExe $preferredCodexExe -CodexHome $codexHome -DefaultModel $DgsisModel

if ($SkipLiveTests) {
    Write-Host "Pulando testes vivos por -SkipLiveTests." -ForegroundColor Yellow
}
else {
    Invoke-CodexDoctorCheck -CodexExe $preferredCodexExe

    Write-Step "Executando teste final do Codex CLI com o gateway DGSIS"
    Invoke-CodexExecTest -CodexExe $preferredCodexExe
    Write-Ok "Codex respondeu com model: cx/gpt-5.5"
    Invoke-CodexShellToolTest -CodexExe $preferredCodexExe
}

Install-CodexDesktopApp -CodexExe $preferredCodexExe -CodexHome $codexHome -WorkspacePath $env:USERPROFILE

Write-Host ""
Write-Host "Instalacao concluida." -ForegroundColor Green
Write-Host "Feche e abra uma nova janela do PowerShell e execute: codex"
Write-Host "No topo do Codex deve aparecer: model: cx/gpt-5.5"
Write-Host "No VS Code, abra a barra lateral Codex/ChatGPT; o token DGSIS ja esta configurado no ambiente do usuario."
