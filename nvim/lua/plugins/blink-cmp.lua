-- blink.cmp: completion and suggestions.
--
-- Chosen over nvim-cmp because it is one plugin instead of six -- nvim-cmp
-- needs separate source plugins for LSP, buffer, path and snippets, plus a
-- snippet engine. blink includes all of that.
--
-- fuzzy.implementation is the setting that matters here, and it is a real
-- tradeoff rather than a formality. See the note beside it below.

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

        -- The fuzzy matcher runs on every keystroke while the completion menu
        -- is open, so it sits directly in the typing path -- a slow one is felt
        -- as input lag, not as a slow menu.
        --
        -- "prefer_rust" downloads a prebuilt binary for this release tag (no
        -- cargo, no compiler) and falls back to the pure-Lua matcher if the
        -- download is unavailable. That keeps a locked-down machine working
        -- while not making everyone pay the Lua matcher's cost.
        --
        -- Not "prefer_rust_with_warning" (the upstream default): on a machine
        -- where the download is blocked it warns on every startup, which is
        -- noise rather than information. Check which one is actually in use
        -- with :checkhealth blink.cmp
        fuzzy = { implementation = "prefer_rust" },
    },
}
