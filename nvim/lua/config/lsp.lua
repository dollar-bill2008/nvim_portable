-- Language servers, diagnostics and LSP keymaps.
--
-- Neovim 0.11 added vim.lsp.config() and vim.lsp.enable(), which means server
-- definitions no longer need the nvim-lspconfig plugin. Four servers at about
-- ten lines each is less to understand, and one less plugin to break.
--
-- Every server here is enabled ONLY if its executable is found, so this same
-- file works on a machine with the full toolchain and on one with nothing but
-- Neovim. Run :LspServers to see what is active and what is missing.

if vim.fn.has("nvim-0.11") == 0 then
    vim.notify("config.lsp needs Neovim 0.11+ for vim.lsp.config", vim.log.levels.WARN)
    return
end

-- Completion capabilities are advertised to the server when the client starts,
-- so they must be registered before any server attaches. blink.cmp is loaded
-- eagerly (see lua/plugins/blink-cmp.lua) and config.lsp is required after
-- config.lazy in init.lua, which is what makes this pcall succeed.
local capabilities = vim.lsp.protocol.make_client_capabilities()
local blink_ok, blink = pcall(require, "blink.cmp")
if blink_ok and blink.get_lsp_capabilities then
    capabilities = blink.get_lsp_capabilities(capabilities)
end

-- How diagnostics are displayed. Separate from the servers that produce them.
vim.diagnostic.config({
    -- Inline messages at the end of the offending line.
    virtual_text = { spacing = 2, prefix = "●" },
    signs = true,
    underline = true,

    -- Do not re-lint while you are mid-keystroke in insert mode; the noise is
    -- worse than the latency saved.
    update_in_insert = false,

    -- Show errors above warnings on a line that has both.
    severity_sort = true,

    float = { border = "rounded", source = true },
})

-- Where setup.ps1 put the bundled tools.
--
-- Derived from the running Neovim binary rather than hardcoded, because
-- setup.ps1 -InstallRoot can move both. nvim lives at
--   <root>/nvim-portable/bin/nvim.exe
-- and the tools at
--   <root>/nvim-portable-tools/
-- vim.fs.normalize is what keeps the separators consistent. fnamemodify
-- returns a Windows path with backslashes, and appending forward slashes to it
-- produces a mixed-separator path that some servers mis-handle -- notably
-- lua-language-server, which failed to start with "Duplicate channel" until
-- the path was normalised.
local function tools_root()
    local root = vim.fs.normalize(vim.fn.fnamemodify(vim.v.progpath, ":h:h:h"))
    return root .. "/nvim-portable-tools"
end

local function resolve(candidates)
    -- Returns the first candidate that exists and is executable, or nil.
    --
    -- Bundled absolute paths are listed before bare names on purpose. A bare
    -- name found on PATH is not necessarily usable: on a machine with rustup
    -- installed, ~/.cargo/bin/rust-analyzer.exe is a *proxy shim* that exists,
    -- satisfies executable(), and then dies with "Unknown binary
    -- 'rust-analyzer.exe' in official toolchain" because the component was
    -- never installed. Preferring the bundled copy sidesteps that entirely.
    for _, candidate in ipairs(candidates) do
        if vim.fn.executable(candidate) == 1 then return candidate end
    end
    return nil
end

local tools = tools_root()
local has_cargo = vim.fn.executable("cargo") == 1

-- root_markers tell the server where the project starts, which decides what it
-- indexes and how imports resolve. Get this wrong and go-to-definition works
-- inside a file but not across the project.
local servers = {
    -- Python types, completion, go-to-definition, hover.
    -- From pip. Ships its own Node via nodejs-wheel-binaries, so it needs no
    -- system Node.
    basedpyright = {
        cmd_candidates = { "basedpyright-langserver" },
        cmd_args = { "--stdio" },
        filetypes = { "python" },
        root_markers = { "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", ".git" },
        settings = {
            basedpyright = {
                analysis = {
                    -- basedpyright defaults to "recommended", which is very
                    -- strict and buries you in warnings on existing code.
                    -- Raise to "strict" or "recommended" when you want it.
                    typeCheckingMode = "standard",
                    -- Only analyse open files. "workspace" indexes everything
                    -- and is slow on a large repo.
                    diagnosticMode = "openFilesOnly",
                    autoImportCompletions = true,
                },
            },
        },
    },

    -- Python linting and formatting. Deliberately alongside basedpyright
    -- rather than instead of it: ruff catches lint and style, basedpyright
    -- catches type errors. They are complementary, not duplicate.
    ruff = {
        cmd_candidates = { "ruff" },
        cmd_args = { "server" },
        filetypes = { "python" },
        root_markers = { "pyproject.toml", "ruff.toml", ".ruff.toml", ".git" },
    },

    -- Rust. Bundled in tools/, so no rustup needed to get the server itself.
    -- Note that full project analysis still wants cargo for metadata; without
    -- it you get syntax and completion but not cross-crate resolution.
    rust_analyzer = {
        cmd_candidates = { tools .. "/bin/rust-analyzer.exe", "rust-analyzer" },
        filetypes = { "rust" },
        root_markers = { "Cargo.toml", "rust-project.json", ".git" },
        settings = {
            ["rust-analyzer"] = {
                cargo = { allFeatures = true },
                -- Both check-on-save modes shell out to cargo. Without cargo
                -- installed they fail on every save, so turn the feature off
                -- rather than let it error repeatedly. You still get syntax,
                -- completion and hover from the server itself.
                checkOnSave = has_cargo,
                check = has_cargo and { command = "clippy" } or nil,
            },
        },
    },

    -- Lua, configured for editing this Neovim config specifically.
    lua_ls = {
        cmd_candidates = {
            tools .. "/lua-language-server/bin/lua-language-server.exe",
            "lua-language-server",
        },
        -- By default this server writes its log and its generated meta
        -- annotations inside its own install directory. That directory is
        -- re-extracted by setup.ps1 on a version change, which would discard
        -- the state, so point both at the cache directory instead.
        cmd_args = {
            "--logpath", vim.fn.stdpath("cache") .. "/lua-language-server/log",
            "--metapath", vim.fn.stdpath("cache") .. "/lua-language-server/meta",
        },
        filetypes = { "lua" },
        root_markers = { ".luarc.json", ".luarc.jsonc", "stylua.toml", ".git" },
        settings = {
            Lua = {
                runtime = { version = "LuaJIT" },
                -- Without this, every reference to `vim` is flagged as an
                -- undefined global, which makes the whole config look broken.
                diagnostics = { globals = { "vim" } },
                workspace = {
                    -- Just the Neovim runtime. Adding every plugin directory
                    -- makes startup noticeably slower for little gain.
                    library = { vim.env.VIMRUNTIME },
                    checkThirdParty = false,
                },
                telemetry = { enable = false },
            },
        },
    },
}

