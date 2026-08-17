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
.\setup.ps1
```

Then open a new terminal and run `nvim`. That is the whole install.

To find out whether a machine will allow any of this before changing anything:

```powershell
.\setup.ps1 -CheckOnly
```

To update later, after config or tool versions change upstream:

```powershell
.\setup.ps1 -Update
```

`-Update` pulls the repo, then re-applies everything. Every phase is
idempotent, so an unchanged bundle is skipped and a re-run costs a couple of
seconds. It is the same command whether you are installing from nothing or
applying a change.

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

### "running scripts is disabled on this system"

That is PowerShell's execution policy, which governs script **files**. It never
blocks `nvim.exe` -- it only decides how you invoke `setup.ps1`. Work down this
ladder.

**1. Per-command, no persistence, no admin:**

```powershell
powershell -ExecutionPolicy Bypass -File .\setup.ps1
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
Get-Content .\setup.ps1 -Raw | Invoke-Expression
```

This is not a bypass of anything security-relevant -- it is the documented
boundary of what execution policy covers. Execution policy is not a security
control; it prevents accidental script execution, which is why Microsoft
places no trust boundary there.

`setup.ps1` reports all of this in its preflight, including whether Group
Policy is involved.

## The two scripts

### `setup.ps1`

The only script you run. Five phases, each idempotent:

| Phase | What it does |
| --- | --- |
| **Preflight** | Can this machine execute a binary from a user-writable path? |
| **Install** | Extract Neovim and the bundled tools; add three PATH entries |
| **Link** | Junction `%LOCALAPPDATA%\nvim` to `nvim/` in this repo |
| **Python** | `pip install basedpyright ruff`, and put pip's script dir on PATH |
| **Plugins** | `Lazy! install` then `Lazy! restore`, pinning to the lockfile |

Preflight checks AppLocker (including whether `AppIDSvc` is even running, since
the rules are inert if it is not), user-mode versus kernel-mode WDAC, Smart App
Control and the execution policy scopes, then performs a live execution test by
copying a signed system binary into `%LOCALAPPDATA%` and running it. If it
finds a blocker it refuses to install and prints ranked fallbacks.

Each bundle records its SHA256 in a `.bundle-sha256` marker on success. On
re-run a matching marker means the extraction is skipped entirely, which is
what makes this cheap to run repeatedly. Extraction stages to a temp directory
first, so a blocked or interrupted run never leaves a half-installed tree, and
it refuses to delete a target that does not carry the expected sentinel file.

Plugins use `install` then `restore`, never `sync` -- `sync` would update
plugins to their branch tips and move them off the pinned commits.

| Switch | Effect |
| --- | --- |
| `-CheckOnly` | Run preflight and stop. Changes nothing |
| `-Update` | `git pull` first, then apply everything |
| `-InstallRoot <path>` | Install somewhere other than `%LOCALAPPDATA%\Programs` |
| `-Force` | Re-extract unchanged bundles; replace a real config directory (renamed, never deleted) |
| `-SkipTools` | No rg, fd, rust-analyzer, lua-language-server |
| `-SkipPython` | No pip install |
| `-SkipPlugins` | Leave plugins for Neovim to install on first launch |
| `-SkipPath` | Leave the user PATH alone |
| `-SkipHashCheck` | Skip bundle verification |

### `fetch-tools.ps1`

Maintenance only -- you never need it to install. It rebuilds
`tools/nvim-tools.zip` from pinned upstream releases, normalising four
different archive layouts into one tree, and records each source URL, version
and SHA256 in `tools/manifest.json`.

To update a bundled tool: edit its pinned version here, run it, copy the new
hash into `$ExpectedToolsSha256` in `setup.ps1`, commit the rebuilt zip.

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
governs driver signing. `setup.ps1` reports the two separately for this reason,
because conflating them is the usual false alarm.

If blocked, in order of least friction: check WSL (Linux binaries are entirely
outside Windows AppLocker), ask IT for a path exception, or run Neovim on a
remote Linux host over SSH.

## Config

Lives in `nvim/`, linked into `%LOCALAPPDATA%\nvim` by `setup.ps1` using a
**directory junction**. Junctions are used rather than symbolic links
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
  lua/config/lsp.lua        language servers, diagnostics, LSP keymaps
  lua/plugins/blink-cmp.lua   completion
  lua/plugins/colorscheme.lua theme
  lua/plugins/lualine.lua     statusline
  lua/plugins/neo-tree.lua    file browser
  lua/plugins/telescope.lua   fuzzy finder
  lua/plugins/treesitter.lua  syntax highlighting
```

