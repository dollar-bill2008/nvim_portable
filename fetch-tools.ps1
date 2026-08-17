<#
.SYNOPSIS
    Rebuilds tools/nvim-tools.zip from upstream releases. Maintenance only.

.DESCRIPTION
    The config depends on four external binaries that have no pip route and
    cannot be assumed present on a locked-down machine:

        rg                   ripgrep, telescope's grep backend
        fd                   telescope's file listing backend
        rust-analyzer        Rust language server
        lua-language-server  Lua language server

    Rather than expect a package manager on the target machine, they are
    normalised into a single zip committed to this repo, which setup.ps1
    extracts. One clone delivers editor, tools and config.

    You do NOT need to run this to install anything -- tools/nvim-tools.zip is
    already committed. Run it only to update the pinned versions, then commit
    the rebuilt zip and manifest.

    Python tooling is deliberately absent: basedpyright and ruff both install
    from pip on a bare machine, and basedpyright bundles its own Node through
    nodejs-wheel-binaries, so neither needs bundling.

.EXAMPLE
    .\fetch-tools.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$scriptDir = $PSScriptRoot
if (-not $scriptDir -and $MyInvocation.MyCommand.Path) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }

$toolsDir = Join-Path $scriptDir 'tools'
$outZip   = Join-Path $toolsDir 'nvim-tools.zip'
$manifest = Join-Path $toolsDir 'manifest.json'

function Write-Step { param([string] $m) Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok   { param([string] $m) Write-Host "    OK   $m" -ForegroundColor Green }

# Versions are pinned rather than tracking "latest", so a rebuild is
# reproducible and an upstream change cannot silently alter what ships.
$sources = @(
    @{
        name    = 'ripgrep'
        version = '15.2.0'
        url     = 'https://github.com/BurntSushi/ripgrep/releases/download/15.2.0/ripgrep-15.2.0-x86_64-pc-windows-msvc.zip'
        # Archive nests everything under a versioned directory; pull out just
        # the executable and place it flat in bin/.
        take    = @{ pattern = 'rg.exe'; into = 'bin' }
    },
    @{
        name    = 'fd'
        version = 'v10.4.2'
        url     = 'https://github.com/sharkdp/fd/releases/download/v10.4.2/fd-v10.4.2-x86_64-pc-windows-msvc.zip'
        take    = @{ pattern = 'fd.exe'; into = 'bin' }
    },
    @{
        name    = 'rust-analyzer'
        version = '2026-08-17.3'
        url     = 'https://github.com/rust-lang/rust-analyzer/releases/download/2026-08-17.3/rust-analyzer-x86_64-pc-windows-msvc.zip'
        take    = @{ pattern = 'rust-analyzer.exe'; into = 'bin' }
    },
    @{
        name    = 'lua-language-server'
        version = '3.19.1'
        url     = 'https://github.com/LuaLS/lua-language-server/releases/download/3.19.1/lua-language-server-3.19.1-win32-x64.zip'
        # This one needs its whole distribution, not a single file: the
        # executable loads main.lua plus the meta/ and locale/ trees at runtime.
        wholeTree = 'lua-language-server'
    }
)

New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null
$work    = Join-Path ([System.IO.Path]::GetTempPath()) ("nvim-tools-" + [Guid]::NewGuid().ToString('N'))
$staging = Join-Path $work 'staging'
New-Item -ItemType Directory -Force -Path (Join-Path $staging 'bin') | Out-Null

$records = @()
$tar = Join-Path $env:SystemRoot 'System32\tar.exe'

try {
    foreach ($src in $sources) {
        Write-Step "$($src.name) $($src.version)"

        $dl = Join-Path $work "$($src.name).zip"
        Invoke-WebRequest -Uri $src.url -OutFile $dl -UseBasicParsing -TimeoutSec 600
        $sha = (Get-FileHash $dl -Algorithm SHA256).Hash.ToLower()
        Write-Ok ("downloaded {0:N1} MB, sha256 {1}" -f ((Get-Item $dl).Length / 1MB), $sha.Substring(0, 16))

        $ex = Join-Path $work "extract-$($src.name)"
        New-Item -ItemType Directory -Force -Path $ex | Out-Null
        & $tar -xf $dl -C $ex
        if ($LASTEXITCODE -ne 0) { throw "extraction of $($src.name) failed with code $LASTEXITCODE" }

        if ($src.wholeTree) {
            # Some archives have a single top-level folder, others extract flat.
            # Detect which, so the staged tree is the same either way.
            $top = Get-ChildItem $ex -Directory
            $root = $ex
            if ($top.Count -eq 1 -and -not (Get-ChildItem $ex -File)) { $root = $top[0].FullName }
            $dest = Join-Path $staging $src.wholeTree
            Copy-Item $root $dest -Recurse
            Write-Ok "staged whole tree -> $($src.wholeTree)/"
        } else {
            $found = Get-ChildItem $ex -Recurse -File -Filter $src.take.pattern | Select-Object -First 1
            if (-not $found) { throw "$($src.take.pattern) not found in the $($src.name) archive" }
            Copy-Item $found.FullName (Join-Path $staging $src.take.into)
            Write-Ok "staged $($src.take.into)/$($found.Name)"
        }

        $records += [ordered]@{
            name          = $src.name
            version       = $src.version
            url           = $src.url
            sourceSha256  = $sha
        }
    }

    Write-Step 'Building tools/nvim-tools.zip'
    if (Test-Path $outZip) { Remove-Item $outZip -Force }
    Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $outZip -CompressionLevel Optimal
    $bundleSha = (Get-FileHash $outZip -Algorithm SHA256).Hash.ToLower()
    Write-Ok ("{0:N1} MB, sha256 {1}" -f ((Get-Item $outZip).Length / 1MB), $bundleSha)

    ([ordered]@{
        note       = 'Rebuild with fetch-tools.ps1. setup.ps1 verifies bundleSha256 before extracting.'
        bundleSha256 = $bundleSha
        tools      = $records
    } | ConvertTo-Json -Depth 5) | Set-Content -Path $manifest -Encoding utf8
    Write-Ok "wrote $manifest"
}
finally {
    if (Test-Path $work) { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
Write-Host 'Done. Commit tools/nvim-tools.zip and tools/manifest.json.' -ForegroundColor Green
Write-Host "Update the ExpectedToolsSha256 constant in setup.ps1 to: $bundleSha"

