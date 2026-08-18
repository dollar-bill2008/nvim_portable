-- nvim-autopairs: closes brackets, quotes and the like as you type.
--
-- Typing ( gives you (), typing " gives you "", and typing the closing
-- character where one already sits steps over it rather than inserting a
-- second. Backspace on an empty pair removes both halves.
--
-- WHY check_ts MATTERS
-- Naive auto-pairing is actively annoying in prose and inside strings: typing
-- an apostrophe in a comment should not produce ''. check_ts asks treesitter
-- what the cursor is actually inside, and skips pairing in strings and
-- comments. This only works because treesitter parsers are installed -- see
-- lua/plugins/treesitter.lua. Without them it silently degrades to naive
-- pairing rather than breaking.

return {
    "windwp/nvim-autopairs",

    -- Nothing to do until you are typing, so defer until the first insert.
    event = "InsertEnter",

    opts = {
        -- Use treesitter to decide where pairing is appropriate.
        check_ts = true,
        ts_config = {
            -- Node types where pairing should be suppressed, per language.
            lua = { "string", "source" },
            python = { "string" },
            javascript = { "string", "template_string" },
        },

        -- Prompt buffers are not code, and pairing in them fights the picker.
        disable_filetype = { "TelescopePrompt", "neo-tree", "neo-tree-popup" },

        -- Do not add a closing pair when the very next character is one of
        -- these -- otherwise typing ( before an existing word gives you (word).
        ignored_next_char = [=[[%w%%%'%[%"%.%`%$]]=],

        -- Wrap the text to the right of the cursor in a pair, on Alt-e. Useful
        -- for adding a call around an existing expression without retyping it.
        fast_wrap = {
            map = "<M-e>",
            chars = { "{", "[", "(", '"', "'" },
            end_key = "$",
            keys = "qwertyuiopzxcvbnmasdfghjkl",
        },
    },
}
