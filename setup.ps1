<#
.SYNOPSIS
    Single entry point: checks the machine, installs Neovim and its tools,
    links the config, and brings plugins to their pinned versions.

.DESCRIPTION
    Safe to run repeatedly. Every phase is idempotent, so the same command
    installs from scratch on a new machine and applies updates on an existing
    one. Nothing needs administrator rights.

    Phases:
      1. Preflight   can this machine run a portable binary at all?
      2. Install     extract Neovim and the bundled tools, put them on PATH
      3. Link        point Neovim's config location at nvim/ in this repo
      4. Python      pip install the Python language server and linter
      5. Plugins     install and pin plugins to nvim/lazy-lock.json

    Extraction is skipped when the installed bundle already matches the repo's,
    so a re-run costs a couple of seconds unless something actually changed.

.PARAMETER Update
    Run `git pull` first, then apply everything. This is the update path.

.PARAMETER CheckOnly
    Run the preflight checks and stop. Changes nothing.

.PARAMETER InstallRoot
    Parent directory for the installs. Defaults to %LOCALAPPDATA%\Programs.

.PARAMETER Force
    Re-extract bundles even when unchanged, and replace a real (non-linked)
    config directory. An existing config directory is renamed, never deleted.

.PARAMETER SkipTools
    Do not install rg, fd, rust-analyzer, lua-language-server.

.PARAMETER SkipPython
    Do not pip install basedpyright and ruff.

.PARAMETER SkipPlugins
    Do not touch plugins. Neovim will install them itself on first launch.

.PARAMETER SkipPath
    Do not modify the user PATH.

.PARAMETER SkipHashCheck
    Skip SHA256 verification of the bundled zips.

.EXAMPLE
    .\setup.ps1
    Full install or update.

.EXAMPLE
    .\setup.ps1 -CheckOnly
    Will this locked-down machine allow a portable install?

.EXAMPLE
    .\setup.ps1 -Update
    Pull the latest repo state and apply it.
#>
#
# PositionalBinding = $false is deliberate and load-bearing. Without it,
# $InstallRoot is the first positional parameter, so a POSIX-style
# `.\setup.ps1 --Update` -- which PowerShell does not recognise as a switch --
# binds "--Update" as a VALUE for it and installs Neovim into a directory
# literally named "--Update". That happened, and it committed 1,200 junk files.
# With positional binding off, any stray argument is a hard error instead.
#
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch] $Update,
    [switch] $CheckOnly,

    # Reject anything that looks like a mistyped switch rather than a path.
    [ValidateScript({
        if ($_ -match '^-') {
            throw "InstallRoot looks like a mistyped switch: '$_'. PowerShell switches take a single dash, e.g. -Update not --Update."
        }
        $true
    })]
    [string] $InstallRoot = (Join-Path $env:LOCALAPPDATA 'Programs'),

    [switch] $Force,
    [switch] $SkipTools,
    [switch] $SkipPython,
    [switch] $SkipPlugins,
    [switch] $SkipPath,
    [switch] $SkipHashCheck
)

$ErrorActionPreference = 'Stop'

# SHA256 of the two committed bundles, recorded when they were built.
#
# nvim-win64.zip is neovim v0.12.4 from
# https://github.com/neovim/neovim/releases/download/v0.12.4/nvim-win64.zip
# Upstream published no checksum file for that tag, so this pins the exact
# bytes that were vetted rather than an upstream-attested digest.
#
# nvim-tools.zip is assembled by fetch-tools.ps1; tools/manifest.json records
# each upstream source, its version and its own SHA256.
$ExpectedNvimSha256  = '9fc3572829ffd13debb6e32555da2c8cc02555568260a9fc4cf1f65bbcca319c'
$ExpectedToolsSha256 = '6048ebbe6e2b2bd4f669ec8b06ff8cd11ff2229d0561983de9fd6679ff271539'

# $PSScriptRoot and $MyInvocation are both empty under Invoke-Expression, which
# is the only route left when a Group Policy execution policy is in force, and
# Split-Path throws on a null argument rather than returning empty.
$scriptDir = $PSScriptRoot
if (-not $scriptDir -and $MyInvocation.MyCommand.Path) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }

