-- Your own key mappings.
--
-- The signature is:  vim.keymap.set(mode, lhs, rhs, opts)
--   mode  "n" normal, "i" insert, "v" visual, "x" visual-block,
--         "t" terminal. A table sets several at once: { "n", "v" }
--   lhs   the keys you press
--   rhs   what happens -- either keys to replay, or a Lua function
--   opts  desc shows up in :map and in <leader>fk (Telescope keymaps).
--         silent stops the command echoing in the message line.
--
-- Plugin-specific mappings do NOT belong here. They go in that plugin's spec
-- under `keys = {}`, which lets lazy.nvim defer loading the plugin until the
-- key is actually pressed. Keeping them together would load everything at
-- startup and lose that.
--
-- LSP mappings also do not belong here -- they are set per buffer when a
-- language server attaches, in lua/config/lsp.lua.

local keymap = vim.keymap

-- Writing and quitting.
keymap.set("n", "<leader>w", "<cmd>write<cr>", { desc = "Save file", silent = true })
keymap.set("n", "<leader>W", "<cmd>wall<cr>", { desc = "Save all buffers", silent = true })
keymap.set("n", "<leader>q", "<cmd>quit<cr>", { desc = "Quit window", silent = true })
keymap.set("n", "<leader>Q", "<cmd>quit!<cr>", { desc = "Force quit, discard changes", silent = true })
keymap.set("n", "<leader>x", "<cmd>wq<cr>", { desc = "Save and quit", silent = true })
keymap.set("n", "<leader>X", "<cmd>wqa<cr>", { desc = "Save and quit all", silent = true })

-- Splits.
keymap.set("n", "<leader>v", "<cmd>vsplit<cr>", { desc = "Split vertically", silent = true })
keymap.set("n", "<leader>s", "<cmd>split<cr>", { desc = "Split horizontally", silent = true })

-- Split navigation with Shift and a direction.
--
-- Be aware what this costs. In Vim's notation <S-h> IS the key H -- there is no
-- separate "shift-h" to bind -- so these four mappings shadow four default
-- normal-mode commands:
--
--   H  jump to the top line of the window        (rehomed: not remapped)
--   J  join this line with the next              (rehomed to <leader>j below)
--   K  hover documentation from the LSP          (rehomed to <leader>k, in lsp.lua)
--   L  jump to the bottom line of the window     (rehomed: not remapped)
--
-- H and L are not remapped because they are cheap to live without: gg and G
-- reach the file ends, and Ctrl-d / Ctrl-u move by half screens. If you miss
-- them, delete the two lines below and use <C-h> / <C-l>, which are also bound.
keymap.set("n", "<S-h>", "<C-w>h", { desc = "Move to left split" })
keymap.set("n", "<S-j>", "<C-w>j", { desc = "Move to split below" })
keymap.set("n", "<S-k>", "<C-w>k", { desc = "Move to split above" })
keymap.set("n", "<S-l>", "<C-w>l", { desc = "Move to right split" })

-- Shift plus arrow keys do the same thing, for when you are not in the mood.
keymap.set("n", "<S-Left>", "<C-w>h", { desc = "Move to left split" })
keymap.set("n", "<S-Down>", "<C-w>j", { desc = "Move to split below" })
keymap.set("n", "<S-Up>", "<C-w>k", { desc = "Move to split above" })
keymap.set("n", "<S-Right>", "<C-w>l", { desc = "Move to right split" })

-- Ctrl plus hjkl, kept as a second route to the same splits. Some terminals
-- send <C-h> as backspace, which is why the Shift bindings above are the
-- primary ones.
keymap.set("n", "<C-h>", "<C-w>h", { desc = "Move to left split" })
keymap.set("n", "<C-j>", "<C-w>j", { desc = "Move to split below" })
keymap.set("n", "<C-k>", "<C-w>k", { desc = "Move to split above" })
keymap.set("n", "<C-l>", "<C-w>l", { desc = "Move to right split" })

-- Join lines, displaced from J by the split navigation above. The mz...`z
-- wrapper keeps the cursor where it was: plain J moves it to the join point,
-- which is disorienting when joining several lines in a row.
keymap.set("n", "<leader>j", "mzJ`z", { desc = "Join line below, keep cursor" })

-- Clear search highlighting. After a search the matches stay lit until the
-- next one; this dismisses them without disabling 'hlsearch' entirely.
keymap.set("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "Clear search highlight" })

-- Centre the view after a half-page jump or a search hit, so the cursor does
-- not end up at the very top or bottom of the window.
keymap.set("n", "<C-d>", "<C-d>zz", { desc = "Half page down, centred" })
keymap.set("n", "<C-u>", "<C-u>zz", { desc = "Half page up, centred" })
keymap.set("n", "n", "nzzzv", { desc = "Next search hit, centred" })
keymap.set("n", "N", "Nzzzv", { desc = "Previous search hit, centred" })

-- Reindent without leaving visual mode, so you can press < or > repeatedly.
keymap.set("v", "<", "<gv", { desc = "Outdent, keep selection" })
keymap.set("v", ">", ">gv", { desc = "Indent, keep selection" })

-- Move the selected lines up or down, carrying their indentation.
-- These are visual mode, so they do not clash with the normal-mode <S-j> and
-- <S-k> split navigation above.
keymap.set("v", "J", ":m '>+1<cr>gv=gv", { desc = "Move selection down" })
keymap.set("v", "K", ":m '<-2<cr>gv=gv", { desc = "Move selection up" })

-- Paste over a selection without losing what you had yanked. Normally the
-- replaced text clobbers the register, so you could only paste it once.
keymap.set("x", "<leader>p", [["_dP]], { desc = "Paste without clobbering register" })

-- Diagnostics for the current line in a floating window.
keymap.set("n", "<leader>d", vim.diagnostic.open_float, { desc = "Line diagnostics" })
