# nvim-portable

Self-contained portable Neovim for locked-down corporate Windows machines.
Clone the repo, run one script, get a working `nvim`. No admin rights, no MSI,
no app portal, no network access beyond reaching this git remote.

Neovim **v0.12.4**, `nvim-win64.zip`, SHA256
`9fc3572829ffd13debb6e32555da2c8cc02555568260a9fc4cf1f65bbcca319c`.

## Why the zip is committed

The one capability confirmed available on the target machine is `git clone`.
Bundling the 12 MB release zip in the repo means the install depends on
nothing else -- not GitHub Releases, not raw HTTPS, not a package manager, not
a proxy exception. One `git clone` delivers both the editor and the config.

12 MB is comfortably under GitHub's 100 MB per-file limit, so no Git LFS.

## Usage on a new machine

```powershell
git clone https://github.com/dollar-bill2008/nvim_portable.git $env:USERPROFILE\nvim-portable
cd $env:USERPROFILE\nvim-portable
.\probe.ps1      # will this machine allow it?
.\install.ps1    # install it
```

### Authenticating the clone

This repo is **private**, owned by the `dollar-bill2008` GitHub account, so the
clone needs credentials. That is the one external dependency in the whole
plan -- worth sorting out early on a new machine rather than at the point of
use.

If the GitHub CLI is available:

```powershell
gh auth login
gh repo clone dollar-bill2008/nvim_portable $env:USERPROFILE\nvim-portable
```

**If `gh` holds more than one account**, the *active* one is used, and a push
or a clone of a private repo will fail against an account that cannot see it.
Check with `gh auth status`, and either switch:

```powershell
gh auth switch --user dollar-bill2008
```

or override the credential helper for a single command without changing the
active account:

```powershell
git -c credential.helper= -c credential.helper='!gh auth git-credential' push
```

If `gh` is not installed, use a fine-grained personal access token scoped to
this repository with `Contents: Read` and clone over HTTPS.

### If github.com is blocked entirely

Nothing here depends on GitHub specifically. Push the repo to whatever git
host the network does allow -- Azure DevOps, GitHub Enterprise, Bitbucket, an
internal GitLab -- and clone from there. The repo is self-contained, so any
git remote reachable from the target machine works identically.

Open a new terminal, then:

```powershell
nvim --version
```

If PowerShell refuses to run the scripts, they are unsigned local files:

```powershell
powershell -ExecutionPolicy Bypass -File .\probe.ps1
```

That flag is per-process and needs no admin rights.

## What each script does

### `probe.ps1`

Read-only. Answers the only question that matters on a hardened build: **can
an unprivileged user execute a binary from a user-writable directory?**

It checks AppLocker (including whether `AppIDSvc` is even running, since the
rules are inert if it is not), user-mode WDAC code integrity, Smart App
Control, and the PowerShell language mode -- then performs a live execution
test by copying a signed system binary into `%LOCALAPPDATA%` and running it.
It also inventories the toolchain and checks network reachability.

Ends with a verdict and, if blocked, a ranked list of fallbacks.

### `install.ps1`

Clears the mark-of-the-web from the zip, verifies its SHA256, extracts via
`tar.exe` from System32 (preferred over `Expand-Archive`, which constrained
language mode often breaks), installs to
`%LOCALAPPDATA%\Programs\nvim-portable`, adds `bin` to the user-scope PATH,
and verifies the binary runs with `--clean`.

Extraction goes to a staging directory first, so a blocked or interrupted run
never leaves a half-installed tree. It refuses to delete a target directory
that does not already look like one of its own installs.

Useful switches:

| Switch | Effect |
| --- | --- |
| `-InstallRoot <path>` | Install somewhere other than `%LOCALAPPDATA%\Programs` |
| `-SkipPath` | Leave the user PATH alone |
| `-SkipHashCheck` | Skip zip verification |

## What actually blocks a portable install

Not the app portal. Not the absence of admin rights. Not Intune enrolment or
Defender. Only two things:

- **AppLocker** with enforced Exe rules
- **User-mode WDAC** code integrity enforcement

Both are uncommon on developer-classed accounts, because they also break pip
console scripts (`.exe` shims in `%APPDATA%\Python\...\Scripts`), Python
virtualenvs (`python.exe` inside the project), VS Code (`%LOCALAPPDATA%\
Programs\Microsoft VS Code`) and every VS Code extension that ships a language
server. A machine that enforces them against a developer has bigger problems
than Neovim.

Note that WDAC **kernel-mode** enforcement is common and irrelevant -- it
governs driver signing. `probe.ps1` reports the two separately for this
reason.

If blocked, in order of least friction: check WSL (Linux binaries are entirely
outside Windows AppLocker), ask IT for a path exception, or run Neovim on a
remote Linux host over SSH.

## Config

Deliberately not included yet. The plan is to confirm a bare Neovim installs
and runs on the target machine first, then add configuration as a second
layer in `nvim/`.

To keep a new config isolated from an existing one at `%LOCALAPPDATA%\nvim`,
use `NVIM_APPNAME`:

```powershell
$env:NVIM_APPNAME = 'nvim-portable'   # reads %LOCALAPPDATA%\nvim-portable
nvim
```

## Known limitations on a hardened machine

- **Treesitter** compiles parsers with a C compiler. Neovim 0.12 bundles
  `c`, `lua`, `vim`, `vimdoc`, `query` and `markdown`, so the basics work
  unaided. For anything else without a compiler, `pip install ziglang` gives
  a working C compiler through pip alone.
- **Mason** language servers mostly want Node. For Python specifically,
  `ruff` and `jedi-language-server` are pure pip and need no Node.
- **Telescope** wants `ripgrep` / `fd`; both are single portable exes subject
  to the same execution question as Neovim itself.
- **Plugin installs** shell out to `git`, so they inherit its proxy and CA
  configuration. If `git clone` works, plugin sync works. `pip` and `npm`
  need their own CA settings behind a TLS-inspecting proxy.
