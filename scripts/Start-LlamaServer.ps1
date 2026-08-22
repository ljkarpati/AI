<#
.SYNOPSIS
    Launch llama-server with a context window large enough to satisfy Hermes
    Agent's floor, and verify what the server actually reports back.

.DESCRIPTION
    The 64k floor and the 40,960-token server allocation are the same problem
    seen from two ends. Raising the server's context is the fix that leaves the
    framework untouched; patching the framework is the fallback.

    On 8 GB of VRAM an 8B model at 64k context does not fit with an f16 KV
    cache -- the cache alone is ~9.7 GB. It does fit once the KV cache is
    quantised -- and even then only barely. With an 8B model at Q4_K_M
    (~5 GB of weights), 64k context costs roughly:

        f16  KV cache : 9.00 GB  -> 14.00 GB total, hopeless
        q8_0 KV cache : 4.78 GB  ->  9.78 GB total, still over
        q4_0 KV cache : 2.53 GB  ->  7.53 GB total, borderline

    Only the q4_0 row fits at all, and it leaves nothing for the compute
    buffer, so expect to offload a few layers to system RAM via -GpuLayers.
    That is why this script defaults to q4_0 despite the quality cost.

    If that trade is not worth it, the pragmatic alternative is to keep the
    server at 40,960 tokens and lower Hermes' floor instead -- see
    docs/hermes-context-window.md. The estimate printed before launch tells
    you whether your combination is plausible before you wait for a load that
    would OOM.

.PARAMETER CacheType
    KV cache precision. f16 is lossless and largest; q8_0 is a good default;
    q4_0 is smallest and the most lossy. Anything other than f16 needs flash
    attention, which this script enables automatically.

.EXAMPLE
    .\Start-LlamaServer.ps1 -ModelPath C:\models\qwen3-8b-instruct-q4_k_m.gguf
    .\Start-LlamaServer.ps1 -ModelPath ... -ContextSize 65536 -CacheType q4_0
    .\Start-LlamaServer.ps1 -ProbeOnly