local active, missing = {}, {}

for name, config in pairs(servers) do
    -- cmd_candidates and cmd_args are this config's own fields, not part of
    -- the vim.lsp.config schema, so strip them before handing the table over.
    local candidates = config.cmd_candidates
    local args = config.cmd_args or {}
    config.cmd_candidates = nil
    config.cmd_args = nil

    -- The graceful-degradation point: a server whose binary cannot be found is
    -- simply not enabled. No error, no broken startup, and the same file works
    -- on a fully equipped machine and a bare one.
    local exe = resolve(candidates)
    if exe then
        config.cmd = vim.list_extend({ exe }, args)
        config.capabilities = capabilities
        vim.lsp.config(name, config)
        vim.lsp.enable(name)
        table.insert(active, string.format("%-14s %s", name, exe))
    else
        -- Report the bare name, which is the one a user would install.
        table.insert(missing, string.format("%-14s needs %s", name, candidates[#candidates]))
    end
end

table.sort(active)
table.sort(missing)

-- Reporting which servers did not start, and why. Without this a missing
-- binary looks like the config being broken rather than a tool not installed.
vim.api.nvim_create_user_command("LspServers", function()
    local lines = { "Enabled language servers (and the binary each resolved to):" }
    if #active == 0 then
        table.insert(lines, "  (none)")
    else
        for _, n in ipairs(active) do table.insert(lines, "  " .. n) end
    end

    table.insert(lines, "")
    table.insert(lines, "Not enabled (binary not found):")
    if #missing == 0 then
        table.insert(lines, "  (none -- everything is installed)")
    else
        for _, n in ipairs(missing) do table.insert(lines, "  " .. n) end
        table.insert(lines, "")
        table.insert(lines, "Python servers come from:  pip install --user basedpyright ruff")
        table.insert(lines, "The others are bundled in the repo; re-run setup.ps1")
    end

    table.insert(lines, "")
    table.insert(lines, "Attached to this buffer:")
    local clients = vim.lsp.get_clients({ bufnr = 0 })
    if #clients == 0 then
        table.insert(lines, "  (none)")
    else
        for _, c in ipairs(clients) do
            table.insert(lines, string.format("  %s (id %d, root %s)", c.name, c.id, c.config.root_dir or "?"))
        end
    end

    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end, { desc = "Show which language servers are active or missing" })

-- Keymaps that only make sense once a server is attached, so they are set per
-- buffer when one attaches rather than globally at startup.
--
-- Neovim 0.11 ships defaults already, and they are not worth re-binding:
--   K      hover            grn  rename          gra  code action
--   grr    references       gri  implementation  grt  type definition
--   gO     document symbols [d / ]d  previous / next diagnostic
--   <C-s>  signature help (insert mode)
--
-- Only what is genuinely missing is added below.
vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("lsp-attach-keymaps", { clear = true }),
    callback = function(event)
        local function map(keys, fn, desc)
            vim.keymap.set("n", keys, fn, { buffer = event.buf, desc = "LSP: " .. desc })
        end

        map("gd", vim.lsp.buf.definition, "Go to definition")
        map("gD", vim.lsp.buf.declaration, "Go to declaration")

        -- Hover, displaced from the default K by the <S-k> split navigation in
        -- config/keymaps.lua. Without this the split binding would silently
        -- cost you documentation on hover, which is one of the main reasons to
        -- run a language server at all.
        map("<leader>k", vim.lsp.buf.hover, "Hover documentation")

        map("<leader>lf", function()
            -- Both ruff and basedpyright attach to Python buffers, and asking
            -- "who formats this?" with two clients attached prompts every
            -- time. Pin Python formatting to ruff.
            vim.lsp.buf.format({
                async = false,
                filter = function(client)
                    if vim.bo[event.buf].filetype == "python" then
                        return client.name == "ruff"
                    end
                    return true
                end,
            })
        end, "Format buffer")

        map("<leader>ll", vim.diagnostic.setloclist, "Diagnostics to location list")
        map("<leader>ls", "<cmd>LspServers<cr>", "Which servers are running")
    end,
})

-- To format automatically on save, uncomment this. Left off by default because
-- a formatter rewriting a file you did not ask it to rewrite is a surprise,
-- especially in a shared repo with its own style settings.
--
-- vim.api.nvim_create_autocmd("BufWritePre", {
--     pattern = { "*.py", "*.lua", "*.rs" },
--     callback = function() vim.lsp.buf.format({ async = false }) end,
-- })
