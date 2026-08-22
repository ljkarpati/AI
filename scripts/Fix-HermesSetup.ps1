<#
.SYNOPSIS
    One-shot remediation for a Hermes Agent install that was started from an
    extracted zip instead of the installer.

.DESCRIPTION
    Runs the whole recovery in order and stops at the first step that genuinely
    fails:

      1. Quarantine the hand-edited Downloads tree (moved, never deleted)
      2. Run the official installer if `hermes` is not already on PATH
      3. Refresh PATH in this session so `hermes` is callable immediately
      4. Install the [web] extra so the dashboard has an HTTP layer
      5. Start llama-server at 65536 context if it is not already serving 64k+
      6. Persist CUSTOM_BASE_URL / CUSTOM_API_KEY for the local endpoint
      7. hermes doctor
      8. hermes dashboard on 127.0.0.1:9119

    Every step is idempotent: re-running after a partial failure is safe.

.PARAMETER ModelPath
    GGUF to serve. Required unless llama-server is already running with a
    context of at least 64,000, or -SkipLlama is passed.

.PARAMETER GpuLayers
    Layers offloaded to GPU. Qwen3-8B has 36. The default of 32 leaves four on
    CPU to make room for the KV cache on an 8 GB card. Lower it if the server
    reports an allocation failure.

.EXAMPLE
    .\Fix-HermesSetup.ps1 -ModelPath C:\models\qwen3-8b-instruct-q4_k_m.gguf
    .\Fix-HermesSetup.ps1 -ModelPath ... -DryRun
