-- lualine: the statusline.
--
-- Neovim's default statusline shows the filename and position. This adds the
-- things you actually want while working: which git branch you are on, whether
-- the file is modified, and how many LSP diagnostics it has -- so you can see
-- there are errors without leaving the file.

return {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },

    -- The statusline is visible immediately, so there is nothing to defer.
    event = "VeryLazy",

    opts = {
        options = {
            -- "auto" derives colours from the active colourscheme, so changing
            -- the scheme changes the statusline too and nothing needs updating
            -- here.
            theme = "auto",

            -- Plain separators. The powerline arrows need a patched font and
            -- look broken without one.
            section_separators = "",
            component_separators = "|",

            globalstatus = true,   -- one statusline for the whole window, not per split
        },

        sections = {
            lualine_a = { "mode" },
            lualine_b = { "branch", "diff" },
            lualine_c = {
                -- Path relative to the working directory. Just the filename is
                -- ambiguous when several files share a name, which happens
                -- constantly in a Python project (every __init__.py).
                { "filename", path = 1 },
            },
            lualine_x = {
                {
                    "diagnostics",
                    sources = { "nvim_diagnostic" },
                    symbols = { error = "E", warn = "W", info = "I", hint = "H" },
                },
                -- Which language servers are attached to this buffer. Turns
                -- "is the LSP even running?" into something you can just see.
                {
                    function()
                        local clients = vim.lsp.get_clients({ bufnr = 0 })
                        if #clients == 0 then return "" end
                        local names = {}
                        for _, c in ipairs(clients) do names[#names + 1] = c.name end
                        table.sort(names)
                        return table.concat(names, ",")
                    end,
                    icon = "LSP:",
                },
                "filetype",
            },
            lualine_y = { "progress" },
            lualine_z = { "location" },
        },
    },
}
