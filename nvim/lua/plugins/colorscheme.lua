-- Colourscheme: Monokai, as in Sublime Text.
--
-- monokai-pro.nvim rather than one of the plainer Monokai ports, for two
-- reasons: its "classic" filter is the original Sublime/TextMate Monokai
-- palette, and it ships a lualine theme, so the statusline follows the scheme
-- automatically (lua/plugins/lualine.lua uses theme = "auto").
--
-- THE FILTER IS SELECTED BY THE COLOURSCHEME NAME, NOT BY THE `filter` OPTION.
--
-- This is a trap. The plugin ships one colours file per filter, and the generic
-- `colors/monokai-pro.lua` consists of a single line:
--     require("monokai-pro").set_filter("pro")
-- So `colorscheme monokai-pro` silently applies the Pro palette no matter what
-- `filter` was passed to setup. Setting filter = "classic" and then loading the
-- generic name gave Monokai Pro's colours (background #2d2a2e, keyword #ff6188)
-- rather than Sublime's (#272822, #f92672).
--
-- Load the filter-specific name instead, as below. Available names:
--   monokai-pro-classic     original Sublime Monokai   <- in use
--   monokai-pro             Monokai Pro, desaturated
--   monokai-pro-octagon     cooler, blue-leaning background
--   monokai-pro-machine     teal-leaning
--   monokai-pro-ristretto   warm, brown-leaning
--   monokai-pro-spectrum    near-neutral grey background
--   monokai-pro-light       light background
--
-- To change variant, change the vim.cmd.colorscheme call at the bottom.
--
-- TO SWITCH TO A DIFFERENT SCHEME ENTIRELY
--   1. Replace the repo and `name` below.
--   2. Update the setup/colorscheme calls in `config`.
--   3. Restart, then `:Lazy clean` to remove the old plugin.
--
-- To see what the scheme is doing to a given token, put the cursor on it and
-- run :Inspect -- it reports the treesitter capture, the highlight group and
-- the resolved colour. That is the tool for tweaking rather than guessing.

return {
    "loctvl842/monokai-pro.nvim",
    name = "monokai-pro",

    -- Loaded eagerly and early. A colourscheme applied after other plugins have
    -- drawn shows a visible flash of the default scheme on startup; priority
    -- wins that race.
    lazy = false,
    priority = 1000,

    opts = {
        -- Kept for completeness, but note it does NOT decide the palette --
        -- the colorscheme name below does. See the header.
        filter = "classic",

        transparent_background = false,

        -- Recolour the built-in :terminal to match the scheme.
        terminal_colors = true,

        -- Colour nvim-web-devicons to match, so the file tree and the
        -- completion menu agree with everything else.
        devicons = true,

        styles = {
            -- Italics are a matter of taste and some terminal fonts render them
            -- badly. Off, matching the previous scheme's setting.
            comment = { italic = false },
            keyword = { italic = false },
            type = { italic = false },
            storageclass = { italic = false },
            structure = { italic = false },
            parameter = { italic = false },
            annotation = { italic = false },
        },

        -- Highlight the current search hit by background rather than underline;
        -- easier to spot while scanning.
        inc_search = "background",
    },

    config = function(_, opts)
        require("monokai-pro").setup(opts)
        -- The "-classic" suffix is what actually selects the Sublime palette.
        vim.cmd.colorscheme("monokai-pro-classic")
    end,
}