#>
[CmdletBinding()]
param(
    [string] $ModelPath,

    [string] $StaleTree = "$env:USERPROFILE\Downloads\hermes-agent-2026.8.19",
    [string] $HermesHome = "$env:USERPROFILE\.hermes",

    [string] $LlamaExe = 'llama-server',
    [string] $LlamaHost = '127.0.0.1',
    [int]    $LlamaPort = 8080,
    [int]    $ContextSize = 65536,
    [ValidateSet('f16', 'q8_0', 'q5_1', 'q4_0')]
    [string] $CacheType = 'q4_0',
    [int]    $GpuLayers = 32,

    [int]    $DashboardPort = 9119,

    [switch] $SkipInstall,
    [switch] $SkipLlama,
    [switch] $NoDashboard,
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'
$LlamaUrl = "http://${LlamaHost}:${LlamaPort}"
$stepNo = 0

function Step([string] $Name) {
    $script:stepNo++
    Write-Host ''
    Write-Host ("[{0}] {1}" -f $script:stepNo, $Name) -ForegroundColor Cyan
    Write-Host ('    ' + ('-' * [Math]::Min(64, $Name.Length)))
}
function Info([string] $M) { Write-Host "    $M" }
function Good([string] $M) { Write-Host "    $M" -ForegroundColor Green }
function Warn([string] $M) { Write-Host "    $M" -ForegroundColor Yellow }
function Would([string] $M) { Write-Host "    [dry-run] $M" -ForegroundColor Magenta }

function Get-LlamaContext {
    <# Returns the served context length, or $null if nothing answers. #>
    try {
        $p = Invoke-RestMethod -Uri "$LlamaUrl/props" -TimeoutSec 4 -ErrorAction Stop
    } catch { return $null }
    foreach ($c in @($p.default_generation_settings.n_ctx,
                     $p.default_generation_settings.n_ctx_per_seq,
                     $p.n_ctx)) {
        if ($null -ne $c) { return [int] $c }
    }
    return 0   # answered, but did not report a context
}

function Update-SessionPath {
    <# The installer edits the user PATH; this process still has the old copy. #>
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

Write-Host ''
Write-Host '=== Hermes Agent setup remediation ===' -ForegroundColor White
if ($DryRun) { Warn 'DRY RUN -- nothing will be changed.' }

# 1 ---------------------------------------------------------------------------
Step 'Quarantine the hand-edited source tree'
if (-not (Test-Path -LiteralPath $StaleTree)) {
    Good 'Nothing to quarantine.'
} else {
    $dest = "$StaleTree.broken-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
    Info "This tree contains a stubbed agent_init.py and must not be run from."
    if ($DryRun) {
        Would "Move-Item '$StaleTree' -> '$dest'"
    } else {
        Move-Item -LiteralPath $StaleTree -Destination $dest -Force
        Good "Moved aside to: $dest"
        Info 'Nothing is deleted. Delete it yourself once the new install works.'
    }
}

# 2 ---------------------------------------------------------------------------
Step 'Install Hermes Agent'
Update-SessionPath
$hermes = Get-Command hermes -ErrorAction SilentlyContinue
if ($hermes) {
    Good "Already installed: $($hermes.Source)"
} elseif ($SkipInstall) {
    throw 'hermes is not on PATH and -SkipInstall was passed. Nothing to do.'
} elseif ($DryRun) {
    Would 'iex (irm https://hermes-agent.nousresearch.com/install.ps1)'
} else {
    Info 'Downloading and running the official installer. This provisions uv,'
    Info 'Python 3.11, Node.js 22, ripgrep and ffmpeg, and may take several minutes.'
    Invoke-Expression (Invoke-RestMethod -Uri 'https://hermes-agent.nousresearch.com/install.ps1')

    # 3 -----------------------------------------------------------------------
    Update-SessionPath
    $hermes = Get-Command hermes -ErrorAction SilentlyContinue
    if (-not $hermes) {
        throw @'
The installer ran but `hermes` is still not on PATH.

Close this window, open a new PowerShell, and re-run this script -- a fresh
shell picks up the PATH change. If it is still missing, the installer did not
complete; re-run it on its own and read its output.
'@
    }
    Good "Installed: $($hermes.Source)"
}

$installDir = Join-Path $HermesHome 'hermes-agent'

# 4 ---------------------------------------------------------------------------
Step 'Install the [web] extra (dashboard HTTP layer)'
if (-not (Test-Path -LiteralPath $installDir)) {
    Warn "Install directory not found at $installDir -- skipping."
    Warn 'If the dashboard fails to start, install the extra there manually.'
} elseif ($DryRun) {
    Would "cd '$installDir'; uv pip install -e '.[web]'"
} else {
    Push-Location $installDir
    try {
        # pty is POSIX-only, so ask for [web] alone on Windows.
        & uv pip install -e ".[web]"
        if ($LASTEXITCODE -ne 0) { throw "uv pip install exited with $LASTEXITCODE" }
        Good 'fastapi + uvicorn installed.'
    } finally { Pop-Location }
}

# 5 ---------------------------------------------------------------------------
Step 'Backend: llama-server with a >=64,000 token context'
$nctx = Get-LlamaContext
if ($SkipLlama) {
    Warn '-SkipLlama passed; not touching the backend.'
} elseif ($null -ne $nctx -and $nctx -ge 64000) {
    Good "Already serving at $LlamaUrl with n_ctx = $nctx."
} else {
    if ($null -ne $nctx) {
        Warn "A server is answering at $LlamaUrl but n_ctx = $nctx, below the"
        Warn '64,000 minimum. Stop it and re-run, or restart it yourself with'
        Warn 'the flags below.'
    }
    if (-not $ModelPath) {
        throw @"
No usable backend, and -ModelPath was not given.

Pass the GGUF to serve:
    .\Fix-HermesSetup.ps1 -ModelPath C:\models\qwen3-8b-instruct-q4_k_m.gguf
"@
    }
    if (-not (Test-Path -LiteralPath $ModelPath)) { throw "Model not found: $ModelPath" }

    $llamaArgs = @(
        '--model', $ModelPath
        '--ctx-size', $ContextSize
        '--host', $LlamaHost
        '--port', $LlamaPort
        '--n-gpu-layers', $GpuLayers
        '--cache-type-k', $CacheType
        '--cache-type-v', $CacheType
    )
    # A quantised V cache requires flash attention.
    if ($CacheType -ne 'f16') { $llamaArgs += '--flash-attn' }

    Info "$LlamaExe $($llamaArgs -join ' ')"
    if ($DryRun) {
        Would 'start llama-server with the above'
    } else {
        if ($null -ne $nctx) { throw 'Port is occupied by an under-provisioned server. Stop it first.' }
        $proc = Start-Process -FilePath $LlamaExe -ArgumentList $llamaArgs -PassThru -NoNewWindow
        Info 'Waiting for the server to allocate its KV cache (up to 3 minutes)...'
        $deadline = (Get-Date).AddSeconds(180)
        while ((Get-Date) -lt $deadline) {
            if ($proc.HasExited) {
                throw @"
llama-server exited with code $($proc.ExitCode) before serving.

The usual cause is running out of VRAM. At $ContextSize tokens with a
$CacheType KV cache this needs roughly 7.5 GB alongside an 8B Q4_K_M model.
Retry with fewer GPU layers, e.g. -GpuLayers 24.
"@
            }
            $nctx = Get-LlamaContext
            if ($null -ne $nctx) { break }
            Start-Sleep -Seconds 3
        }
        if ($nctx -eq 0) {
            Warn 'Server is up but this build does not report n_ctx; cannot verify'
            Warn "the 64,000 floor automatically. Confirm it served --ctx-size $ContextSize."
            $nctx = $ContextSize
        }
        if ($null -eq $nctx -or $nctx -lt 64000) {
            throw "Server came up reporting n_ctx = $nctx, still below 64,000. Check its output."
        }
        Good "Serving at $LlamaUrl with n_ctx = $nctx (PID $($proc.Id))."
    }
}

# 6 ---------------------------------------------------------------------------
Step 'Point Hermes at the local endpoint'
# Note the full four-octet address and the /v1 suffix -- "http://127.0.0" is
# not a valid IPv4 address and was the cause of every failed request.
$baseUrl = "http://${LlamaHost}:${LlamaPort}/v1"
if ($DryRun) {
    Would "set CUSTOM_BASE_URL=$baseUrl (user scope)"
    Would 'set CUSTOM_API_KEY=local (user scope)'
} else {
    [Environment]::SetEnvironmentVariable('CUSTOM_BASE_URL', $baseUrl, 'User')
    [Environment]::SetEnvironmentVariable('CUSTOM_API_KEY', 'local', 'User')
    $env:CUSTOM_BASE_URL = $baseUrl
    $env:CUSTOM_API_KEY = 'local'
    Good "CUSTOM_BASE_URL = $baseUrl"
    Good 'CUSTOM_API_KEY  = local'
}
Info ''
Info 'Then select the provider interactively -- this is the supported path and'
Info 'writes to ~/.hermes/config.yaml correctly:'
Info '    hermes model        # choose "Custom Endpoint"'

# 7 ---------------------------------------------------------------------------
Step 'hermes doctor'
if ($DryRun) {
    Would 'hermes doctor'
} else {
    & hermes doctor
    if ($LASTEXITCODE -ne 0) {
        throw "hermes doctor exited with $LASTEXITCODE. Resolve what it reports before starting the dashboard."
    }
    Good 'doctor completed cleanly.'
}

# 8 ---------------------------------------------------------------------------
Step 'Dashboard'
if ($DashboardPort -eq $LlamaPort) { throw "Dashboard port $DashboardPort collides with llama-server." }
if ($NoDashboard -or $DryRun) {
    Info "Start it with:  hermes dashboard --port $DashboardPort"
} else {
    Write-Host ''
    Good "Opening http://127.0.0.1:$DashboardPort"
    & hermes dashboard --port $DashboardPort
}
