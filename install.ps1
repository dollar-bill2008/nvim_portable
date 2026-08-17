<#
.SYNOPSIS
    Installs portable Neovim and its external tools. No admin rights required.

.DESCRIPTION
    Extracts two bundles committed to this repo into a user-writable directory
    and puts them on the user-scope PATH:

        bin/nvim-win64.zip    Neovim itself
        tools/nvim-tools.zip  rg, fd, rust-analyzer, lua-language-server

    Nothing here needs elevation: no MSI, no registry writes outside HKCU, no
    services. If this fails at a "verify" step with an access or policy error,
    the machine is enforcing AppLocker or user-mode WDAC -- run probe.ps1.

    Python tooling is not bundled because it does not need to be. On the target
    machine:

        pip install --user basedpyright ruff

    basedpyright brings its own Node through nodejs-wheel-binaries, so no
    system Node is required.

.PARAMETER InstallRoot
    Parent directory for both installs. Defaults to %LOCALAPPDATA%\Programs.

.PARAMETER SkipPath
    Do not modify the user PATH.

.PARAMETER SkipTools
    Install Neovim only, leaving rg / fd / the language servers out.

.PARAMETER SkipHashCheck
    Skip SHA256 verification of the bundled zips.

.EXAMPLE
    .\install.ps1

.EXAMPLE
    .\install.ps1 -InstallRoot D:\tools -SkipPath
#>
[CmdletBinding()]
param(
    [string] $InstallRoot = (Join-Path $env:LOCALAPPDATA 'Programs'),
    [switch] $SkipPath,
    [switch] $SkipTools,
    [switch] $SkipHashCheck
)

$ErrorActionPreference = 'Stop'

# SHA256 of the two committed bundles, recorded when they were built.
#
# nvim-win64.zip is neovim v0.12.4, fetched from
# https://github.com/neovim/neovim/releases/download/v0.12.4/nvim-win64.zip
# Upstream published no checksum file for that tag, so this pins the exact
# bytes that were vetted rather than an upstream-attested digest.
#
# nvim-tools.zip is assembled by fetch-tools.ps1; tools/manifest.json records
# each upstream source, its version and its own SHA256.
$ExpectedNvimSha256  = '9fc3572829ffd13debb6e32555da2c8cc02555568260a9fc4cf1f65bbcca319c'
$ExpectedToolsSha256 = 'f3ebe11822a36debc3ae82ddc7000f6dc181e65fd550c373df1cad8855f9a308'

# Both are null under Invoke-Expression, which is the only route left when a
# Group Policy execution policy is in force, and Split-Path throws on a null
# argument rather than returning empty. Guard before calling it.
$scriptDir = $PSScriptRoot
if (-not $scriptDir -and $MyInvocation.MyCommand.Path) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }

$nvimZip   = Join-Path $scriptDir 'bin\nvim-win64.zip'
$toolsZip  = Join-Path $scriptDir 'tools\nvim-tools.zip'
$nvimDir   = Join-Path $InstallRoot 'nvim-portable'
$toolsDir  = Join-Path $InstallRoot 'nvim-portable-tools'
$nvimExe   = Join-Path $nvimDir 'bin\nvim.exe'

function Write-Step { param([string] $Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string] $Message) Write-Host "    OK   $Message" -ForegroundColor Green }
function Write-Warn { param([string] $Message) Write-Host "    WARN $Message" -ForegroundColor Yellow }

function Remove-WithRetry {
    <#
        Real-time antivirus on managed corporate builds transiently opens
        freshly written binaries to scan them, which surfaces here as an
        access-denied on files such as bin\DbgHelp.dll. The lock clears within
        a few hundred milliseconds, so back off and retry rather than fail an
        otherwise healthy install.
    #>
    param(
        [Parameter(Mandatory)] [string] $Path,
        [int] $Attempts = 5
    )
    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            return
        }
        catch {
            if ($i -eq $Attempts) { throw }
            Write-Warn "locked, retrying ($i/$Attempts): $($_.Exception.Message)"
            Start-Sleep -Milliseconds (250 * $i)
        }
    }
}