#>
[CmdletBinding()]
param(
    [string] $ModelPath,
    [int]    $ContextSize = 65536,
    [ValidateSet('f16', 'q8_0', 'q5_1', 'q4_0')]
    [string] $CacheType = 'q4_0',

    # Layers to offload to GPU. 999 = all. Lower this to trade speed for VRAM.
    [int]    $GpuLayers = 999,

    [string] $ListenHost = '127.0.0.1',
    [int]    $Port = 8080,
    [string] $ServerExe = 'llama-server',

    # Model geometry, used only for the VRAM estimate. Defaults are Qwen3-8B.
    [int] $NumLayers = 36,
    [int] $NumKvHeads = 8,
    [int] $HeadDim = 128,

    # Approximate on-disk size of the weights, in GB. Used only in the estimate.
    [double] $WeightsGB = 5.0,

    [switch] $ProbeOnly,
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'
$BaseUrl = "http://${ListenHost}:${Port}"

function Get-ServerProps {
    param([string] $Url, [int] $TimeoutSec = 5)
    try {
        return Invoke-RestMethod -Uri "$Url/props" -TimeoutSec $TimeoutSec -ErrorAction Stop
    } catch {
        return $null
    }
}

function Show-Probe {
    param([string] $Url)
    Write-Host ''
    Write-Host "Probing $Url ..." -ForegroundColor Cyan
    $props = Get-ServerProps -Url $Url
    if (-not $props) {
        Write-Host '  No response. Server is not up on this address.' -ForegroundColor Red
        return $false
    }

    # n_ctx has moved around between llama.cpp builds; check both spellings.
    $nctx = $null
    foreach ($candidate in @(
            $props.default_generation_settings.n_ctx,
            $props.n_ctx,
            $props.default_generation_settings.n_ctx_per_seq)) {
        if ($null -ne $candidate) { $nctx = [int] $candidate; break }
    }

    $modelName = $props.model_path
    if (-not $modelName) { $modelName = $props.model }
    if (-not $modelName) { $modelName = '(not reported)' }
    Write-Host "  model      : $modelName"
    if ($null -ne $nctx) {
        Write-Host "  n_ctx      : $nctx"
        if ($nctx -lt 64000) {
            Write-Host "  VERDICT    : below Hermes' 64000 floor -- it will still refuse." -ForegroundColor Yellow
            Write-Host "               Raise -ContextSize, or lower the floor with" -ForegroundColor Yellow
            Write-Host "               scripts/hermes_ctx_patch.py." -ForegroundColor Yellow
        } else {
            Write-Host "  VERDICT    : at or above the 64000 floor. No patch needed." -ForegroundColor Green
        }
    } else {
        Write-Host '  n_ctx      : not reported by this build' -ForegroundColor Yellow
    }
    Write-Host ''
    Write-Host "  OpenAI-compatible base_url for Hermes: $Url/v1" -ForegroundColor Green
    return $true
}

if ($ProbeOnly) {
    $ok = Show-Probe -Url $BaseUrl
    exit ($(if ($ok) { 0 } else { 1 }))
}

if (-not $ModelPath) { throw 'Provide -ModelPath (or use -ProbeOnly).' }
if (-not (Test-Path -LiteralPath $ModelPath)) { throw "Model not found: $ModelPath" }

# --- VRAM estimate ------------------------------------------------------------
# KV cache = 2 (K and V) * layers * kv_heads * head_dim * bytes_per_element,
# per token. Quantised caches also carry per-block scales; the multipliers
# below fold those in and are approximate, not exact.
$bytesPerElement = switch ($CacheType) {
    'f16'  { 2.0    }
    'q8_0' { 1.0625 }
    'q5_1' { 0.75   }
    'q4_0' { 0.5625 }
}
$kvBytesPerToken = 2 * $NumLayers * $NumKvHeads * $HeadDim * $bytesPerElement
$kvGB = ($kvBytesPerToken * $ContextSize) / 1GB
$totalGB = $kvGB + $WeightsGB

Write-Host ''
Write-Host '== VRAM estimate ============================================' -ForegroundColor Cyan
Write-Host ("  context          : {0:N0} tokens" -f $ContextSize)
Write-Host ("  KV cache type    : {0}" -f $CacheType)
Write-Host ("  KV per token     : {0:N1} KiB" -f ($kvBytesPerToken / 1KB))
Write-Host ("  KV cache total   : {0:N2} GB" -f $kvGB)
Write-Host ("  weights (approx) : {0:N2} GB" -f $WeightsGB)
Write-Host ("  sum              : {0:N2} GB" -f $totalGB) -ForegroundColor $(
    if ($totalGB -gt 7.5) { 'Red' } elseif ($totalGB -gt 6.5) { 'Yellow' } else { 'Green' })
Write-Host '  (excludes the compute buffer and CUDA context, roughly 0.5-1 GB)' -ForegroundColor DarkGray

if ($totalGB -gt 7.5) {
    Write-Host ''
    Write-Host '  This will not fit in 8 GB. Before launching, try one of:' -ForegroundColor Yellow
    Write-Host '    - a smaller -CacheType (q8_0 -> q4_0)'
    Write-Host '    - fewer -GpuLayers, pushing some layers to system RAM'
    Write-Host '    - a smaller -ContextSize, and patch the floor instead'
}

# --- Launch -------------------------------------------------------------------
$serverArgs = @(
    '--model', $ModelPath
    '--ctx-size', $ContextSize
    '--host', $ListenHost
    '--port', $Port
    '--n-gpu-layers', $GpuLayers
    '--cache-type-k', $CacheType
    '--cache-type-v', $CacheType
)
# Quantised V-cache requires flash attention in llama.cpp.
if ($CacheType -ne 'f16') { $serverArgs += '--flash-attn' }

Write-Host ''
Write-Host '== Command ==================================================' -ForegroundColor Cyan
Write-Host "  $ServerExe $($serverArgs -join ' ')"

if ($DryRun) {
    Write-Host ''
    Write-Host 'Dry run; nothing launched.'
    exit 0
}

# Refuse to fight an existing listener rather than failing obscurely later.
$busy = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($busy) {
    $owner = (Get-Process -Id $busy[0].OwningProcess -ErrorAction SilentlyContinue).ProcessName
    throw "Port $Port is already bound by PID $($busy[0].OwningProcess) ($owner). Stop it first, or pass a different -Port."
}

Write-Host ''
Write-Host "Starting $ServerExe ..." -ForegroundColor Cyan
$proc = Start-Process -FilePath $ServerExe -ArgumentList $serverArgs -PassThru -NoNewWindow

# Poll until it answers or dies. Large contexts take a while to allocate.
$deadline = (Get-Date).AddSeconds(180)
while ((Get-Date) -lt $deadline) {
    if ($proc.HasExited) { throw "$ServerExe exited with code $($proc.ExitCode) before serving." }
    if (Get-ServerProps -Url $BaseUrl -TimeoutSec 2) { break }
    Start-Sleep -Seconds 3
}

if (-not (Show-Probe -Url $BaseUrl)) {
    throw "Server did not become ready within 180s. Check its output above for an OOM or allocation failure."
}

Write-Host "  PID $($proc.Id)" -ForegroundColor DarkGray
