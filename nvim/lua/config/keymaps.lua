-- Your own key mappings.
--
-- The signature is:  vim.keymap.set(mode, lhs, rhs, opts)
--   mode  "n" normal, "i" insert, "v" visual, "x" visual-block,
--         "t" terminal. A table sets several at once: { "n", "v" }
--   lhs   the keys you press
--   rhs   what happens -- either keys to replay, or a Lua function
--   opts  desc shows up in :map and in which-key style popups.
--         silent stops the command echoing in the message line.
--
-- Plugin-specific mappings do NOT belong here. They go in that plugin's spec
-- under `keys = {}`, which lets lazy.nvim defer loading the plugin until the
-- key is actually pressed. Keeping them together would load everything at
-- startup and lose that.

local map = vim.keymap.set

-- Clear search highlighting. After a search the matches stay lit until the
-- next search; this dismisses them without disabling 'hlsearch' entirely.
map("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "Clear search highlight" })

-- Save and quit. Familiar from your previous config.
map("n", "<leader>w", "<cmd>write<cr>", { desc = "Write file", silent = true })
map("n", "<leader>q", "<cmd>quit<cr>", { desc = "Quit window", silent = true })

-- Move between splits with Ctrl and a direction, rather than <C-w> then the
-- direction. Two keystrokes instead of three, and it matches the h/j/k/l you
-- already use for cursor movement.
map("n", "<C-h>", "<C-w>h", { desc = "Go to left split" })
map("n", "<C-j>", "<C-w>j", { desc = "Go to split below" })
map("n", "<C-k>", "<C-w>k", { desc = "Go to split above" })
map("n", "<C-l>", "<C-w>l", { desc = "Go to right split" })

-- Keep the cursor in place while joining lines. Plain J moves the cursor to
-- the join point, which is disorienting when joining several lines in a row.
map("n", "J", "mzJ`z", { desc = "Join line, keep cursor position" })

-- Centre the view after a half-page jump or a search hit, so the cursor does
-- not end up at the very top or bottom of the window.
map("n", "<C-d>", "<C-d>zz", { desc = "Half page down, centred" })
map("n", "<C-u>", "<C-u>zz", { desc = "Half page up, centred" })
map("n", "n", "nzzzv", { desc = "Next search hit, centred" })
map("n", "N", "Nzzzv", { desc = "Previous search hit, centred" })

-- Reindent without leaving visual mode, so you can press < or > repeatedly.
map("v", "<", "<gv", { desc = "Outdent, keep selection" })
map("v", ">", ">gv", { desc = "Indent, keep selection" })

-- Move the selected lines up or down, carrying their indentation with them.
map("v", "J", ":m '>+1<cr>gv=gv", { desc = "Move selection down" })
map("v", "K", ":m '<-2<cr>gv=gv", { desc = "Move selection up" })

-- Paste over a selection without losing what you had yanked. Normally the
-- replaced text clobbers the register, so you can only paste it once.
map("x", "<leader>p", [["_dP]], { desc = "Paste without clobbering register" })

-- Open the diagnostics for the line under the cursor in a floating window.
-- Useful before LSP is configured, and still useful after.
map("n", "<leader>d", vim.diagnostic.open_float, { desc = "Line diagnostics" })