`init.lua` requires `config.lsp` **after** `config.lazy`, and that order is
load-bearing: `config.lsp` asks blink.cmp for its completion capabilities, and
those must be advertised before any language server client starts. Swap the two
and you silently lose snippet support and rich documentation from every server.

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
| `<leader>w` / `<leader>W` | Save file / save all |
| `<leader>q` / `<leader>Q` | Quit / force quit discarding changes |
| `<leader>x` / `<leader>X` | Save and quit / save and quit all |
| `<leader>v` / `<leader>s` | Split vertically / horizontally |
| `<S-h/j/k/l>` | Move between splits |
| `<S-Left/Down/Up/Right>` | Move between splits |
| `<C-h/j/k/l>` | Move between splits (second route) |
| `<leader>j` | Join line below, keeping cursor position |
| `gd` / `gD` | Go to definition / declaration |
| `<leader>k` | Hover documentation |
| `<leader>lf` | Format buffer (Python always via ruff) |
| `<leader>ll` | Diagnostics to location list |
| `<leader>ls` | `:LspServers` -- what is running, what is missing |
| `<leader>d` | Diagnostics for the current line, floating |

#### What the Shift split-navigation costs

In Vim's notation `<S-h>` **is** the key `H` -- there is no separate shift-h to
bind. So those four mappings shadow four default normal-mode commands:

| Shadowed | Was | Now reachable via |
| --- | --- | --- |
| `H` | Jump to top line of window | `gg`, or `<C-u>` |
| `J` | Join line below | `<leader>j` |
| `K` | **LSP hover documentation** | `<leader>k` |
| `L` | Jump to bottom line of window | `G`, or `<C-d>` |

`J` and `K` are rehomed because both are worth keeping -- losing hover
documentation would remove one of the main reasons to run a language server.
`H` and `L` are simply given up; they are cheap to live without, and `<C-h>` /
`<C-l>` are bound to the same splits if you would rather delete the `<S-h>` and
`<S-l>` lines and get them back.

Visual-mode `J` and `K` are untouched and still move the selected lines up and
down -- the split navigation is normal mode only.

Neovim 0.11+ already ships LSP defaults, and the rest are not re-bound here:

| Key | Action |
| --- | --- |
| `grn` | Rename symbol |
| `gra` | Code action |
| `grr` | References |
| `gri` | Implementation |
| `grt` | Type definition |
| `gO` | Document symbols |
| `[d` / `]d` | Previous / next diagnostic |
| `<C-s>` (insert) | Signature help |

Note that `K` is **not** in the list above: it is shadowed by split navigation,
which is why hover lives on `<leader>k`.

Completion, via blink.cmp:

| Key | Action |
| --- | --- |
| `<C-space>` | Open menu / show documentation |
| `<C-n>` / `<C-p>` | Next / previous item |
| `<C-y>` | Accept |
| `<C-e>` | Dismiss |
| `<Tab>` | Next snippet placeholder |

`<CR>` deliberately does **not** accept a completion, so pressing Enter still
inserts a newline rather than a suggestion you did not want.

### Language support

| Language | Server | Provides |
| --- | --- | --- |
| Python | `basedpyright` | Types, completion, go-to-definition, hover |
| Python | `ruff` | Linting and formatting |
| Rust | `rust-analyzer` | Completion, hover, go-to-definition |
| Lua | `lua-language-server` | Completion and diagnostics, aware of the `vim` API |

Both Python servers attach at once, deliberately -- ruff catches lint and style,
basedpyright catches type errors. Verified complementary rather than duplicate:
on a file with two unused imports and a type error, ruff reports the imports and
basedpyright reports `Operator "+" not supported for types "int" and
"Literal['...']"`. Because both attach, `<leader>lf` pins Python formatting to
ruff rather than prompting you to choose every time.

Three design decisions worth knowing:

**No Mason.** It downloads language servers at runtime, which is the single
component most likely to be blocked on a hardened build. Servers here are
either bundled in the repo or installed from pip.

**No nvim-lspconfig.** Neovim 0.11 added `vim.lsp.config()` and
`vim.lsp.enable()`, so four servers are about ten lines each in
`lua/config/lsp.lua`. One less plugin, and the definitions are readable.

**Every server is optional.** Each is enabled only if its binary resolves, so
the same config works on a fully equipped machine and on one with nothing but
Neovim -- a missing server is simply absent, not an error at startup. Run
`:LspServers` to see what is active, what is missing, and which binary each one
resolved to.

