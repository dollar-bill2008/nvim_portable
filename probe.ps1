<#
.SYNOPSIS
    Reports whether this machine will permit a portable Neovim install.

.DESCRIPTION
    Run this first on a new, locked-down machine. It answers one question:
    can an unprivileged user run an executable from a user-writable directory?

    That is the only thing that can actually stop a portable Neovim install.
    An app portal, missing admin rights, Intune enrolment and Defender do not
    block it. AppLocker and user-mode WDAC do.

    Read-only: makes no lasting change. The execution test copies a Microsoft
    signed system binary into a temp directory, runs it, and deletes it.

.EXAMPLE
    .\probe.ps1
#>
[CmdletBinding()]
param()

function Write-Section { param([string] $Title) Write-Host ''; Write-Host "== $Title" -ForegroundColor Cyan }
function Write-Pass { param([string] $Message) Write-Host "   PASS  $Message" -ForegroundColor Green }
function Write-Fail { param([string] $Message) Write-Host "   FAIL  $Message" -ForegroundColor Red }
function Write-Info { param([string] $Message) Write-Host "   info  $Message" -ForegroundColor Gray }

$blockers = New-Object System.Collections.ArrayList

Write-Section 'AppLocker'
try {
    $svc = Get-Service AppIDSvc -ErrorAction Stop
    Write-Info "Application Identity service: $($svc.Status) / $($svc.StartType)"
    # AppLocker rules are inert unless AppIDSvc is running, regardless of policy.
    if ($svc.Status -ne 'Running') {
        Write-Pass 'AppIDSvc not running, so AppLocker cannot be enforcing'
    } else {
        try {
            $policy = [xml](Get-AppLockerPolicy -Effective -ErrorAction Stop).ToXml()
            $enforced = $false
            foreach ($rc in $policy.AppLockerPolicy.RuleCollection) {
                Write-Info "$($rc.Type): EnforcementMode=$($rc.EnforcementMode) Rules=$($rc.ChildNodes.Count)"
                if ($rc.Type -eq 'Exe' -and $rc.EnforcementMode -eq 'Enabled' -and $rc.ChildNodes.Count -gt 0) { $enforced = $true }
            }
            if ($enforced) {
                Write-Fail 'AppLocker is enforcing Exe rules'
                [void]$blockers.Add('AppLocker Exe enforcement')
            } else {
                Write-Pass 'no enforcing AppLocker Exe rules'
            }
        } catch {
            Write-Info "could not read effective policy: $($_.Exception.Message)"
        }
    }
} catch {
    Write-Info "AppIDSvc not queryable: $($_.Exception.Message)"
}

Write-Section 'WDAC / Device Guard code integrity'
try {
    $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction Stop
    # Kernel-mode enforcement only governs drivers and is irrelevant here.
    # User-mode enforcement is what would block nvim.exe.
    Write-Info "kernel-mode CI : $($dg.CodeIntegrityPolicyEnforcementStatus)  (0=off 1=audit 2=enforced)"
    Write-Info "user-mode   CI : $($dg.UsermodeCodeIntegrityPolicyEnforcementStatus)  (0=off 1=audit 2=enforced)"
    if ($dg.UsermodeCodeIntegrityPolicyEnforcementStatus -eq 2) {
        Write-Fail 'user-mode code integrity is ENFORCED'
        [void]$blockers.Add('user-mode WDAC enforcement')
    } else {
        Write-Pass 'user-mode code integrity not enforced'
    }
} catch {
    Write-Info "DeviceGuard not queryable: $($_.Exception.Message)"
}

Write-Section 'Smart App Control'
try {
    $ci = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' -ErrorAction Stop
    Write-Info "VerifiedAndReputablePolicyState: $($ci.VerifiedAndReputablePolicyState)  (0=off 1=enforced 2=evaluation)"
    if ($ci.VerifiedAndReputablePolicyState -eq 1) {
        Write-Fail 'Smart App Control is enforced; unsigned or low-reputation binaries are blocked'
        [void]$blockers.Add('Smart App Control')
    } else {
        Write-Pass 'Smart App Control not enforced'
    }
} catch {
    Write-Pass 'Smart App Control absent'
}