$nvimZip   = Join-Path $scriptDir 'bin\nvim-win64.zip'
$toolsZip  = Join-Path $scriptDir 'tools\nvim-tools.zip'
$configSrc = Join-Path $scriptDir 'nvim'
$nvimDir   = Join-Path $InstallRoot 'nvim-portable'
$toolsDir  = Join-Path $InstallRoot 'nvim-portable-tools'
$nvimExe   = Join-Path $nvimDir 'bin\nvim.exe'
$configLink = Join-Path $env:LOCALAPPDATA 'nvim'

function Write-Section { param([string] $m) Write-Host ''; Write-Host "== $m" -ForegroundColor Cyan }
function Write-Ok      { param([string] $m) Write-Host "   OK    $m" -ForegroundColor Green }
function Write-Warn    { param([string] $m) Write-Host "   WARN  $m" -ForegroundColor Yellow }
function Write-Fail    { param([string] $m) Write-Host "   FAIL  $m" -ForegroundColor Red }
function Write-Info    { param([string] $m) Write-Host "   info  $m" -ForegroundColor Gray }
function Write-Skip    { param([string] $m) Write-Host "   skip  $m" -ForegroundColor DarkGray }

function Remove-WithRetry {
    <#
        Real-time antivirus on managed corporate builds transiently opens
        freshly written binaries to scan them, surfacing here as access-denied
        on files such as bin\DbgHelp.dll. The lock clears within a few hundred
        milliseconds, so back off and retry rather than fail a healthy install.
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

function Invoke-Native {
    <#
        Runs a native executable, returning its combined output as strings and
        leaving the exit code in $script:LastNativeExit.

        Windows PowerShell 5.1 wraps every stderr line from a native command in
        a NativeCommandError record when stderr is redirected. Under
        $ErrorActionPreference = 'Stop' that turns any tool which merely warns
        on stderr -- pip and git both do -- into a terminating failure.
        Dropping to 'Continue' for the duration of the call is the way round
        it, and exit code is the thing worth judging anyway.
    #>
    param(
        [Parameter(Mandatory)] [string] $FilePath,
        [string[]] $Arguments = @()
    )
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $FilePath @Arguments 2>&1 | ForEach-Object { "$_" }
        $script:LastNativeExit = $LASTEXITCODE
        return $output
    }
    finally { $ErrorActionPreference = $previous }
}

function Add-UserPathEntries {
    <#
        Adds directories to the user-scope PATH, idempotently, and to the
        current session so tools are usable without reopening the terminal.
        Returns the entries it actually added.
    #>
    param([Parameter(Mandatory)] [string[]] $Entries)

    if ($SkipPath) {
        Write-Skip 'PATH not modified by request'
        return @()
    }

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($null -eq $userPath) { $userPath = '' }
    $current = @($userPath -split ';' | Where-Object { $_ -ne '' })

    $added = @()
    foreach ($entry in $Entries) {
        if ($current -notcontains $entry) {
            $current += $entry
            $added += $entry
        }
        if (($env:Path -split ';') -notcontains $entry) { $env:Path = "$env:Path;$entry" }
    }

    if ($added.Count -gt 0) {
        [Environment]::SetEnvironmentVariable('Path', ($current -join ';'), 'User')
        foreach ($a in $added) { Write-Ok "PATH += $a" }
    }
    return $added
}

