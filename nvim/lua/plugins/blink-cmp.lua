-- blink.cmp: completion and suggestions.
--
-- Chosen over nvim-cmp because it is one plugin instead of six -- nvim-cmp
-- needs separate source plugins for LSP, buffer, path and snippets, plus a
-- snippet engine. blink includes all of that.
--
-- The critical setting for a locked-down machine is fuzzy.implementation.
-- blink's default matcher is a Rust binary it downloads or compiles with
-- cargo, and neither is safe to assume. Forcing "lua" means no binary, no
-- download and no compiler -- pure Lua, deterministic everywhere.

return {
    "saghen/blink.cmp",
    version = "1.*",

    -- Deliberately NOT lazy-loaded. Completion capabilities have to be
    -- advertised to a language server when its client starts, so blink must be
    -- set up before the first LSP attaches. Loading it on InsertEnter would be
    -- too late for the first file you open, and you would silently lose
    -- snippet support and rich documentation from the server.
    lazy = false,

    opts = {
        -- The default keymap:
        --   <C-space>  open the menu / show documentation
        --   <C-n>      next item          <C-p>  previous item
        --   <C-y>      accept             <C-e>  dismiss
        --   <Tab>      jump to next snippet placeholder
        -- Note that <CR> does NOT accept by default, so pressing Enter still
        -- inserts a newline rather than a completion you did not want.
        keymap = { preset = "default" },

        appearance = {
            -- "mono" aligns icon widths for Nerd Font Mono variants. If icons
            -- look wrong, this and vim.g.have_nerd_font are the two dials.
            nerd_font_variant = "mono",
        },

        completion = {
            documentation = {
                -- Show the docs pane automatically, after a short pause so it
                -- does not flicker while you are still typing.
                auto_show = true,
                auto_show_delay_ms = 200,
            },
            -- Inline preview of the selected item. Off because it competes
            -- visually with diagnostics on the same line.
            ghost_text = { enabled = false },
        },

        sources = {
            -- Order is priority: language server first, then filesystem paths,
            -- then snippets, then words from open buffers as a last resort.
            default = { "lsp", "path", "snippets", "buffer" },
        },

        -- Snippet expansion uses Neovim's built-in vim.snippet (0.10+), so
        -- there is no separate snippet engine plugin to install.
        snippets = { preset = "default" },

        signature = { enabled = true },

        -- No Rust binary, no cargo, no download. See the note at the top.
        fuzzy = { implementation = "lua" },
    },
}