Write-Section 'PowerShell language mode'
# Constrained language mode does not stop nvim.exe running, but it does break
# Expand-Archive and much of install.ps1, so it changes how you install.
$mode = $ExecutionContext.SessionState.LanguageMode
Write-Info "language mode: $mode"
if ($mode -ne 'FullLanguage') {
    Write-Fail "constrained PowerShell; install.ps1 may not run. Extract manually with tar.exe instead."
    [void]$blockers.Add('constrained PowerShell language mode')
} else {
    Write-Pass 'full language mode'
}

Write-Section 'Live execution test from a user-writable directory'
# The decisive check. Everything above is policy inspection; this is empirical.
$testDir = Join-Path $env:LOCALAPPDATA ('nvim-probe-' + [System.Guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    New-Item -ItemType Directory -Force -Path $testDir | Out-Null
    $src = Join-Path $env:SystemRoot 'System32\whoami.exe'
    $dst = Join-Path $testDir 'whoami.exe'
    Copy-Item $src $dst -Force
    Write-Info "copied whoami.exe to $testDir"
    $out = & $dst 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Pass "executed from a user-writable path (returned '$out')"
        Write-Info 'note: whoami.exe is Microsoft-signed. A publisher-based AppLocker'
        Write-Info 'rule could allow this yet still block nvim.exe. If the policy'
        Write-Info 'checks above were clean, that is unlikely.'
    } else {
        Write-Fail "execution blocked (exit code $LASTEXITCODE)"
        [void]$blockers.Add('execution from user-writable path blocked')
    }
} catch {
    Write-Fail "execution blocked: $($_.Exception.Message)"
    [void]$blockers.Add('execution from user-writable path blocked')
} finally {
    if (Test-Path $testDir) { Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Section 'Toolchain available for later config work'
$tools = [ordered]@{
    'git'    = 'required: plugin manager clones plugins with it'
    'python' = 'required: pip installs the Python language servers'
    'node'   = 'optional: many Mason-installed language servers need it'
    'cc'     = 'optional: compiles treesitter parsers'
    'gcc'    = 'optional: compiles treesitter parsers'
    'zig'    = 'optional: pip install ziglang provides this if absent'
    'rg'     = 'optional: fast fuzzy-find backend'
    'wsl'    = 'fallback: Linux nvim is not subject to Windows AppLocker'
}
foreach ($t in $tools.Keys) {
    $found = Get-Command $t -ErrorAction SilentlyContinue
    if ($found) { Write-Pass ("{0,-7} {1}" -f $t, $found.Source) }
    else { Write-Info ("{0,-7} absent -- {1}" -f $t, $tools[$t]) }
}

Write-Section 'Network reachability'
foreach ($host_ in @('github.com', 'pypi.org')) {
    try {
        $r = Invoke-WebRequest -Uri "https://$host_" -UseBasicParsing -TimeoutSec 15 -Method Head
        Write-Pass "$host_ reachable (HTTP $($r.StatusCode))"
    } catch {
        Write-Info "$host_ not directly reachable: $($_.Exception.Message)"
    }
}

Write-Host ''
Write-Host ('-' * 60)
if ($blockers.Count -eq 0) {
    Write-Host 'VERDICT: portable Neovim should install and run. Run install.ps1.' -ForegroundColor Green
} else {
    Write-Host 'VERDICT: blockers found.' -ForegroundColor Red
    foreach ($b in $blockers) { Write-Host "  - $b" -ForegroundColor Red }
    Write-Host ''
    Write-Host 'Options, in order of least friction:'
    Write-Host '  1. Check WSL. Linux binaries are outside Windows AppLocker entirely.'
    Write-Host '  2. Ask IT for a path exception. You are classed as a developer and'
    Write-Host '     this policy also breaks pip console scripts and Python venvs,'
    Write-Host '     so there is very likely an approved writable path already.'
    Write-Host '  3. Run nvim on a remote Linux host over SSH.'
}
Write-Host ('-' * 60)
