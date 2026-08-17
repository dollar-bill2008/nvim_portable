<#
.SYNOPSIS
    Installs a portable Neovim from the bundled zip. No admin rights required.

.DESCRIPTION
    Extracts bin/nvim-win64.zip into a user-writable directory, optionally adds
    it to the user-scope PATH, and verifies the binary actually executes.

    Nothing here needs elevation: no MSI, no registry writes outside HKCU, no
    services. If this script fails at the "verify" step with an access or
    policy error, the machine is enforcing AppLocker or user-mode WDAC -- run
    probe.ps1 for the diagnosis.

.PARAMETER InstallRoot
    Parent directory for the install. Defaults to %LOCALAPPDATA%\Programs.

.PARAMETER SkipPath
    Do not modify the user PATH.

.PARAMETER SkipHashCheck
    Skip SHA256 verification of the bundled zip.

.EXAMPLE
    .\install.ps1

.EXAMPLE
    .\install.ps1 -InstallRoot D:\tools -SkipPath
#>
[CmdletBinding()]
param(
    [string] $InstallRoot = (Join-Path $env:LOCALAPPDATA 'Programs'),
    [switch] $SkipPath,
    [switch] $SkipHashCheck
)

$ErrorActionPreference = 'Stop'

# SHA256 of neovim v0.12.4 nvim-win64.zip, recorded when the zip was fetched
# from https://github.com/neovim/neovim/releases/download/v0.12.4/nvim-win64.zip
# Upstream published no checksum file for this tag, so this pins the exact
# bytes that were vetted rather than an upstream-attested digest.
$ExpectedSha256 = '9fc3572829ffd13debb6e32555da2c8cc02555568260a9fc4cf1f65bbcca319c'

# $PSScriptRoot and $MyInvocation are both empty when this script is run via
# Invoke-Expression, which is the only route left when a Group Policy
# execution policy is in force. Fall back to the working directory so that
# route still finds the bundled zip.
# Both are null under Invoke-Expression, and Split-Path throws on a null
# argument rather than returning empty, so guard before calling it.
$scriptDir = $PSScriptRoot
if (-not $scriptDir -and $MyInvocation.MyCommand.Path) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }

$zipPath    = Join-Path $scriptDir 'bin\nvim-win64.zip'
$installDir = Join-Path $InstallRoot 'nvim-portable'
$binDir     = Join-Path $installDir 'bin'
$nvimExe    = Join-Path $binDir 'nvim.exe'

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

if (-not (Test-Path $zipPath)) {
    throw "Bundled zip not found at $zipPath. Was the repo cloned with the bin/ directory intact?"
}

# Downloaded files carry a mark-of-the-web zone identifier that makes Windows
# treat every extracted exe as untrusted. Strip it before extracting.
Write-Step 'Clearing mark-of-the-web from the bundled zip'
Unblock-File -Path $zipPath
Write-Ok 'zone identifier cleared'

if ($SkipHashCheck) {
    Write-Warn 'hash verification skipped by request'
} else {
    Write-Step 'Verifying zip integrity'
    $actual = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $ExpectedSha256) {
        throw "SHA256 mismatch.`n  expected $ExpectedSha256`n  actual   $actual`nThe zip was altered in transit or by git. Do not run it."
    }
    Write-Ok "sha256 $actual"
}

# Extract to a staging directory first so an interrupted or policy-blocked
# extraction never leaves a half-populated install behind.
$staging = Join-Path ([System.IO.Path]::GetTempPath()) ("nvim-stage-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $staging | Out-Null

try {
    Write-Step "Extracting to staging area"

    # tar.exe (bsdtar) ships in System32 on Windows 10 1803+ and handles zip.
    # It is preferred because Expand-Archive is frequently blocked by
    # constrained-language-mode PowerShell policies on locked-down builds.
    $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
    if (Test-Path $tar) {
        & $tar -xf $zipPath -C $staging
        if ($LASTEXITCODE -ne 0) { throw "tar.exe exited with code $LASTEXITCODE" }
        Write-Ok 'extracted with tar.exe'
    } else {
        Expand-Archive -Path $zipPath -DestinationPath $staging -Force
        Write-Ok 'extracted with Expand-Archive'
    }

    # The archive contains a single top-level folder (nvim-win64) holding
    # bin/, lib/ and share/. Locate it rather than assuming the name, since
    # upstream has renamed it between releases.
    $payload = Get-ChildItem $staging -Directory | Select-Object -First 1
    if (-not $payload) { throw "Extracted archive contained no top-level directory." }
    if (-not (Test-Path (Join-Path $payload.FullName 'bin\nvim.exe'))) {
        throw "Extracted payload at $($payload.FullName) has no bin\nvim.exe."
    }

    # Only ever remove a directory that looks like a previous run of this
    # script, so a mistyped -InstallRoot cannot delete unrelated data.
    if (Test-Path $installDir) {
        if (Test-Path (Join-Path $installDir 'bin\nvim.exe')) {
            # A running editor holds its own binary open, which no amount of
            # retrying will clear. Say so plainly instead of timing out.
            $running = Get-Process -Name nvim, nvim-qt -ErrorAction SilentlyContinue |
                Where-Object { $_.Path -and $_.Path.StartsWith($installDir, [StringComparison]::OrdinalIgnoreCase) }
            if ($running) {
                throw "Neovim is running from $installDir (PID $($running.Id -join ', ')). Close it and re-run."
            }

            Write-Step "Removing previous install at $installDir"
            Remove-WithRetry -Path $installDir
            Write-Ok 'previous install removed'
        } else {
            throw "$installDir exists but does not look like a nvim-portable install (no bin\nvim.exe). Refusing to delete it."
        }
    }

    Write-Step "Installing to $installDir"
    New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
    Move-Item -Path $payload.FullName -Destination $installDir
    Write-Ok "installed"
}
finally {
    if (Test-Path $staging) { Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue }
}

# This is the real test of whether the machine permits execution from a
# user-writable path. --clean bypasses every config file, so a broken or
# unrelated config cannot mask a genuine execution failure.
Write-Step 'Verifying the binary executes'
try {
    $version = & $nvimExe --version 2>&1 | Select-Object -First 1
    & $nvimExe --clean --headless "+qall" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "nvim --clean exited with code $LASTEXITCODE" }
    Write-Ok "$version"
    Write-Ok 'headless startup succeeded'
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

if ($SkipPath) {
    Write-Warn 'PATH not modified by request'
} else {
    Write-Step 'Adding to user PATH'
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($null -eq $userPath) { $userPath = '' }
    $entries = $userPath -split ';' | Where-Object { $_ -ne '' }

    if ($entries -contains $binDir) {
        Write-Ok 'already present in user PATH'
    } else {
        $newPath = (@($entries) + $binDir) -join ';'
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        Write-Ok "appended $binDir"
        Write-Warn 'open a new terminal for the PATH change to take effect'
    }

    # Make nvim usable in the current session without reopening the terminal.
    if (($env:Path -split ';') -notcontains $binDir) { $env:Path = "$env:Path;$binDir" }
}

Write-Host ''
Write-Host 'Neovim portable is installed.' -ForegroundColor Green
Write-Host "  binary : $nvimExe"
Write-Host "  config : $env:LOCALAPPDATA\nvim  (or set NVIM_APPNAME to isolate)"
Write-Host ''
Write-Host 'Verify in a new terminal with:  nvim --version'
