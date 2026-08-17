-- Neovim configuration entry point.
--
-- Neovim looks for this file in stdpath('config'), which is
-- %LOCALAPPDATA%\nvim on Windows. This repo is linked to that location by
-- link-config.ps1, so editing this file edits the live config directly.
--
-- Check what Neovim thinks at any time with:  :lua print(vim.fn.stdpath('config'))

-- The leader key is a prefix for your own shortcuts. It must be set before
-- anything that defines a mapping, because mappings capture the current value
-- of leader when they are created, not when they are pressed. Plugins define
-- mappings as they load, so this has to happen before lazy.nvim starts.
-- Setting it late is the single most common reason a config's keymaps
-- silently do nothing.
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Set this to false if your terminal font is not a Nerd Font. Plugins read it
-- to decide between icons and plain-text fallbacks. Nothing breaks either way;
-- you just get placeholder boxes instead of file-type icons.
vim.g.have_nerd_font = true

-- Each require() below loads lua/<path>.lua, with dots standing in for
-- directory separators -- so "config.options" resolves to lua/config/options.lua.
-- Neovim searches every directory on its runtimepath for a lua/ folder, and
-- your config directory is on that path, which is why this works with no
-- setup. Confirm with:  :lua print(vim.o.runtimepath)
require("config.options")
require("config.keymaps")
require("config.lazy")
