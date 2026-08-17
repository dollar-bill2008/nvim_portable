<#
.SYNOPSIS
    Points Neovim's config location at the nvim/ folder in this repo.

.DESCRIPTION
    Neovim only reads its configuration from stdpath('config'), which is
    %LOCALAPPDATA%\nvim on Windows. This script creates a directory junction
    there pointing at nvim/ inside this repo, so the config lives under version
    control while Neovim still finds it where it expects.

    A junction is used rather than a symbolic link because Windows permits
    junctions without administrator rights or Developer Mode. Symbolic links
    require one or the other, which a locked-down corporate build will not give
    you. The tradeoff is that junctions only work within a single volume --
    fine here, since both paths are on C:.

    Safe to re-run. It refuses to touch a real directory of config files, so it
    cannot silently destroy a config that is not already a link.

.PARAMETER Force
    Replace an existing real directory at the config location. The directory is
    renamed with a timestamp rather than deleted.

.EXAMPLE
    .\link-config.ps1
#>
[CmdletBinding()]
param(
    [switch] $Force
)

$ErrorActionPreference = 'Stop'

# Empty under Invoke-Expression, which is the fallback route when a Group
# Policy execution policy blocks running script files. See README.
$scriptDir = $PSScriptRoot
if (-not $scriptDir -and $MyInvocation.MyCommand.Path) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }

$source = Join-Path $scriptDir 'nvim'
$link   = Join-Path $env:LOCALAPPDATA 'nvim'

function Write-Step { param([string] $Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string] $Message) Write-Host "    OK   $Message" -ForegroundColor Green }
function Write-Warn { param([string] $Message) Write-Host "    WARN $Message" -ForegroundColor Yellow }

if (-not (Test-Path $source)) {
    throw "No nvim/ directory found at $source. Are you running this from the repo root?"
}

if (Test-Path $link) {
    $existing = Get-Item $link -Force
    $isLink = [bool]($existing.Attributes -band [IO.FileAttributes]::ReparsePoint)

    if ($isLink) {
        # Re-running with the link already in place is the common case. Only
        # rebuild it if it points somewhere else.
        $currentTarget = $existing.Target
        if ($currentTarget -and ($currentTarget -contains $source -or $currentTarget -eq $source)) {
            Write-Ok "already linked: $link -> $source"
            return
        }
        Write-Step "Replacing existing link (points at $currentTarget)"
        Remove-Item -LiteralPath $link -Force
    }
    elseif ($Force) {
        $backup = "$link.replaced-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
        Write-Step "Moving existing config directory aside"
        Move-Item -LiteralPath $link -Destination $backup
        Write-Ok "moved to $backup"
    }
    else {
        throw "$link already exists and is a real directory, not a link.`nIt holds a config that is not part of this repo. Re-run with -Force to move it aside (it will be renamed, not deleted)."
    }
}

Write-Step "Linking $link -> $source"
New-Item -ItemType Junction -Path $link -Target $source | Out-Null
Write-Ok 'junction created (no admin rights required)'

# Prove Neovim actually resolves the link, rather than trusting that the
# filesystem object exists.
$nvim = Join-Path $env:LOCALAPPDATA 'Programs\nvim-portable\bin\nvim.exe'
if (Test-Path $nvim) {
    Write-Step 'Verifying Neovim reads the linked config'
    $probe = & $nvim --headless "+lua io.write(vim.fn.stdpath('config') .. '|' .. tostring(vim.loop.fs_stat(vim.fn.stdpath('config') .. '/init.lua') ~= nil))" "+qall" 2>&1
    $parts = ($probe -join '') -split '\|'
    Write-Ok "stdpath('config') = $($parts[0])"
    if ($parts[1] -eq 'true') { Write-Ok 'init.lua is visible to Neovim' }
    else { Write-Warn 'init.lua NOT visible -- the link exists but Neovim cannot see the file' }
} else {
    Write-Warn "Neovim not found at $nvim; run install.ps1 first"
}