function Install-Bundle {
    <#
        Verifies and extracts one committed zip into $TargetDir.

        A .bundle-sha256 marker is written on success and compared on re-run,
        so an unchanged bundle is skipped entirely. That is what makes this
        script cheap to run repeatedly.

        Extraction stages to a temp directory first, so a blocked or
        interrupted run never leaves a half-populated install. The target is
        removed only when it carries the expected sentinel file, so a mistyped
        -InstallRoot cannot delete unrelated data.

        -StripTopLevel handles archives nesting everything under a single
        versioned folder (nvim-win64/) versus those that extract flat.
    #>
    param(
        [Parameter(Mandatory)] [string] $ZipPath,
        [Parameter(Mandatory)] [string] $TargetDir,
        [Parameter(Mandatory)] [string] $ExpectedSha256,
        [Parameter(Mandatory)] [string] $Label,
        [Parameter(Mandatory)] [string] $SentinelRelativePath,
        [switch] $StripTopLevel
    )

    if (-not (Test-Path $ZipPath)) {
        throw "Bundle not found at $ZipPath. Was the repo cloned with its bin/ and tools/ directories intact?"
    }

    $marker = Join-Path $TargetDir '.bundle-sha256'
    if (-not $Force -and (Test-Path $marker) -and (Test-Path (Join-Path $TargetDir $SentinelRelativePath))) {
        if ((Get-Content $marker -Raw).Trim() -eq $ExpectedSha256) {
            Write-Skip "$Label already at this version"
            return
        }
        Write-Info "$Label version changed, reinstalling"
    }

    # Downloaded files carry a mark-of-the-web zone identifier that makes
    # Windows treat every extracted exe as untrusted. A git clone does not set
    # it; downloading the repo as a zip does.
    Unblock-File -Path $ZipPath

    if ($SkipHashCheck) {
        Write-Warn "$Label hash check skipped by request"
    } else {
        $actual = (Get-FileHash $ZipPath -Algorithm SHA256).Hash.ToLower()
        if ($actual -ne $ExpectedSha256) {
            throw "SHA256 mismatch for $Label.`n  expected $ExpectedSha256`n  actual   $actual`nThe zip was altered in transit or by git. Do not run it."
        }
    }

    $staging = Join-Path ([System.IO.Path]::GetTempPath()) ("nvim-stage-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $staging | Out-Null

    try {
        # tar.exe (bsdtar) ships in System32 on Windows 10 1803+ and handles
        # zip. Preferred because Expand-Archive is often unavailable under
        # constrained-language-mode PowerShell on locked-down builds.
        $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
        if (Test-Path $tar) {
            & $tar -xf $ZipPath -C $staging
            if ($LASTEXITCODE -ne 0) { throw "tar.exe exited with $LASTEXITCODE extracting $Label" }
        } else {
            Expand-Archive -Path $ZipPath -DestinationPath $staging -Force
        }

        $payload = $staging
        if ($StripTopLevel) {
            # Locate the folder rather than assuming its name; upstream has
            # renamed it between releases.
            $top = Get-ChildItem $staging -Directory | Select-Object -First 1
            if (-not $top) { throw "$Label archive contained no top-level directory." }
            $payload = $top.FullName
        }
        if (-not (Test-Path (Join-Path $payload $SentinelRelativePath))) {
            throw "$Label payload is missing $SentinelRelativePath -- the archive is not what was expected."
        }

        if (Test-Path $TargetDir) {
            if (-not (Test-Path (Join-Path $TargetDir $SentinelRelativePath))) {
                throw "$TargetDir exists but has no $SentinelRelativePath, so it is not a previous $Label install. Refusing to delete it."
            }

            # A process running from this directory holds its binary open and no
            # amount of retrying clears that. This check lives here, rather than
            # once up front, precisely because an unchanged bundle is skipped
            # above: having Neovim open must not block a tools or config update
            # that would never have touched the editor's own files.
            #
            # .Path throws on protected system processes, hence the try/catch
            # per process rather than a single Where-Object.
            $inUse = @()
            foreach ($proc in (Get-Process -ErrorAction SilentlyContinue)) {
                $procPath = $null
                try { $procPath = $proc.Path } catch { }
                if ($procPath -and $procPath.StartsWith($TargetDir, [StringComparison]::OrdinalIgnoreCase)) {
                    $inUse += $proc
                }
            }
            if ($inUse.Count -gt 0) {
                $who = ($inUse | ForEach-Object { "$($_.ProcessName) (PID $($_.Id))" }) -join ', '
                throw "Cannot replace the $Label install: $who is running from $TargetDir. Close it and re-run."
            }

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
        Set-Content -Path (Join-Path $TargetDir '.bundle-sha256') -Value $ExpectedSha256 -Encoding ascii
        Write-Ok "$Label installed"
    }
    finally {
        if (Test-Path $staging) { Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Invoke-Preflight {
    <#
        Answers the only question that can actually stop a portable install:
        can an unprivileged user execute a binary from a user-writable
        directory? An app portal, missing admin rights, Intune enrolment and
        Defender do not prevent it. AppLocker and user-mode WDAC do.

        Returns a list of blockers; empty means good to go.
    #>
    $blockers = New-Object System.Collections.ArrayList

    Write-Section 'Preflight: AppLocker'
    try {
        $svc = Get-Service AppIDSvc -ErrorAction Stop
        Write-Info "Application Identity service: $($svc.Status) / $($svc.StartType)"
        # AppLocker rules are inert unless AppIDSvc is running, whatever the policy says.
        if ($svc.Status -ne 'Running') {
            Write-Ok 'not running, so AppLocker cannot be enforcing'
        } else {
            try {
                $policy = [xml](Get-AppLockerPolicy -Effective -ErrorAction Stop).ToXml()
                $enforcing = $false
                foreach ($rc in $policy.AppLockerPolicy.RuleCollection) {
                    Write-Info "$($rc.Type): EnforcementMode=$($rc.EnforcementMode) Rules=$($rc.ChildNodes.Count)"
                    if ($rc.Type -eq 'Exe' -and $rc.EnforcementMode -eq 'Enabled' -and $rc.ChildNodes.Count -gt 0) { $enforcing = $true }
                }
                if ($enforcing) {
                    Write-Fail 'AppLocker is enforcing Exe rules'
                    [void]$blockers.Add('AppLocker Exe enforcement')
                } else {
                    Write-Ok 'no enforcing Exe rules'
                }
            } catch {
                Write-Info "effective policy unreadable: $($_.Exception.Message)"
            }
        }
    } catch {
        Write-Info "AppIDSvc not queryable: $($_.Exception.Message)"
    }

    Write-Section 'Preflight: WDAC code integrity'
    try {
        $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction Stop
        # Kernel-mode enforcement governs driver signing and is irrelevant
        # here. User-mode enforcement is what would block nvim.exe. Conflating
        # the two is the usual false alarm.
        Write-Info "kernel-mode : $($dg.CodeIntegrityPolicyEnforcementStatus)  (0=off 1=audit 2=enforced)"
        Write-Info "user-mode   : $($dg.UsermodeCodeIntegrityPolicyEnforcementStatus)  (0=off 1=audit 2=enforced)"
        if ($dg.UsermodeCodeIntegrityPolicyEnforcementStatus -eq 2) {
            Write-Fail 'user-mode code integrity is ENFORCED'
            [void]$blockers.Add('user-mode WDAC enforcement')
        } else {
            Write-Ok 'user-mode not enforced'
        }
    } catch {
        Write-Info "DeviceGuard not queryable: $($_.Exception.Message)"
    }

    Write-Section 'Preflight: Smart App Control'
    try {
        $ci = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' -ErrorAction Stop
        Write-Info "VerifiedAndReputablePolicyState: $($ci.VerifiedAndReputablePolicyState)  (0=off 1=enforced 2=evaluation)"
        if ($ci.VerifiedAndReputablePolicyState -eq 1) {
            Write-Fail 'Smart App Control enforced; unsigned binaries are blocked'
            [void]$blockers.Add('Smart App Control')
        } else {
            Write-Ok 'not enforced'
        }
    } catch {
        Write-Ok 'absent'
    }

    Write-Section 'Preflight: script execution policy'
    # Governs script FILES only and never blocks nvim.exe. It matters solely
    # for how this script is invoked. The trap: the two Group Policy scopes
    # outrank both -ExecutionPolicy on the command line and
    # Set-ExecutionPolicy -Scope CurrentUser, so neither overrides them.
    $policies = Get-ExecutionPolicy -List
    foreach ($p in $policies) { Write-Info ("{0,-14} {1}" -f $p.Scope, $p.ExecutionPolicy) }
    $byGpo = $policies | Where-Object {
        ($_.Scope -eq 'MachinePolicy' -or $_.Scope -eq 'UserPolicy') -and $_.ExecutionPolicy -ne 'Undefined'
    }
    if ($byGpo) {
        Write-Warn "set by Group Policy ($($byGpo[0].ExecutionPolicy)); -ExecutionPolicy Bypass will NOT override it"
        Write-Info 'if you cannot run this file:  Get-Content .\setup.ps1 -Raw | Invoke-Expression'
    } else {
        Write-Ok 'not enforced by Group Policy'
    }

    Write-Section 'Preflight: live execution test'
    # The decisive check. Everything above is policy inspection; this is empirical.
    $testDir = Join-Path $env:LOCALAPPDATA ('nvim-probe-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        New-Item -ItemType Directory -Force -Path $testDir | Out-Null
        $dst = Join-Path $testDir 'whoami.exe'
        Copy-Item (Join-Path $env:SystemRoot 'System32\whoami.exe') $dst -Force
        $out = (Invoke-Native $dst) | Select-Object -First 1
        if ($script:LastNativeExit -eq 0) {
            Write-Ok "ran an exe from a user-writable path (returned '$out')"
            Write-Info 'whoami.exe is Microsoft-signed, so a publisher-based AppLocker rule'
            Write-Info 'could allow this yet still block nvim.exe. Unlikely if the above is clean.'
        } else {
            Write-Fail "execution blocked (exit $($script:LastNativeExit))"
            [void]$blockers.Add('execution from a user-writable path is blocked')
        }
    } catch {
        Write-Fail "execution blocked: $($_.Exception.Message)"
        [void]$blockers.Add('execution from a user-writable path is blocked')
    } finally {
        if (Test-Path $testDir) { Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    Write-Section 'Preflight: toolchain'
    foreach ($t in 'git', 'python', 'py', 'node', 'wsl') {
        $c = Get-Command $t -ErrorAction SilentlyContinue
        if ($c) { Write-Ok ("{0,-8} {1}" -f $t, $c.Source) } else { Write-Info ("{0,-8} absent" -f $t) }
    }

    return $blockers
}

function Set-ConfigLink {
    <#
        Neovim only reads config from stdpath('config'), a fixed location. A
        directory junction from there to nvim/ in this repo keeps the config
        under version control while leaving Neovim able to find it.

        A junction rather than a symbolic link because Windows permits
        junctions without admin rights or Developer Mode, neither of which a
        locked-down build grants. Junctions are same-volume only, which is fine
        as both paths sit on the system drive.
    #>
    if (-not (Test-Path $configSrc)) {
        throw "No nvim/ directory at $configSrc. Are you running this from the repo root?"
    }

    if (Test-Path $configLink) {
        $existing = Get-Item $configLink -Force
        $isLink = [bool]($existing.Attributes -band [IO.FileAttributes]::ReparsePoint)

        if ($isLink) {
            $target = $existing.Target
            if ($target -and (($target -eq $configSrc) -or ($target -contains $configSrc))) {
                Write-Skip "already linked to $configSrc"
                return
            }
            Write-Info "relinking (currently points at $target)"
            Remove-Item -LiteralPath $configLink -Force
        }
        elseif ($Force) {
            $backup = "$configLink.replaced-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
            Move-Item -LiteralPath $configLink -Destination $backup
            Write-Warn "existing config moved to $backup (renamed, not deleted)"
        }
        else {
            throw "$configLink is a real directory holding a config that is not part of this repo.`nRe-run with -Force to move it aside (it will be renamed, not deleted)."
        }
    }

    New-Item -ItemType Junction -Path $configLink -Target $configSrc | Out-Null
    Write-Ok "linked $configLink -> $configSrc"
}

function Install-PythonTooling {
    <#
        Three things, all from pip, none needing a compiler or system Node:

          basedpyright  Python language server. Pulls nodejs-wheel-binaries, so
                        it ships its own Node.
          ruff          Python linting and formatting. A Rust binary shipped as
                        a wheel.
          ziglang       A complete C compiler, as a wheel. This is what lets
                        treesitter build parsers on a machine with no build
                        tools at all -- `zig cc` stands in for gcc/clang.

        pip --user installs console scripts into a directory that is not on
        PATH by default, so that directory is added here. Without it the
        language server is installed but invisible to Neovim. ziglang is
        different again: its zig.exe sits inside the package directory rather
        than in Scripts, so that path is located and added separately.
    #>
    $py = Get-Command python -ErrorAction SilentlyContinue
    if (-not $py) { $py = Get-Command py -ErrorAction SilentlyContinue }
    if (-not $py) {
        Write-Warn 'no python found; skipping. Install Python, then re-run.'
        return
    }
    Write-Info "using $($py.Source)"

    $packages = @('basedpyright', 'ruff', 'ziglang')

    # --user fails inside an active virtualenv, so fall back without it.
    $out = Invoke-Native $py.Source (@('-m', 'pip', 'install', '--user', '--quiet',
        '--disable-pip-version-check') + $packages)
    if ($script:LastNativeExit -ne 0) {
        Write-Info 'retrying without --user'
        $out = Invoke-Native $py.Source (@('-m', 'pip', 'install', '--quiet',
            '--disable-pip-version-check') + $packages)
    }
    if ($script:LastNativeExit -ne 0) {
        Write-Warn 'pip install failed; the Python LSP and treesitter compiler stay unavailable'
        $out | Select-Object -Last 6 | ForEach-Object { Write-Info "  $_" }
        Write-Info 'if PyPI is unreachable from this machine, that is the blocker, not the config'
        return
    }
    Write-Ok ($packages -join ', ')

    # Ask Python where its user-scope console scripts went rather than guessing
    # at a version-numbered path.
    $scriptsDir = (Invoke-Native $py.Source @('-c',
        "import sysconfig; print(sysconfig.get_path('scripts', scheme='nt_user'))")) | Select-Object -First 1
    if ($scriptsDir -and (Test-Path $scriptsDir)) {
        Add-UserPathEntries -Entries @($scriptsDir) | Out-Null
    } else {
        Write-Info "could not determine the pip user scripts directory (got '$scriptsDir')"
    }

    # ziglang's zig.exe lives inside the package directory, not in Scripts, so
    # it needs its own PATH entry. This is what gives treesitter a C compiler
    # on a machine with no build tools installed.
    $zigDir = (Invoke-Native $py.Source @('-c',
        "import ziglang, pathlib; print(pathlib.Path(ziglang.__file__).parent)")) | Select-Object -First 1
    if ($zigDir -and (Test-Path (Join-Path $zigDir 'zig.exe'))) {
        Add-UserPathEntries -Entries @($zigDir) | Out-Null
    } else {
        Write-Warn 'zig.exe not located; treesitter will not be able to build parsers'
    }

    foreach ($exe in 'basedpyright-langserver', 'ruff', 'zig') {
        $found = Get-Command $exe -ErrorAction SilentlyContinue
        if ($found) { Write-Ok ("{0,-24} {1}" -f $exe, $found.Source) }
        else { Write-Warn ("{0,-24} installed but not resolvable; open a new terminal" -f $exe) }
    }
}

function Update-Plugins {
    <#
        Brings plugins to exactly the commits in nvim/lazy-lock.json.

        install adds anything missing (a no-op once present); restore then pins
        every plugin to the lockfile. Deliberately not `sync`, which would
        update plugins to their branch tips and move them off the pinned
        commits.
    #>
    if (-not (Test-Path $nvimExe)) {
        Write-Warn 'Neovim not installed; skipping'
        return
    }
    $out = Invoke-Native $nvimExe @('--headless', '+Lazy! install', '+Lazy! restore', '+qall')
    $errors = $out | Select-String -Pattern '^E\d+:|Error' | Select-Object -First 5
    if ($errors) {
        Write-Warn 'plugin sync reported errors:'
        $errors | ForEach-Object { Write-Info "  $_" }
        Write-Info 'plugin installs need git and access to github.com'
    }

    $lazyDir = Join-Path $env:LOCALAPPDATA 'nvim-data\lazy'
    if (Test-Path $lazyDir) {
        $count = (Get-ChildItem $lazyDir -Directory).Count
        Write-Ok "$count plugin directories present"
    } else {
        Write-Warn 'no plugins installed'
    }
}

Write-Host ''
Write-Host 'nvim-portable setup' -ForegroundColor White
Write-Host "  repo         : $scriptDir"
Write-Host "  install root : $InstallRoot"

if ($Update) {
    Write-Section 'Updating the repo'
    Push-Location $scriptDir
    try {
        $out = Invoke-Native 'git' @('pull', '--ff-only')
        $out | ForEach-Object { Write-Info $_ }
        if ($script:LastNativeExit -ne 0) {
            Write-Warn 'git pull failed; continuing with the working tree as it is'
        }
    } finally { Pop-Location }
}

$blockers = Invoke-Preflight

if ($blockers.Count -gt 0) {
    Write-Host ''
    Write-Host ('-' * 62)
    Write-Fail 'Blockers found:'
    foreach ($b in $blockers) { Write-Host "     - $b" -ForegroundColor Red }
    Write-Host ''
    Write-Host '  Options, least friction first:'
    Write-Host '    1. Check WSL. Linux binaries are outside Windows AppLocker entirely.'
    Write-Host '    2. Ask IT for a path exception. You are classed as a developer, and'
    Write-Host '       this policy also breaks pip console scripts and Python venvs, so'
    Write-Host '       an approved writable path very likely already exists.'
    Write-Host '    3. Run Neovim on a remote Linux host over SSH.'
    Write-Host ('-' * 62)
    if (-not $CheckOnly -and -not $Force) {
        throw 'Refusing to install into a blocked environment. Re-run with -Force to try anyway.'
    }
}

if ($CheckOnly) {
    Write-Host ''
    if ($blockers.Count -eq 0) {
        Write-Host 'VERDICT: this machine should run portable Neovim. Re-run without -CheckOnly.' -ForegroundColor Green
    }
    return
}

Write-Section 'Installing Neovim'
Install-Bundle -ZipPath $nvimZip -TargetDir $nvimDir -ExpectedSha256 $ExpectedNvimSha256 `
    -Label 'neovim' -SentinelRelativePath 'bin\nvim.exe' -StripTopLevel

# --clean bypasses every config file, so a broken or unrelated config cannot
# mask a genuine execution failure. This is also the real test of whether the
# machine permits execution from a user-writable path.
$version = (Invoke-Native $nvimExe @('--version')) | Select-Object -First 1
$null = Invoke-Native $nvimExe @('--clean', '--headless', '+qall')
if ($script:LastNativeExit -ne 0) {
    Write-Fail 'the binary extracted but will not run'
    Write-Info 'if the error mentions a system administrator or a policy, this'
    Write-Info 'machine enforces AppLocker or user-mode WDAC.'
    throw "nvim --clean exited with $($script:LastNativeExit)"
}
Write-Ok "$version runs"

if ($SkipTools) {
    Write-Section 'External tools'
    Write-Skip 'skipped by request'
} else {
    Write-Section 'Installing external tools'
    Install-Bundle -ZipPath $toolsZip -TargetDir $toolsDir -ExpectedSha256 $ExpectedToolsSha256 `
        -Label 'tools' -SentinelRelativePath 'bin\rg.exe'

    $bundled = [ordered]@{
        'rg'                  = Join-Path $toolsDir 'bin\rg.exe'
        'fd'                  = Join-Path $toolsDir 'bin\fd.exe'
        'rust-analyzer'       = Join-Path $toolsDir 'bin\rust-analyzer.exe'
        'tree-sitter'         = Join-Path $toolsDir 'bin\tree-sitter.exe'
        'lua-language-server' = Join-Path $toolsDir 'lua-language-server\bin\lua-language-server.exe'
    }
    # Verify by absolute path. Get-Command alone would pass on a machine that
    # already has its own rg on PATH, reporting success without ever
    # exercising the bundle.
    foreach ($name in $bundled.Keys) {
        $exe = $bundled[$name]
        if (-not (Test-Path $exe)) { Write-Warn ("{0,-20} missing from the bundle" -f $name); continue }
        # Some exit non-zero on --version, so judge by output, not exit code.
        $out = (Invoke-Native $exe @('--version')) | Select-Object -First 1
        if ($out) { Write-Ok ("{0,-20} {1}" -f $name, $out) }
        else { Write-Warn ("{0,-20} present but produced no output" -f $name) }
    }
}

Write-Section 'PATH'
$pathEntries = @(Join-Path $nvimDir 'bin')
if (-not $SkipTools) {
    $pathEntries += Join-Path $toolsDir 'bin'
    $pathEntries += Join-Path $toolsDir 'lua-language-server\bin'
}
if ((Add-UserPathEntries -Entries $pathEntries).Count -eq 0 -and -not $SkipPath) {
    Write-Skip 'all entries already present'
}

Write-Section 'Linking config'
Set-ConfigLink

if ($SkipPython) {
    Write-Section 'Python tooling'
    Write-Skip 'skipped by request'
} else {
    Write-Section 'Python tooling (basedpyright, ruff)'
    Install-PythonTooling
}

if ($SkipPlugins) {
    Write-Section 'Plugins'
    Write-Skip 'skipped by request; Neovim will install them on first launch'
} else {
    Write-Section 'Plugins (installing and pinning to lazy-lock.json)'
    Update-Plugins
}

Write-Host ''
Write-Host ('-' * 62)
Write-Host 'Done.' -ForegroundColor Green
Write-Host "  neovim : $nvimExe"
if (-not $SkipTools) { Write-Host "  tools  : $toolsDir" }
Write-Host "  config : $configLink -> $configSrc"
Write-Host ''
Write-Host '  Open a NEW terminal (for PATH) and run:  nvim'
Write-Host '  Later, to update:                       .\setup.ps1 -Update'
Write-Host ('-' * 62)
