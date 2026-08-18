-- nvim-treesitter: language-aware syntax highlighting and indentation.
--
-- Neovim's built-in highlighting is a regex engine, which guesses at structure.
-- Treesitter parses the file into a real syntax tree, so a function name is
-- highlighted because it IS a function name, not because it matched a pattern.
-- That accuracy is also what makes a colourscheme look good: schemes target
-- treesitter's fine-grained groups (@function.call, @variable.parameter, ...)
-- which the regex engine simply cannot produce.
--
-- WHY THIS NEEDS TOOLING
-- A treesitter parser is a C library compiled per language. Neovim 0.12 ships
-- none, so each one is generated and built on the machine. The main branch
-- requires:
--     tree-sitter CLI  bundled in tools/nvim-tools.zip (no pip package exists,
--                      and upstream explicitly says not to install it from npm)
--     a C compiler     `zig cc`, from `pip install ziglang` -- a full C
--                      compiler as a Python wheel, which is what makes this
--                      work on a machine with no build tools
--     tar and curl     both ship with Windows 10+
--
-- If any of those is missing, the guard below skips the whole thing and you
-- keep the regex highlighting rather than getting errors on every startup.

return {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",

    -- Upstream is explicit: this plugin does not support lazy-loading.
    lazy = false,

    -- Parsers are pinned to plugin versions, so they must be rebuilt whenever
    -- the plugin updates or they break.
    build = ":TSUpdate",

    config = function()
        local ts = require("nvim-treesitter")

        -- install_dir is prepended to runtimepath, and holds both the compiled
        -- parsers and their query files. Deliberately under stdpath('data')
        -- rather than in this repo: compiled binaries are derived artifacts and
        -- do not belong in version control.
        ts.setup({
            install_dir = vim.fn.stdpath("data") .. "/site",
        })

        -- Languages worth having. Kept deliberately short: every entry is a
        -- compile, and parsers you never look at cost build time for nothing.
        local languages = {
            "python", "rust", "lua", "toml", "json", "yaml",
            "markdown", "markdown_inline", "sql", "bash", "diff",
            "gitcommit", "gitignore", "vim", "vimdoc", "query",
        }

        -- Locate the toolchain, repairing this session's environment if needed.
        --
        -- Neither half of it can be found the obvious way. setup.ps1 adds the
        -- tool directories to the *user* PATH, and environment changes only
        -- reach processes started afterwards, so a terminal opened before setup
        -- ran sees none of them. And the compiler is not a PATH question at
        -- all: `tree-sitter build` compiles through Rust's `cc` crate, which on
        -- Windows looks for cl.exe and nothing else unless CC names an
        -- alternative -- so a perfectly good zig.exe on PATH still produced
        -- "cl.exe ... program not found". config.paths resolves the bundled
        -- tree-sitter CLI onto this session's PATH, and points CC at a shim
        -- that forwards to `zig cc`.
        local paths = require("config.paths")

        -- Downloads go through curl, which on a TLS-inspecting corporate
        -- network fails with CRYPT_E_NO_REVOCATION_CHECK before any compiler is
        -- involved. Give it a config that tolerates a proxy certificate with no
        -- reachable revocation list. Scoped to this session's children.
        paths.ensure_curl_config()

        local missing = {}
        if not paths.ensure_tree_sitter_cli() then table.insert(missing, "the tree-sitter CLI") end
        if not paths.ensure_c_compiler() then table.insert(missing, "a C compiler") end

        if #missing > 0 then
            vim.notify(
                "treesitter: not installing parsers, missing " .. table.concat(missing, " and ")
                .. "\nHighlighting falls back to the regex engine."
                .. "\nRun setup.ps1, then open a NEW terminal.",
                vim.log.levels.WARN
            )
        else
            -- Asynchronous, and a no-op for parsers already installed, so this
            -- is cheap on every startup after the first.
            ts.install(languages)
        end

        -- Highlighting is NOT enabled by the plugin on the main branch -- that
        -- is a deliberate upstream change. vim.treesitter.start() attaches the
        -- highlighter to a buffer, and it must be called per buffer.
        --
        -- pcall because a filetype whose parser has not finished building yet
        -- would otherwise raise an error on every file you open.
        vim.api.nvim_create_autocmd("FileType", {
            group = vim.api.nvim_create_augroup("treesitter-highlight", { clear = true }),
            callback = function(event)
                local lang = vim.treesitter.language.get_lang(vim.bo[event.buf].filetype)
                if not lang then return end
                -- Skip enormous files: parsing cost scales with size and the
                -- benefit does not.
                local ok, stats = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(event.buf))
                if ok and stats and stats.size > 1024 * 1024 then return end

                if pcall(vim.treesitter.start, event.buf, lang) then
                    -- Treesitter-aware indentation. Opt-in per buffer, and only
                    -- once highlighting succeeded, since both need the parser.
                    vim.bo[event.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
                end
            end,
            desc = "Enable treesitter highlighting where a parser exists",
        })
    end,
}
