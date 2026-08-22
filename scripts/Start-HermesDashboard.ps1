<#
.SYNOPSIS
    Verify a Hermes Agent install end to end, then start the web dashboard.

.DESCRIPTION
    Walks the supported path in order and stops at the first thing that is
    actually wrong, instead of failing deep inside the agent with an
    AttributeError. Checks, in order:

      1. the `hermes` CLI is on PATH (i.e. the installer was actually run)
      2. the managed install exists at ~/.hermes/hermes-agent
      3. no stray hand-edited source tree is shadowing it
      4. the [web] extra is installed (FastAPI/Uvicorn)
      5. llama-server is up and its context meets the documented 64k floor
      6. the configured base_url is a valid address
      7. `hermes doctor` passes

    Then runs `hermes dashboard` on 127.0.0.1:9119.

.EXAMPLE
    .\Start-HermesDashboard.ps1 -CheckOnly
    .\Start-HermesDashboard.ps1
#>
[CmdletBinding()]
param(
    [int]    $DashboardPort = 9119,
    [string] $LlamaUrl = 'http://127.0.0.1:8080',
    [string] $HermesHome = "$env:USERPROFILE\.hermes",

    # Hand-extracted tree to warn about. Set to '' to skip that check.
    [string] $StaleTree = "$env:USERPROFILE\Downloads\hermes-agent-2026.8.19",

    [switch] $CheckOnly,
    [switch] $NoOpen
)

$ErrorActionPreference = 'Stop'
$script:Failed = $false

function Step([string] $Name) {
    Write-Host ''
    Write-Host "-- $Name" -ForegroundColor Cyan
}
function Pass([string] $Msg) { Write-Host "   [ok]   $Msg" -ForegroundColor Green }
function Warn([string] $Msg) { Write-Host "   [warn] $Msg" -ForegroundColor Yellow }
function Fail([string] $Msg) {
    Write-Host "   [FAIL] $Msg" -ForegroundColor Red
    $script:Failed = $true
}

# 1 -- CLI present -------------------------------------------------------------
Step 'Hermes CLI'
$hermes = Get-Command hermes -ErrorAction SilentlyContinue
if ($hermes) {
    Pass "found at $($hermes.Source)"
} else {
    Fail @'
`hermes` is not on PATH -- the installer has not been run.

    iex (irm https://hermes-agent.nousresearch.com/install.ps1)

Then open a new PowerShell window so PATH is refreshed.
Running python run_agent.py out of an extracted zip is not a supported
install and is the root cause of the nemo_relay and AttributeError failures.
'@
}

# 2 -- managed install ---------------------------------------------------------
Step 'Managed install'
$installDir = Join-Path $HermesHome 'hermes-agent'
if (Test-Path -LiteralPath $installDir) {
    Pass $installDir
} else {
    Fail "not found at $installDir -- re-run the installer."
}

$configPath = Join-Path $HermesHome 'config.yaml'
if (Test-Path -LiteralPath $configPath) {
    Pass "config: $configPath"
} else {
    Warn "no config yet at $configPath -- run `hermes model` and pick 'Custom Endpoint'."
}

# 3 -- stale hand-edited tree --------------------------------------------------
if ($StaleTree) {
    Step 'Stale source tree'
    if (Test-Path -LiteralPath $StaleTree) {
        Warn @"
An extracted copy still exists at:
     $StaleTree
   It contains hand-edited files (a stubbed agent_init.py). Nothing should be
   run from it. Move or delete it so you cannot start the wrong tree by
   accident.
"@
    } else {
        Pass 'no leftover extracted tree'
    }
}

# 4 -- web extra ---------------------------------------------------------------
Step 'Dashboard dependencies'
if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Fail 'uv is not on PATH. The installer provisions it; if it is missing, the install did not complete.'
} elseif (Test-Path -LiteralPath $installDir) {
    Push-Location $installDir
    try {
        $probe = & uv run python -c "import fastapi, uvicorn; print('ok')" 2>&1
        if ($LASTEXITCODE -eq 0 -and $probe -match 'ok') {
            Pass 'fastapi + uvicorn present'
        } else {
            Fail @"
The [web] extra is not installed; the dashboard cannot start. Run:

     cd `"$installDir`"
     uv pip install -e `".[web]`"

   Use `".[web,pty]`" on POSIX for the embedded terminal; pty is not
   available on Windows.
"@
        }
    } finally { Pop-Location }
} else {
    Warn 'skipped -- install directory missing'
}

