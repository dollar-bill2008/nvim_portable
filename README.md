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
.\probe.ps1        # will this machine allow it?
.\install.ps1      # install the editor
.\link-config.ps1  # point Neovim's config location at nvim/ in this repo
```

Then open a new terminal and run `nvim`. On first launch lazy.nvim clones
itself and installs the plugins pinned in `nvim/lazy-lock.json`, which needs
`git` and network access to github.com. After that, startup is offline.

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

### "running scripts is disabled on this system"

That is PowerShell's execution policy, which governs script **files**. It never
blocks `nvim.exe` -- it only decides how you invoke these two scripts. Work
down this ladder.

**1. Per-command, no persistence, no admin:**

```powershell
powershell -ExecutionPolicy Bypass -File .\probe.ps1
```

**2. Persistent for your user, no admin:**

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

`RemoteSigned` permits unsigned *local* scripts. A `git clone` does not mark
files as downloaded, so cloned scripts run fine under it. Downloading the repo
as a **zip** does mark them, in which case clear it with:

```powershell
Unblock-File .\*.ps1
```

**3. If it is set by Group Policy, neither of the above works.** Execution
policy has a precedence order, and the two Group Policy scopes outrank
anything you can set yourself:

| Scope | Set by |
| --- | --- |
| `MachinePolicy` | Group Policy -- outranks all below |
| `UserPolicy` | Group Policy -- outranks all below |
| `Process` | `-ExecutionPolicy` on the command line |
| `CurrentUser` | `Set-ExecutionPolicy -Scope CurrentUser` |
| `LocalMachine` | machine default |

Check with `Get-ExecutionPolicy -List`. If either policy scope is anything but
`Undefined`, `-ExecutionPolicy Bypass` will silently fail to take effect.

The escape is that the policy applies to script *files*, not to commands. Feed
the script text to PowerShell instead of executing the file:

```powershell
Get-Content .\probe.ps1   -Raw | Invoke-Expression
Get-Content .\install.ps1 -Raw | Invoke-Expression
```

This is not a bypass of anything security-relevant -- it is the documented
boundary of what execution policy covers. Execution policy is not a security
control; it prevents accidental script execution, which is why Microsoft
places no trust boundary there.

`probe.ps1` reports all of this, including whether Group Policy is involved.

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

Lives in `nvim/`, linked into `%LOCALAPPDATA%\nvim` by `link-config.ps1` using
a **directory junction**. Junctions are used rather than symbolic links
because Windows permits them without administrator rights or Developer Mode,
neither of which a locked-down build grants. The consequence: editing
`nvim/init.lua` in this repo edits the live config, with no copy step and no
drift.

```
nvim/
  init.lua                  entry point: leader key, then requires below
  lazy-lock.json            exact plugin commits, committed on purpose
  lua/config/options.lua    editor options
  lua/config/keymaps.lua    non-plugin key mappings
  lua/config/lazy.lua       bootstraps the plugin manager
  lua/plugins/*.lua         one file per plugin, each returning a spec
```

Adding a plugin means adding a file to `lua/plugins/`. There is no central
list to keep in sync -- `lua/config/lazy.lua` imports the whole directory.

`lazy-lock.json` pins every plugin to an exact git commit. Plugins are git
repositories tracked on moving branches, not versioned releases, so without
the lockfile a clone six weeks from now installs whatever each plugin's branch
happens to be that morning. Update deliberately with `:Lazy update`, test,
then commit the changed lockfile; `git revert` plus `:Lazy restore` walks it
back.

### Keymaps

Leader is `<space>`.

| Key | Action |
| --- | --- |
| `<leader>e` | File tree: toggle |
| `<leader>E` | File tree: reveal current file |
| `<leader>ff` | Find files |
| `<leader>fg` | Grep across project |
| `<leader>fb` | Open buffers |
| `<leader>fr` | Recent files |
| `<leader>fk` | Search your own keymaps |
| `<leader>w` / `<leader>q` | Write / quit |
| `<C-h/j/k/l>` | Move between splits |

### External tools the config expects

| Tool | Used by | Source |
| --- | --- | --- |
| `rg` (ripgrep) | telescope grep | `scoop install ripgrep` |
| `fd` | telescope file listing | `scoop install fd` |
| `rust-analyzer` | Rust LSP | `rustup component add rust-analyzer` |
| `ruff` | Python lint/format | `pip install ruff` |

Telescope degrades to slower built-ins without `rg`/`fd` rather than failing.
Verify what Neovim can see with `:checkhealth telescope`.

### Running two configs side by side

`NVIM_APPNAME` changes which config directory Neovim reads, which is the safe
way to try something without disturbing this one:

```powershell
$env:NVIM_APPNAME = 'nvim-test'   # reads %LOCALAPPDATA%\nvim-test
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