Bundled binaries are preferred over bare names on PATH, and that ordering
matters: on a machine with rustup installed, `~/.cargo/bin/rust-analyzer.exe`
is a *proxy shim* that exists, satisfies `executable()`, and then dies with
`Unknown binary 'rust-analyzer.exe' in official toolchain` when the component
was never installed. Preferring the bundled copy sidesteps that.

Paths are passed through `vim.fs.normalize`. Mixed separators are not cosmetic:
lua-language-server failed to start with `Duplicate channel 'task:1'` until its
path used consistent separators.

Formatting on save is **off**. `<leader>lf` formats on demand. There is a
commented-out autocmd at the end of `lua/config/lsp.lua` if you want it
automatic -- left off because a formatter rewriting a file you did not ask it to
rewrite is a surprise, especially in a shared repo with its own style settings.

### External tools

The design rule is **assume nothing is installed on the target machine**. Every
dependency comes from exactly one of two places: bundled in this repo, or
`pip`. No package manager, no rustup, no system Node, and no preinstalled C
compiler.

Bundled in `tools/nvim-tools.zip`, extracted by `setup.ps1`:

| Tool | Used by | Version |
| --- | --- | --- |
| `rg` (ripgrep) | telescope grep | 15.2.0 |
| `fd` | telescope file listing | 10.4.2 |
| `rust-analyzer` | Rust LSP | 2026-08-17.4 |
| `lua-language-server` | Lua LSP | 3.19.1 |
| `tree-sitter` | generating treesitter parsers | 0.26.12 |

> **rust-analyzer pins rot.** Upstream ships several releases a day and prunes
> the assets of superseded ones, so its download URL 404s within hours while the
> git tag survives. `fetch-tools.ps1` detects this and prints how to find a
> current tag. The committed zip is unaffected -- which is exactly why the
> binary is bundled rather than fetched at install time.

Installed from pip by `setup.ps1`:

| Tool | Used by | Why pip is enough |
| --- | --- | --- |
| `basedpyright` | Python LSP | Ships its own Node via `nodejs-wheel-binaries`, so **no system Node needed** |
| `ruff` | Python lint + format | Rust binary distributed as a wheel |
| `ziglang` | **C compiler** for treesitter parsers | A complete C compiler as a wheel -- `zig cc` stands in for gcc/clang |

That last one is the interesting piece: `pip install ziglang` gives you a real C
compiler on a machine with no build tools whatsoever, which is what makes
treesitter possible here. Its `zig.exe` lives inside the package directory
rather than in `Scripts`, so `setup.ps1` locates and adds that path separately.
Getting treesitter to *use* it takes one more step, described below.

`pip --user` puts console scripts in a directory that is not on PATH by
default, so `setup.ps1` asks Python where they went
(`sysconfig.get_path('scripts', scheme='nt_user')`) and adds it. Without that
the language server is installed but invisible to Neovim.

`tools/manifest.json` records every bundled tool's upstream URL, version and
SHA256. `setup.ps1` verifies the bundle's own SHA256 before extracting, then
verifies each binary by absolute path -- not via `Get-Command`, which would
pass on a machine that happens to have its own `rg` already on PATH and report
success without ever exercising the bundle.

Telescope degrades to slower built-ins if `rg`/`fd` are somehow unavailable
rather than failing. Verify what Neovim can see with `:checkhealth telescope`.

### Syntax highlighting

Treesitter parses each file into a real syntax tree instead of matching regular
expressions, so a function name is highlighted because it *is* a function name.
Neovim 0.12 ships **no** parsers, so each is generated and compiled locally.

That is why the tooling above exists. `nvim-treesitter`'s `main` branch needs:

| Requirement | Source here |
| --- | --- |
| `tree-sitter` CLI ≥ 0.26.1 | bundled -- no PyPI package exists, and upstream says explicitly not to use npm |
| a C compiler | `pip install ziglang` → `zig cc`, reached through a shim |
| `tar` and `curl` | ship with Windows 10+ |

> **`tree-sitter build` does not look for a compiler on PATH.** It compiles
> through Rust's `cc` crate, which on a `*-windows-msvc` host runs `cl.exe` and
> nothing else unless `CC` names an alternative. So a working `zig.exe` sitting
> on PATH still fails with `cl.exe ... Error: program not found`. `CC` takes a
> single executable, and a `CC` of `"zig cc"` loses the `cc` and runs bare zig,
> which just prints its usage. Worse, once the crate sees clang behind a shim it
> appends `--target=x86_64-pc-windows-msvc` -- a valid LLVM triple that zig, which
> parses triples itself, rejects with `UnknownOperatingSystem`.
>
> `lua/config/paths.lua` therefore writes a small batch file to
> `stdpath('data')/nvim-portable/zig-cc.bat` that forwards to `zig cc` and drops
> that flag, and sets `CC` to it. zig then builds for its native target and
> Neovim loads the resulting parsers happily. The shim is rewritten only when
> its content changes, and an existing `CC` in the environment always wins.

