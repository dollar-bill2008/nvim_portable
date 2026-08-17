-- neo-tree: the file browser panel, equivalent to VS Code's Explorer sidebar.
--
-- This file returns a plugin SPEC -- a table describing a plugin to
-- lazy.nvim. It does not load anything itself. lazy.nvim collects every spec
-- under lua/plugins/, works out the dependency order, and loads each one at
-- the moment it is first needed.

return {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",

    -- Plugins this one needs. lazy.nvim installs and loads them first; you do
    -- not list them separately.
    --   plenary          shared Lua utility library, used by half the ecosystem
    --   nui              the window and popup toolkit neo-tree draws with
    --   nvim-web-devicons  file-type icons (needs a Nerd Font in your terminal)
    dependencies = {
        "nvim-lua/plenary.nvim",
        "MunifTanjim/nui.nvim",
        "nvim-tree/nvim-web-devicons",
    },

    -- Lazy-loading triggers. The plugin stays unloaded until you press one of
    -- these keys or run the :Neotree command, which keeps startup fast.
    -- Because `keys` is declared here rather than in config/keymaps.lua,
    -- lazy.nvim knows the mapping exists without loading the plugin to find out.
    cmd = "Neotree",
    keys = {
        { "<leader>e", "<cmd>Neotree toggle left<cr>", desc = "File tree: toggle" },
        { "<leader>E", "<cmd>Neotree reveal left<cr>", desc = "File tree: reveal current file" },
    },

    -- `opts` is passed to the plugin's setup() function. Using opts rather
    -- than writing config = function() require(...).setup{...} end lets
    -- lazy.nvim merge settings and call setup at the right moment.
    opts = {
        -- Quit Neovim if the tree is the only window left, rather than
        -- leaving an empty sidebar behind.
        close_if_last_window = true,

        window = {
            width = 32,
            mappings = {
                -- Space is the leader key, so unbind it inside the tree or
                -- every leader mapping stalls for timeoutlen while neo-tree
                -- waits to see if you meant its own space mapping.
                ["<space>"] = "none",
                ["<cr>"] = "open",
                ["s"] = "open_vsplit",
                ["i"] = "open_split",
            },
        },

        filesystem = {
            -- Move the tree's selection to match the file you are editing.
            follow_current_file = { enabled = true, leave_dirs_open = true },

            -- Let libuv watch the filesystem, so files created outside Neovim
            -- appear without a manual refresh.
            use_libuv_file_watcher = true,

            filtered_items = {
                -- Show dotfiles. In this repo that includes .gitattributes
                -- and .gitignore, which you do want to see.
                hide_dotfiles = false,
                hide_gitignored = true,
                hide_by_name = { ".git" },
            },
        },

        default_component_configs = {
            indent = { with_expanders = true },
            git_status = {
                symbols = {
                    added = "+", modified = "~", deleted = "-",
                    renamed = "→", untracked = "?", ignored = "·",
                    staged = "S", conflict = "!",
                },
            },
        },
    },
}