function Expand-Bundle {
    <#
        Verifies and extracts one committed zip into $TargetDir.

        Extraction goes to a staging directory first, so a blocked or
        interrupted run never leaves a half-populated install behind. The
        target is only removed if it looks like a previous run of this script,
        so a mistyped -InstallRoot cannot delete unrelated data.

        -StripTopLevel handles archives that nest everything under a single
        versioned folder (nvim-win64/) versus those that extract flat.
    #>
    param(
        [Parameter(Mandatory)] [string] $ZipPath,
        [Parameter(Mandatory)] [string] $TargetDir,
        [Parameter(Mandatory)] [string] $ExpectedSha256,
        [Parameter(Mandatory)] [string] $Label,
        [string] $SentinelRelativePath,
        [switch] $StripTopLevel,
        [switch] $NoHashCheck
    )

    if (-not (Test-Path $ZipPath)) {
        throw "Bundled zip not found at $ZipPath. Was the repo cloned with its bin/ and tools/ directories intact?"
    }

    # Downloaded files carry a mark-of-the-web zone identifier that makes
    # Windows treat every extracted exe as untrusted. A git clone does not set
    # it, but downloading the repo as a zip does.
    Unblock-File -Path $ZipPath

    if ($NoHashCheck) {
        Write-Warn "$Label hash verification skipped by request"
    } else {
        $actual = (Get-FileHash $ZipPath -Algorithm SHA256).Hash.ToLower()
        if ($actual -ne $ExpectedSha256) {
            throw "SHA256 mismatch for $Label.`n  expected $ExpectedSha256`n  actual   $actual`nThe zip was altered in transit or by git. Do not run it."
        }
        Write-Ok "$Label sha256 verified"
    }

    $staging = Join-Path ([System.IO.Path]::GetTempPath()) ("nvim-stage-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $staging | Out-Null

    try {
        # tar.exe (bsdtar) ships in System32 on Windows 10 1803+ and handles
        # zip. Preferred because Expand-Archive is frequently unavailable under
        # constrained-language-mode PowerShell on locked-down builds.
        $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
        if (Test-Path $tar) {
            & $tar -xf $ZipPath -C $staging
            if ($LASTEXITCODE -ne 0) { throw "tar.exe exited with code $LASTEXITCODE extracting $Label" }
        } else {
            Expand-Archive -Path $ZipPath -DestinationPath $staging -Force
        }

        $payload = $staging
        if ($StripTopLevel) {
            # Locate the folder rather than assuming its name, since upstream
            # has renamed it between releases.
            $top = Get-ChildItem $staging -Directory | Select-Object -First 1
            if (-not $top) { throw "$Label archive contained no top-level directory." }
            $payload = $top.FullName
        }

        if ($SentinelRelativePath) {
            $sentinel = Join-Path $payload $SentinelRelativePath
            if (-not (Test-Path $sentinel)) {
                throw "$Label payload is missing $SentinelRelativePath -- the archive is not what was expected."
            }
        }

        if (Test-Path $TargetDir) {
            $looksLikeOurs = -not $SentinelRelativePath -or (Test-Path (Join-Path $TargetDir $SentinelRelativePath))
            if (-not $looksLikeOurs) {
                throw "$TargetDir exists but does not look like a previous $Label install (no $SentinelRelativePath). Refusing to delete it."
            }
            Write-Step "Removing previous $Label install"
            Remove-WithRetry -Path $TargetDir
        }

        New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
        if ($StripTopLevel) {
            Move-Item -LiteralPath $payload -Destination $TargetDir
        } else {
            New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
            Get-ChildItem $payload -Force | ForEach-Object {
                Move-Item -LiteralPath $_.FullName -Destination $TargetDir
            }
        }
        Write-Ok "$Label installed to $TargetDir"
    }
    finally {
        if (Test-Path $staging) { Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# A running editor holds its own binary open, which no amount of retrying will
# clear. Detect it before touching anything.
$running = Get-Process -Name nvim, nvim-qt -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -and $_.Path.StartsWith($nvimDir, [StringComparison]::OrdinalIgnoreCase) }
if ($running) {
    throw "Neovim is running from $nvimDir (PID $($running.Id -join ', ')). Close it and re-run."
}

Write-Step 'Installing Neovim'
Expand-Bundle -ZipPath $nvimZip -TargetDir $nvimDir -ExpectedSha256 $ExpectedNvimSha256 `
    -Label 'neovim' -SentinelRelativePath 'bin\nvim.exe' -StripTopLevel -NoHashCheck:$SkipHashCheck

if ($SkipTools) {
    Write-Warn 'external tools skipped by request'
} else {
    Write-Step 'Installing external tools (rg, fd, rust-analyzer, lua-language-server)'
    Expand-Bundle -ZipPath $toolsZip -TargetDir $toolsDir -ExpectedSha256 $ExpectedToolsSha256 `
        -Label 'tools' -SentinelRelativePath 'bin\rg.exe' -NoHashCheck:$SkipHashCheck
}

# The real test of whether the machine permits execution from a user-writable
# path. --clean bypasses every config file, so a broken or unrelated config
# cannot mask a genuine execution failure.
Write-Step 'Verifying Neovim executes'
try {
    $version = & $nvimExe --version 2>&1 | Select-Object -First 1
    & $nvimExe --clean --headless "+qall" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "nvim --clean exited with code $LASTEXITCODE" }
    Write-Ok "$version"
}
catch {
    Write-Host ''
    Write-Host 'EXECUTION FAILED' -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    Write-Host '  The binary extracted but will not run. If the message mentions'
    Write-Host '  a system administrator or a policy, this machine enforces'
    Write-Host '  AppLocker or user-mode WDAC. Run probe.ps1 for the diagnosis.'
    throw
}

$pathEntries = @(Join-Path $nvimDir 'bin')
if (-not $SkipTools) {
    $pathEntries += Join-Path $toolsDir 'bin'
    $pathEntries += Join-Path $toolsDir 'lua-language-server\bin'
}

if ($SkipPath) {
    Write-Warn 'PATH not modified by request'
} else {
    Write-Step 'Adding to user PATH'
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($null -eq $userPath) { $userPath = '' }
    $entries = @($userPath -split ';' | Where-Object { $_ -ne '' })

    $added = @()
    foreach ($entry in $pathEntries) {
        if ($entries -notcontains $entry) {
            $entries += $entry
            $added += $entry
        }
        # Make the tools usable in this session too, without reopening a terminal.
        if (($env:Path -split ';') -notcontains $entry) { $env:Path = "$env:Path;$entry" }
    }

    if ($added.Count -gt 0) {
        [Environment]::SetEnvironmentVariable('Path', ($entries -join ';'), 'User')
        foreach ($a in $added) { Write-Ok "appended $a" }
        Write-Warn 'open a new terminal for the PATH change to take effect'
    } else {
        Write-Ok 'all entries already present in user PATH'
    }
}

if (-not $SkipTools) {
    $bundled = [ordered]@{
        'rg'                  = Join-Path $toolsDir 'bin\rg.exe'
        'fd'                  = Join-Path $toolsDir 'bin\fd.exe'
        'rust-analyzer'       = Join-Path $toolsDir 'bin\rust-analyzer.exe'
        'lua-language-server' = Join-Path $toolsDir 'lua-language-server\bin\lua-language-server.exe'
    }

    # Verify the BUNDLED binaries by absolute path. Checking Get-Command alone
    # would pass on a machine that already has its own rg or rust-analyzer on
    # PATH, reporting success while the bundle was never exercised at all.
    Write-Step 'Verifying bundled tools execute'
    foreach ($name in $bundled.Keys) {
        $exe = $bundled[$name]
        if (-not (Test-Path $exe)) {
            Write-Warn ("{0,-20} missing from the bundle" -f $name)
            continue
        }
        # Some of these exit non-zero on --version, so judge by whether they
        # produced output rather than by exit code.
        $out = & $exe --version 2>&1 | Select-Object -First 1
        if ($out) { Write-Ok ("{0,-20} {1}" -f $name, $out) }
        else { Write-Warn ("{0,-20} present but produced no output" -f $name) }
    }

    # Then report what PATH will actually resolve to, which can differ when the
    # machine already carries its own copy earlier on PATH.
    Write-Step 'What PATH resolves to'
    foreach ($name in $bundled.Keys) {
        $found = Get-Command $name -ErrorAction SilentlyContinue
        if (-not $found) {
            Write-Warn ("{0,-20} not on PATH yet -- open a new terminal" -f $name)
        } elseif ($found.Source -eq $bundled[$name]) {
            Write-Ok ("{0,-20} bundled copy" -f $name)
        } else {
            Write-Warn ("{0,-20} a different copy wins: {1}" -f $name, $found.Source)
        }
    }
}

Write-Host ''
Write-Host 'Installed.' -ForegroundColor Green
Write-Host "  neovim : $nvimExe"
if (-not $SkipTools) { Write-Host "  tools  : $toolsDir" }
Write-Host "  config : $env:LOCALAPPDATA\nvim"
Write-Host ''
Write-Host 'Next:'
Write-Host '  .\link-config.ps1                        point Neovim at nvim/ in this repo'
Write-Host '  pip install --user basedpyright ruff     Python language server and linter'
Write-Host '  nvim                                     (in a NEW terminal)'
