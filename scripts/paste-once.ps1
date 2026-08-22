# Hermes Agent -- one-shot recovery. Paste the whole thing into PowerShell.
# Every statement is single-line on purpose so it survives a console paste.

Set-Location $env:USERPROFILE
Get-Process llama-server -EA 0 | Stop-Process -Force
$stale = "$env:USERPROFILE\Downloads\hermes-agent-2026.8.19"
if (Test-Path $stale) { Move-Item $stale "$stale.broken-$(Get-Date -f yyyyMMddHHmmss)" -Force; "Moved the broken copy aside." }

"Looking for a .gguf model (this can take a minute)..."
$all = Get-ChildItem $env:USERPROFILE -Filter *.gguf -Recurse -EA 0 | Sort-Object Length -Descending
if (-not $all) { throw "No .gguf found under $env:USERPROFILE. If your model is on another drive, run:  `$model = Get-Item 'D:\path\to\model.gguf'  then paste the rest again." }
$model = $all | Where-Object { $_.Name -match 'qwen3.*8b' } | Select-Object -First 1
if (-not $model) { $model = $all[0] }
"Using model: $($model.FullName)"

if (-not (Get-Command hermes -EA 0)) { "Installing Hermes Agent (several minutes)..."; iex (irm https://hermes-agent.nousresearch.com/install.ps1) }
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
if (-not (Get-Command hermes -EA 0)) { throw "Installed, but hermes is not on PATH yet. Close this window, open a NEW PowerShell, and paste this again -- it will skip straight past the install." }

Push-Location "$env:USERPROFILE\.hermes\hermes-agent"; uv pip install -e ".[web]"; Pop-Location

"Starting llama-server at 65536 context..."
Start-Process llama-server -NoNewWindow -ArgumentList @('--model',$model.FullName,'--ctx-size',65536,'--flash-attn','--cache-type-k','q4_0','--cache-type-v','q4_0','--n-gpu-layers',32,'--host','127.0.0.1','--port',8080)
$props = $null
foreach ($i in 1..60) { try { $props = Invoke-RestMethod 'http://127.0.0.1:8080/props' -TimeoutSec 3; break } catch { Start-Sleep 3 } }
if (-not $props) { throw "llama-server did not come up. Most likely out of VRAM -- re-run the Start-Process line above with -n-gpu-layers 24." }
$nctx = $props.default_generation_settings.n_ctx; if (-not $nctx) { $nctx = $props.n_ctx }
"llama-server is up. n_ctx = $nctx"
if ($nctx -and $nctx -lt 64000) { "WARNING: $nctx is below the 64000 Hermes requires. Lower --n-gpu-layers and retry." }

[Environment]::SetEnvironmentVariable('CUSTOM_BASE_URL','http://127.0.0.1:8080/v1','User')
[Environment]::SetEnvironmentVariable('CUSTOM_API_KEY','local','User')
$env:CUSTOM_BASE_URL='http://127.0.0.1:8080/v1'; $env:CUSTOM_API_KEY='local'

hermes doctor
"Now run:  hermes model     (choose 'Custom Endpoint'), then:  hermes dashboard"
