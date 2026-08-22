<#
.SYNOPSIS
    Restores hand-edited Hermes Agent source files from the original download
    archive, then reports where the context-window minimum is enforced.

.DESCRIPTION
    Manual find-and-replace on a vendored package is how the current install
    ended up raising:

        AttributeError: 'AIAgent' object has no attribute 'api_mode'

    That is not a bug to patch on top of. It means the edit truncated or
    reflowed the constructor so some attribute assignments no longer execute.
    The fix is to put the original bytes back and then change behaviour
    through a mechanism that cannot corrupt syntax.

    No internet access is needed: the extracted folder name is doubled
    (hermes-agent-2026.8.19\hermes-agent-2026.8.19), which is the signature of
    Expand-Archive on a zip that is almost certainly still in Downloads. This
    script re-extracts that zip to a scratch directory and copies pristine
    files back over the damaged ones.

.EXAMPLE
    .\Repair-HermesInstall.ps1 -Verify
    .\Repair-HermesInstall.ps1 -Restore
#>
[CmdletBinding(DefaultParameterSetName = 'Verify')]
param(
    [string] $InstallRoot = "$env:USERPROFILE\Downloads\hermes-agent-2026.8.19\hermes-agent-2026.8.19",

    # Original archive. Adjust if it was saved elsewhere or already deleted.
    [string] $ArchivePath = "$env:USERPROFILE\Downloads\hermes-agent-2026.8.19.zip",

    [Parameter(ParameterSetName = 'Verify')]
    [switch] $Verify,

    [Parameter(ParameterSetName = 'Restore')]
    [switch] $Restore,

    # Files known to have been hand-edited. Add more as needed.
    [string[]] $DamagedFiles = @('agent_init.py', 'turn_context.py')
)

$ErrorActionPreference = 'Stop'

function Write-Section([string] $Text) {
    Write-Host ''
    Write-Host "== $Text " -ForegroundColor Cyan -NoNewline
    Write-Host ('=' * [Math]::Max(0, 60 - $Text.Length)) -ForegroundColor Cyan
}

if (-not (Test-Path -LiteralPath $InstallRoot)) {
    throw "Install root not found: $InstallRoot`nPass -InstallRoot with the correct path."
}

Write-Section 'Install root'
Write-Host $InstallRoot

# --- Locate the damaged files -------------------------------------------------
Write-Section 'Locating hand-edited files'
$targets = @()
foreach ($name in $DamagedFiles) {
    $found = Get-ChildItem -LiteralPath $InstallRoot -Filter $name -Recurse -File -ErrorAction SilentlyContinue
    if (-not $found) {
        Write-Host "  [miss] $name -- not present under install root" -ForegroundColor Yellow
        continue
    }
    foreach ($f in $found) {
        $rel = $f.FullName.Substring($InstallRoot.Length).TrimStart('\')
        $targets += [pscustomobject]@{ Relative = $rel; Full = $f.FullName }
        Write-Host "  [ok]   $rel"
    }
}

# --- Does each file still parse? ---------------------------------------------
Write-Section 'Syntax check (python -m py_compile)'
$broken = @()
foreach ($t in $targets) {
    & python -m py_compile $t.Full 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [parses] $($t.Relative)" -ForegroundColor Green
    } else {
        Write-Host "  [SYNTAX ERROR] $($t.Relative)" -ForegroundColor Red
        & python -m py_compile $t.Full 2>&1 | Select-Object -First 6 | ForEach-Object { Write-Host "      $_" }
        $broken += $t
    }
}
Write-Host ''
Write-Host '  Note: a file can parse cleanly and still be wrong. The AttributeError' -ForegroundColor DarkGray
Write-Host '  on api_mode is a runtime symptom of a semantically broken __init__,' -ForegroundColor DarkGray
Write-Host '  not necessarily a syntax error.' -ForegroundColor DarkGray

# --- Where is the 64k floor enforced? ----------------------------------------
Write-Section 'Sites enforcing the context minimum'
$hits = Get-ChildItem -LiteralPath $InstallRoot -Filter *.py -Recurse -File |
    Select-String -Pattern '64000|64_000|MIN_CONTEXT|MINIMUM_CONTEXT|min_context|n_ctx_seq|context window of' -CaseSensitive:$false
if ($hits) {
    $hits | ForEach-Object {
        $rel = $_.Path.Substring($InstallRoot.Length).TrimStart('\')
        Write-Host ("  {0}:{1}" -f $rel, $_.LineNumber) -ForegroundColor Yellow
        Write-Host ("      " + $_.Line.Trim())
    }
} else {
    Write-Host '  No matches. The floor may live in config.yaml or a non-.py resource.' -ForegroundColor Yellow
}

# --- Config surface -----------------------------------------------------------
Write-Section 'Config files under install root'
Get-ChildItem -LiteralPath $InstallRoot -Include *.yaml, *.yml, *.toml, *.json -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\(node_modules|\.git|__pycache__|site-packages)\\' } |
    ForEach-Object {
        $rel = $_.FullName.Substring($InstallRoot.Length).TrimStart('\')
        Write-Host ("  {0,-55} {1,8:N0} bytes" -f $rel, $_.Length)
    }

if ($Verify) {
    Write-Section 'Done (verify only)'
    Write-Host 'Re-run with -Restore to copy pristine files back from the archive.'
    return
}

# --- Restore ------------------------------------------------------------------
if (-not $Restore) { return }

Write-Section 'Restoring from archive'
if (-not (Test-Path -LiteralPath $ArchivePath)) {
    throw @"
Archive not found: $ArchivePath

Nothing is restored. Options, in order of preference:
  1. Point -ArchivePath at the original zip wherever it was saved.
  2. Recover the two files from the Recycle Bin or File History
     (right-click the folder -> Restore previous versions).
  3. Re-extract from any other copy of the release you still have.

Do not continue editing the damaged files by hand.
"@
}

$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("hermes-pristine-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
Write-Host "  Extracting archive -> $scratch"
Expand-Archive -LiteralPath $ArchivePath -DestinationPath $scratch -Force

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$restored = 0
foreach ($t in $targets) {
    $leaf = Split-Path -Leaf $t.Full
    $source = Get-ChildItem -LiteralPath $scratch -Filter $leaf -Recurse -File -ErrorAction SilentlyContinue |
        Sort-Object { $_.FullName.Length } | Select-Object -First 1
    if (-not $source) {
        Write-Host "  [miss] $leaf not found in archive" -ForegroundColor Yellow
        continue
    }
    $backup = "$($t.Full).broken-$stamp"
    Copy-Item -LiteralPath $t.Full -Destination $backup -Force
    Copy-Item -LiteralPath $source.FullName -Destination $t.Full -Force
    Write-Host "  [restored] $($t.Relative)" -ForegroundColor Green
    Write-Host "      damaged copy kept at $backup" -ForegroundColor DarkGray
    $restored++
}

Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue

Write-Section 'Restore complete'
Write-Host "  $restored file(s) restored."
Write-Host ''
Write-Host '  Next: do NOT re-apply the edit by hand. Either raise the server''s'
Write-Host '  context (see docs/hermes-context-window.md) or use'
Write-Host '  scripts/hermes_ctx_patch.py, which edits only the numeric literal'
Write-Host '  and reverts automatically if the file stops compiling.'
