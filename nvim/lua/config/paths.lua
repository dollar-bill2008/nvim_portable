-- Locating the tools this config depends on.
--
-- PATH is not a reliable channel, for three separate reasons:
--
--   1. setup.ps1 writes tool directories into the user PATH, but environment
--      changes only reach processes started afterwards. A terminal or editor
--      opened before setup ran never sees them -- which shows up as
--      "missing a C compiler" even though the compiler is installed.
--   2. A machine may carry its own broken copy of a tool earlier on PATH. On a
--      box with rustup, ~/.cargo/bin/rust-analyzer.exe is a proxy shim that
--      exists, satisfies executable(), then dies with "Unknown binary".
--   3. Nothing guarantees setup.ps1 ran at all.
--
-- So: resolve explicitly first, fall back to PATH, and where a subprocess needs
-- to find the tool itself, put the directory on this session's PATH.
--
-- The C compiler is a further case again, and PATH does nothing for it at all:
-- `tree-sitter build` looks for cl.exe by name and consults CC for anything
-- else. See ensure_c_compiler.

local M = {}

local is_windows = vim.fn.has("win32") == 1
local sep = is_windows and ";" or ":"

--- Directory holding the bundled tools from tools/nvim-tools.zip.
---
--- Derived from the running Neovim binary rather than hardcoded, because
--- setup.ps1 -InstallRoot can relocate both. Neovim lives at
--- <root>/nvim-portable/bin/nvim.exe and the tools at
--- <root>/nvim-portable-tools/.
---
--- Normalised, because fnamemodify returns backslashes on Windows and
--- appending forward slashes yields a mixed-separator path that some tools
--- mishandle -- lua-language-server refused to start over exactly that.
---@return string
function M.tools_root()
    local root = vim.fs.normalize(vim.fn.fnamemodify(vim.v.progpath, ":h:h:h"))
    return root .. "/nvim-portable-tools"
end

--- First candidate that exists and is executable, or nil.
--- List absolute bundled paths before bare names, so a bundled copy wins over
--- whatever the machine happens to have on PATH.
---@param candidates string[]
---@return string|nil
function M.resolve(candidates)
    for _, candidate in ipairs(candidates) do
        if vim.fn.executable(candidate) == 1 then return candidate end
    end
    return nil
end

--- Put a directory on this session's PATH, so subprocesses inherit it.
--- Idempotent and case-insensitive, since Windows paths are.
---@param dir string|nil
---@return boolean added_or_already_present
function M.prepend_to_path(dir)
    if not dir or dir == "" or not vim.uv.fs_stat(dir) then return false end
    local target = vim.fs.normalize(dir):lower()
    for entry in vim.gsplit(vim.env.PATH or "", sep, { plain = true }) do
        if entry ~= "" and vim.fs.normalize(entry):lower() == target then return true end
    end
    vim.env.PATH = dir .. sep .. (vim.env.PATH or "")
    return true
end

--- Absolute path to a zig.exe, or nil.
---
--- PATH first, then ask Python where pip put the ziglang package: its zig.exe
--- sits inside the package directory rather than in Scripts, so it is never on
--- PATH unless setup.ps1 put it there, and a terminal opened before setup.ps1
--- ran has not seen that change.
---@return string|nil
local function find_zig()
    local on_path = vim.fn.exepath("zig")
    if on_path ~= "" then return on_path end

    local python = vim.fn.exepath("python")
    if python == "" then python = vim.fn.exepath("py") end
    if python == "" then return nil end

    local ok, result = pcall(function()
        return vim
            .system({ python, "-c", "import ziglang, pathlib; print(pathlib.Path(ziglang.__file__).parent)" },
                { text = true })
            :wait(10000)
    end)
    if not ok or not result or result.code ~= 0 then return nil end

    local dir = vim.trim(result.stdout or "")
    if dir == "" then return nil end

    local exe = dir .. (is_windows and "\\zig.exe" or "/zig")
    if vim.fn.executable(exe) == 1 then return exe end
    return nil
end