# 5 -- backend context window --------------------------------------------------
Step 'llama-server context'
try {
    $props = Invoke-RestMethod -Uri "$LlamaUrl/props" -TimeoutSec 5 -ErrorAction Stop
    $nctx = $null
    foreach ($c in @($props.default_generation_settings.n_ctx,
                     $props.default_generation_settings.n_ctx_per_seq,
                     $props.n_ctx)) {
        if ($null -ne $c) { $nctx = [int] $c; break }
    }
    if ($null -eq $nctx) {
        Warn "server is up at $LlamaUrl but did not report n_ctx"
    } elseif ($nctx -lt 64000) {
        Fail @"
n_ctx = $nctx, below the documented 64,000 minimum.
   Restart llama-server with a larger window. On 8 GB this needs a quantised
   KV cache:

     llama-server --model <model.gguf> --ctx-size 65536 --flash-attn ``
       --cache-type-k q4_0 --cache-type-v q4_0 --n-gpu-layers 32 ``
       --host 127.0.0.1 --port 8080

   See docs/hermes-context-window.md for the VRAM arithmetic.
"@
    } else {
        Pass "n_ctx = $nctx (meets the 64,000 floor)"
    }
} catch {
    Fail "no response from $LlamaUrl/props -- llama-server is not running there."
}

# 6 -- configured endpoint sanity ---------------------------------------------
Step 'Configured base_url'
$baseUrl = $env:CUSTOM_BASE_URL
if (-not $baseUrl -and (Test-Path -LiteralPath $configPath)) {
    $m = Select-String -Path $configPath -Pattern 'base_url\s*:\s*["'']?([^"''\s]+)' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($m) { $baseUrl = $m.Matches[0].Groups[1].Value }
}
if (-not $baseUrl) {
    Warn 'no CUSTOM_BASE_URL set and none found in config -- run `hermes model`.'
} else {
    $hostPart = ($baseUrl -replace '^https?://', '').Split('/')[0]
    $bare = if ($hostPart -match ':') { $hostPart.Substring(0, $hostPart.LastIndexOf(':')) } else { $hostPart }
    if ($bare -match '^[\d.]+$' -and ($bare.Split('.').Count -ne 4)) {
        Fail "base_url '$baseUrl' -- '$bare' is not a valid IPv4 address. Use http://127.0.0.1:8080/v1"
    } elseif ($baseUrl -notmatch '/v\d+/?$') {
        Warn "base_url '$baseUrl' does not end in /v1; llama-server serves OpenAI routes under /v1."
    } else {
        Pass $baseUrl
    }
}

# 7 -- hermes doctor -----------------------------------------------------------
Step 'hermes doctor'
if ($hermes) {
    & hermes doctor
    if ($LASTEXITCODE -eq 0) { Pass 'doctor completed cleanly' }
    else { Fail "doctor exited with code $LASTEXITCODE -- resolve what it reports before continuing." }
} else {
    Warn 'skipped -- CLI missing'
}

# --- Result -------------------------------------------------------------------
Write-Host ''
if ($script:Failed) {
    Write-Host '== Not ready. Fix the [FAIL] items above. ==' -ForegroundColor Red
    exit 1
}
Write-Host '== All checks passed. ==' -ForegroundColor Green

if ($CheckOnly) { exit 0 }

if ($DashboardPort -eq 8080) {
    throw 'Port 8080 is llama-server. Pick a different -DashboardPort (default 9119).'
}

Write-Host ''
Write-Host "Starting dashboard on http://127.0.0.1:$DashboardPort ..." -ForegroundColor Cyan
$dashArgs = @('dashboard', '--port', $DashboardPort)
if ($NoOpen) { $dashArgs += '--no-open' }
& hermes @dashArgs
