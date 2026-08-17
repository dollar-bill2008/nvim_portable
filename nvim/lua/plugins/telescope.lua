-- telescope: the fuzzy finder. Equivalent to VS Code's Ctrl+P for files and
-- its search panel for text, in one floating window.
--
-- Two backends do the actual work, both installed separately from Neovim:
--   fd        lists files fast, respecting .gitignore   -> find_files
--   ripgrep   searches file contents fast               -> live_grep
-- Without them telescope still runs but falls back to much slower built-ins.
-- Check they are visible from inside Neovim with:  :checkhealth telescope

return {
    "nvim-telescope/telescope.nvim",
    branch = "0.1.x",
    dependencies = { "nvim-lua/plenary.nvim" },

    cmd = "Telescope",
    keys = {
        -- The <leader>f... group: f for find.
        { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find: files" },
        { "<leader>fg", "<cmd>Telescope live_grep<cr>",  desc = "Find: text in project (grep)" },
        { "<leader>fb", "<cmd>Telescope buffers<cr>",    desc = "Find: open buffers" },
        { "<leader>fr", "<cmd>Telescope oldfiles<cr>",   desc = "Find: recent files" },
        { "<leader>fh", "<cmd>Telescope help_tags<cr>",  desc = "Find: help topics" },
        { "<leader>fk", "<cmd>Telescope keymaps<cr>",    desc = "Find: keymaps" },
        { "<leader>fd", "<cmd>Telescope diagnostics<cr>", desc = "Find: diagnostics" },

        -- Search the word under the cursor across the project.
        { "<leader>fw", "<cmd>Telescope grep_string<cr>", desc = "Find: word under cursor" },
    },

    opts = {
        defaults = {
            -- Where the prompt sits and how results are laid out. horizontal
            -- puts the preview pane to the right, like VS Code's search.
            layout_strategy = "horizontal",
            layout_config = {
                horizontal = { preview_width = 0.55 },
                width = 0.9,
                height = 0.85,
            },

            -- Directories that are never worth searching. Adding to this list
            -- is usually the fix when live_grep feels slow in a big repo.
            file_ignore_patterns = {
                "%.git/", "node_modules/", "%.venv/", "venv/",
                "__pycache__/", "%.mypy_cache/", "%.ruff_cache/",
                "target/", "%.lock",
            },

            mappings = {
                -- Inside the telescope prompt (insert mode):
                i = {
                    ["<C-j>"] = "move_selection_next",
                    ["<C-k>"] = "move_selection_previous",
                    -- Escape closes the picker outright rather than dropping
                    -- to normal mode inside it, which is rarely what you want.
                    ["<Esc>"] = "close",
                },
            },
        },

        pickers = {
            find_files = {
                -- Show dotfiles, but never the .git directory itself.
                hidden = true,
                no_ignore = false,
            },
        },
    },
}