--- Write a shim that presents `zig cc` as a plain C compiler, and return it.
---
--- Two separate things stop the tree-sitter CLI from using zig directly.
---
---   1. It compiles through Rust's `cc` crate, which on a *-windows-msvc host
---      only ever looks for cl.exe. A zig.exe on PATH is invisible to it. That
---      is what "cl.exe ... Error: program not found" was: a working compiler
---      installed the whole time, never consulted. The crate does read CC, but
---      as a single executable -- a CC of "zig cc" silently drops the "cc" and
---      runs bare zig, which prints its usage and exits.
---   2. Once it identifies clang behind the shim it passes
---      --target=x86_64-pc-windows-msvc. That is a valid LLVM triple, but zig
---      parses triples itself and rejects the vendor field: "unable to parse
---      target query 'x86_64-pc-windows-msvc': UnknownOperatingSystem".
---      Dropping the flag leaves zig on its native target, whose DLLs Neovim
---      loads without complaint.
---
--- Hence a batch file: one executable to occupy CC's single slot, which
--- forwards to `zig cc` and filters that one flag out. Written only when the
--- content would change, so a normal startup does not rewrite a file that
--- real-time antivirus then wants to rescan.
---
--- Note the delayed expansion: an argument containing `!` would be mangled.
--- Nothing in a parser build carries one.
---@param zig string absolute path to zig.exe
---@return string|nil path_to_shim
local function write_zig_cc_shim(zig)
    local dir = vim.fs.normalize(vim.fn.stdpath("data")) .. "/nvim-portable"
    local path = dir .. "/zig-cc.bat"
    local content = table.concat({
        "@echo off",
        "rem Generated by lua/config/paths.lua. Edits are overwritten.",
        "setlocal EnableDelayedExpansion",
        'set "ARGS="',
        ":parse",
        'if "%~1"=="" goto run',
        'set "A=%~1"',
        'if "!A:~0,9!"=="--target=" goto next',
        'set "ARGS=!ARGS! "!A!""',
        ":next",
        "shift",
        "goto parse",
        ":run",
        '"' .. zig:gsub("/", "\\") .. '" cc %ARGS%',
        "",
    }, "\r\n")

    local existing = io.open(path, "rb")
    if existing then
        local current = existing:read("a")
        existing:close()
        if current == content then return path end
    end

    vim.fn.mkdir(dir, "p")
    local out = io.open(path, "wb")
    if not out then return nil end
    out:write(content)
    out:close()
    return path
end

--- Make a C compiler usable by `tree-sitter build`, which does the compiling
--- in a subprocess of its own.
---
--- "Usable" means one of exactly two things: it is the compiler that
--- subprocess looks for by default (cl.exe on Windows, cc elsewhere), or it is
--- named in CC. Being on PATH is not enough on Windows -- gcc, clang and zig
--- are all ignored there unless CC points at them.
---@return string|nil compiler
function M.ensure_c_compiler()
    -- An explicit choice in the environment outranks anything guessed here.
    if vim.env.CC and vim.env.CC ~= "" then return vim.env.CC end

    local default_cc = is_windows and "cl" or "cc"
    if vim.fn.executable(default_cc) == 1 then return default_cc end

    if is_windows then
        local zig = find_zig()
        if zig then
            local shim = write_zig_cc_shim(zig)
            if shim then
                vim.env.CC = shim
                return shim
            end
        end
    end

    -- Deliberately no bare "zig" here: it needs its `cc` subcommand, which CC
    -- cannot carry. Without the shim above it is not a candidate at all.
    for _, cc in ipairs({ "clang", "gcc", "cc" }) do
        if cc ~= default_cc and vim.fn.executable(cc) == 1 then
            vim.env.CC = cc
            return cc
        end
    end
    return nil
end

--- Locate the tree-sitter CLI, making it usable by subprocesses.
--- Bundled copy first, then PATH.
---@return string|nil
function M.ensure_tree_sitter_cli()
    local bundled_dir = M.tools_root() .. "/bin"
    local bundled = bundled_dir .. (is_windows and "/tree-sitter.exe" or "/tree-sitter")
    if vim.fn.executable(bundled) == 1 then
        -- nvim-treesitter invokes it by bare name, so the directory has to be
        -- on PATH; resolving the absolute path alone is not enough.
        M.prepend_to_path(bundled_dir)
        return bundled
    end
    if vim.fn.executable("tree-sitter") == 1 then return "tree-sitter" end
    return nil
end

return M
