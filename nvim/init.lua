-- Neovim configuration entry point.
--
-- Neovim looks for this file in stdpath('config'), which is
-- %LOCALAPPDATA%\nvim on Windows. This repo is linked to that location by
-- link-config.ps1, so editing this file edits the live config directly.
--
-- Check what Neovim thinks at any time with:  :lua print(vim.fn.stdpath('config'))

-- The leader key is a prefix for your own shortcuts. It must be set before
-- anything that defines a mapping, because mappings capture the current value
-- of leader when they are created, not when they are pressed. Setting it late
-- is the single most common reason a config's keymaps silently do nothing.
-- Space is the usual choice: it is easy to reach and does nothing useful in
-- normal mode by default.
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Line numbering. Relative numbers show distance from the cursor, which is
-- what motion counts like 5j or d3k actually operate on. Combined with
-- 'number', the current line shows its true number while the rest show
-- distance -- so you can read the count for a jump straight off the screen.
vim.opt.number = true
vim.opt.relativenumber = true

-- Indentation. Neovim distinguishes three things:
--   tabstop     how many columns an existing tab character is displayed as
--   shiftwidth  how many columns >> and << and autoindent move by
--   expandtab   insert spaces instead of an actual tab character
-- Four spaces, no tab characters, matching PEP 8.
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.smartindent = true

-- Search. 'ignorecase' alone would make it impossible to search case
-- sensitively; 'smartcase' restores that by making the search case sensitive
-- as soon as you type a capital letter. The two are almost always set together.
vim.opt.ignorecase = true
vim.opt.smartcase = true

-- Highlight matches as you type the search, and clear the leftover highlight
-- once you are done.
vim.opt.incsearch = true
vim.opt.hlsearch = true

-- Use the full colour range of a modern terminal. Without this, colourschemes
-- fall back to 256 colours and look noticeably wrong.
vim.opt.termguicolors = true

-- Always show the sign column, where git markers and diagnostics appear.
-- Left on "auto" the text shifts left and right as signs come and go, which is
-- distracting once linting is running.
vim.opt.signcolumn = "yes"

-- Keep some context visible above and below the cursor rather than letting it
-- sit against the very edge of the window.
vim.opt.scrolloff = 8

-- Open splits where the eye expects them: new pane right or below.
vim.opt.splitright = true
vim.opt.splitbelow = true

-- Long lines run off the screen instead of wrapping. For code this is usually
-- preferable; wrapped lines make it hard to see the real structure.
vim.opt.wrap = false

-- Persistent undo. Undo history is written to disk under stdpath('state'), so
-- it survives closing the file -- you can reopen something tomorrow and still
-- undo yesterday's change.
vim.opt.undofile = true

-- Share the system clipboard, so y and p exchange text with other Windows
-- applications rather than only with Neovim's own registers.
vim.opt.clipboard = "unnamedplus"

-- Write the swapfile and trigger CursorHold sooner. The default of 4000ms is
-- a holdover from slow disks and makes later plugin features feel sluggish.
vim.opt.updatetime = 250
