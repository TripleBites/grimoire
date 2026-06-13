-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Better Python/Rust indentation
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.softtabstop = 4
vim.opt.expandtab = true

-- Enable line wrapping for markdown and text
vim.opt.wrap = false

-- Faster update time for LSP
vim.opt.updatetime = 250
vim.opt.timeoutlen = 300

-- Better diff options
vim.opt.diffopt = { "internal", "filler", "closeoff", "linematch:60" }

-- Enable persistent undo
vim.opt.undofile = true

-- Smart case searching
vim.opt.smartcase = true
vim.opt.ignorecase = true

-- Better clipboard integration
vim.opt.clipboard = "unnamedplus"

-- Python host program (optional, speeds up some plugins)
-- vim.g.python3_host_prog = vim.fn.expand("~/.venv/bin/python")
