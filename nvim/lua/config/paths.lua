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

--- Locate a C compiler, making it usable by subprocesses.
---
--- Treesitter parsers are C libraries that must be compiled locally. On a
--- machine with no build tools the compiler comes from `pip install ziglang`,
--- whose zig.exe sits inside the Python package directory rather than in
--- Scripts. If PATH does not already have a compiler, ask Python where that
--- package is instead of giving up -- this is what makes the config work in a
--- terminal that predates setup.ps1.
---@return string|nil name_of_compiler_on_path
function M.ensure_c_compiler()
    for _, cc in ipairs({ "zig", "cc", "gcc", "clang", "cl" }) do
        if vim.fn.executable(cc) == 1 then return cc end
    end

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

    M.prepend_to_path(dir)
    if vim.fn.executable("zig") == 1 then return "zig" end
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
