-- Colourscheme.
--
-- Now that treesitter is running, a scheme has far more to work with: it can
-- colour a function *call* differently from a function *definition*, because
-- treesitter tells it which is which. The regex engine could not, so schemes
-- looked flatter before.
--
-- TO SWITCH SCHEMES
--   1. Change the repo below (and `name`, if the plugin's directory name
--      differs from the scheme name).
--   2. Change the vim.cmd.colorscheme call at the bottom.
--   3. Restart. `:Lazy clean` afterwards removes the old plugin.
--
-- Schemes worth trying, all treesitter-aware:
--   rose-pine/neovim          variants: rose-pine-main, -moon, -dawn (light)
--   folke/tokyonight.nvim     variants: tokyonight-night, -storm, -moon, -day
--   catppuccin/nvim           variants: catppuccin-mocha, -macchiato, -frappe
--   ellisonleao/gruvbox.nvim  the classic
--   rebelot/kanagawa.nvim     muted, low contrast
--
-- To see what a scheme is actually doing to a given token, put the cursor on it
-- and run :Inspect -- it reports the treesitter capture, the highlight group,
-- and the colour. That is the tool for tweaking rather than guessing.

return {
    "rose-pine/neovim",
    name = "rose-pine",

    -- Loaded eagerly and early. A colourscheme applied after other plugins
    -- have drawn produces a visible flash of the default scheme on startup,
    -- and priority ensures it wins that race.
    lazy = false,
    priority = 1000,

    opts = {
        variant = "main",       -- "main" (dark), "moon" (softer dark), "dawn" (light)
        dark_variant = "main",

        styles = {
            -- Italic comments are a matter of taste and some terminal fonts
            -- render them badly. Off by default; flip if you like them.
            italic = false,
            transparent = false,
        },

        -- Highlight-group overrides applied by the scheme itself. Doing it here
        -- rather than with nvim_set_hl means they survive a scheme reload
        -- without needing a separate ColorScheme autocmd.
        --
        -- Note that the custom LineNr and CursorLineNr colours in
        -- lua/config/options.lua are re-applied on the ColorScheme event, so
        -- they deliberately override whatever this scheme sets for those two.
        highlight_groups = {
            -- Make the current search hit stand out from other matches.
            CurSearch = { fg = "base", bg = "gold", inherit = false },
            Search = { fg = "text", bg = "rose", blend = 20, inherit = false },
        },
    },

    config = function(_, opts)
        require("rose-pine").setup(opts)
        vim.cmd.colorscheme("rose-pine")
    end,
}
