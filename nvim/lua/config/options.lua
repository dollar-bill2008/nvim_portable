-- Editor options. Set with vim.opt, read with vim.o.
--
-- Every option here has a manual page. Note the quotes -- for options you need
-- them:  :h 'relativenumber'   (without quotes, the help search finds nothing)

-- Line numbering. Relative numbers show distance from the cursor, which is
-- exactly what motion counts like 5j or d3k operate on. Combined with
-- 'number', the current line shows its true number while the rest show
-- distance, so you can read the count for a jump straight off the screen.
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
vim.opt.incsearch = true
vim.opt.hlsearch = true

-- Use the full colour range of a modern terminal. Without this, colourschemes
-- fall back to 256 colours and look noticeably wrong.
vim.opt.termguicolors = true

-- Always show the sign column, where git markers and LSP diagnostics appear.
-- Left on "auto" the text shifts left and right as signs come and go, which
-- becomes distracting once diagnostics are live.
vim.opt.signcolumn = "yes"

-- Keep context visible above and below the cursor rather than letting it sit
-- against the very edge of the window.
vim.opt.scrolloff = 8

-- Open splits where the eye expects them: new pane right, or below.
vim.opt.splitright = true
vim.opt.splitbelow = true

-- Long lines run off the screen instead of wrapping. For code this is usually
-- preferable; wrapped lines obscure the real structure.
vim.opt.wrap = false

-- Persistent undo, written under stdpath('state'). Undo history survives
-- closing the file, so you can reopen something tomorrow and still undo
-- yesterday's change.
vim.opt.undofile = true

-- Share the system clipboard, so y and p exchange text with other Windows
-- applications rather than only with Neovim's own registers.
vim.opt.clipboard = "unnamedplus"

-- Write the swapfile and trigger CursorHold sooner. The 4000ms default is a
-- holdover from slow disks and makes diagnostic hovers feel sluggish.
vim.opt.updatetime = 250

-- How long to wait for the rest of a multi-key mapping before giving up.
-- Matters once <leader> sequences exist: too short and you cannot type them,
-- too long and a lone <leader> press feels like a hang.
vim.opt.timeoutlen = 400

-- Show the effect of :s substitutions live, in a preview split.
vim.opt.inccommand = "split"

-- Highlight the line the cursor is on.
vim.opt.cursorline = true

-- Confirm on quit with unsaved changes rather than failing with an error.
vim.opt.confirm = true
