-- Bootstraps lazy.nvim, the plugin manager.
--
-- "Bootstrap" here means: on a machine that has never run this config, clone
-- the plugin manager itself before asking it to manage anything. That is why
-- a fresh clone of this repo needs nothing but git -- lazy.nvim installs
-- itself, then installs everything else.

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

-- Plugins live under stdpath('data') (%LOCALAPPDATA%\nvim-data), NOT under
-- your config directory. That separation is deliberate: config is yours and
-- belongs in git, plugin clones are derived data and do not. It is also why
-- deleting nvim-data is always safe -- lazy.nvim rebuilds it from the lockfile.
if not (vim.uv or vim.loop).fs_stat(lazypath) then
    local out = vim.fn.system({
        "git", "clone", "--filter=blob:none", "--branch=stable",
        "https://github.com/folke/lazy.nvim.git", lazypath,
    })
    if vim.v.shell_error ~= 0 then
        vim.api.nvim_echo({
            { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
            { out, "WarningMsg" },
            { "\nIs git on PATH? Behind a proxy, does `git clone` work in a terminal?" },
        }, true, {})
        vim.fn.getchar()
        os.exit(1)
    end
end

-- Put lazy.nvim at the FRONT of the runtimepath so require("lazy") finds it.
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
    -- Every .lua file in lua/plugins/ is imported and expected to return a
    -- plugin spec table. Adding a plugin is therefore just adding a file --
    -- there is no central list to keep in sync.
    spec = {
        { import = "plugins" },
    },

    -- Pin plugin versions in lazy-lock.json. Committed to git, so a clone on
    -- another machine installs the exact commits that work here rather than
    -- whatever each plugin's branch happens to be that day.
    lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json",

    -- Do not check for plugin updates automatically. Updates should be a
    -- deliberate act (:Lazy update) followed by committing the changed
    -- lockfile, so a breakage is always traceable to a commit.
    checker = { enabled = false },

    -- The config lives behind a junction; the file watcher gets noisy about
    -- that and it adds nothing when you are editing the config yourself.
    change_detection = { notify = false },

    -- Fall back to a built-in colourscheme during first install, before any
    -- real one is available.
    install = { colorscheme = { "habamax" } },
})