Parsers install to `stdpath('data')/site`, not into this repo -- compiled
binaries are derived artifacts. Highlighting is enabled per buffer by a
`FileType` autocmd calling `vim.treesitter.start()`, because the `main` branch
deliberately does not enable features for you. Files over 1 MB are skipped.

If the toolchain is missing, `lua/plugins/treesitter.lua` notifies once and
falls back to the regex engine rather than erroring on every startup.

Add a language by adding it to the `languages` list in that file. `:TSUpdate`
rebuilds parsers after a plugin update -- required, since parser versions are
pinned to plugin versions.

### Theming

`lua/plugins/colorscheme.lua` holds the scheme, currently **Monokai** as in
Sublime Text, via `monokai-pro.nvim`'s `classic` palette. Verified against the
original values: background `#272822`, keywords `#F92672`, strings `#E6DB74`,
functions `#A6E22E`, constants `#AE81FF`.

> **The filter is chosen by the colourscheme NAME, not the `filter` option.**
> The plugin ships one colours file per variant, and the generic
> `colors/monokai-pro.lua` is a single line: `set_filter("pro")`. So
> `colorscheme monokai-pro` applies the Pro palette regardless of what `filter`
> was passed to `setup`. Load `monokai-pro-classic` instead. Variant names are
> listed in the file's header.

To switch scheme entirely: change the repo and the `vim.cmd.colorscheme` call in
that file, restart, then `:Lazy clean` to remove the old plugin.

Treesitter matters for theming: it produces fine-grained groups like
`@function.call` and `@variable.parameter` that a scheme can colour separately.
The regex engine cannot, which is why schemes looked flatter before.

Two tools for tweaking rather than guessing:

| Command | Shows |
| --- | --- |
| `:Inspect` | Treesitter capture, highlight group and colour under the cursor |
| `:InspectTree` | The live syntax tree for the buffer |

The custom `LineNr` / `CursorLineNr` colours in `lua/config/options.lua`
deliberately override whatever the scheme sets, and are re-applied on the
`ColorScheme` event so they survive a scheme change. Verified: they hold at
`#9CC2D6` / `#3A6B84` under Monokai.

Note that those are a cool blue, whereas Monokai's own gutter is a muted warm
grey. If you want the authentic Sublime look, delete the
`line_number_highlights` block near the end of `lua/config/options.lua` and the
scheme's own colours take over.

`lua/plugins/lualine.lua` is the statusline, themed `auto` so it follows the
colourscheme with no separate configuration. It shows git branch, diagnostic
counts, and which language servers are attached to the current buffer.

### Running two configs side by side

`NVIM_APPNAME` changes which config directory Neovim reads, which is the safe
way to try something without disturbing this one:

```powershell
$env:NVIM_APPNAME = 'nvim-test'   # reads %LOCALAPPDATA%\nvim-test
nvim
```

## Known limitations on a hardened machine

- **Treesitter parser builds can fail transiently.** Real-time antivirus locks
  freshly extracted files, which surfaces as `EPERM: operation not permitted`
  while renaming a temp directory. Re-running the install fixes it -- one parser
  hit this during setup here and succeeded on retry. GitHub outages also cause
  silent download stalls; `:TSInstall <lang>` picks those up later. zig's own
  build cache (`%LOCALAPPDATA%\zig`) can also report `CacheCheckFailed` while it
  is populating; deleting that directory is safe and it rebuilds.
- **Mason is deliberately not used.** It downloads language servers at
  runtime, which is the component most likely to be blocked on a hardened
  build. Every server here is either bundled in the repo or comes from pip.
- **rust-analyzer without a Rust toolchain is partial.** It runs and gives
  syntax and completion, but full project analysis needs `cargo` for metadata.
  Install `rustup` (a user-directory install, no admin) if you need that.
- **Plugin installs shell out to `git`**, so they inherit its proxy and CA
  configuration. If `git clone` works, plugin sync works. `pip` needs its own
  CA settings behind a TLS-inspecting proxy.
- **Nerd Font.** Without one in your terminal, file-type icons render as empty
  boxes. Cosmetic only -- set `vim.g.have_nerd_font = false` in
  `nvim/init.lua` for plain-text fallbacks.
