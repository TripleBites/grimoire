-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

local map = vim.keymap.set

-- Quick save and quit
map("n", "<leader>w", "<cmd>w<cr>", { desc = "Save" })
map("n", "<leader>q", "<cmd>q<cr>", { desc = "Quit" })

-- Rust-specific keymaps
map("n", "<leader>cr", "<cmd>RustLsp runnables<cr>", { desc = "Rust Runnables" })
map("n", "<leader>cR", "<cmd>RustLsp rebuildProcMacros<cr>", { desc = "Rebuild Rust Proc Macros" })
map("n", "<leader>ce", "<cmd>RustLsp expandMacro<cr>", { desc = "Expand Rust Macro" })
map("n", "<leader>cD", "<cmd>RustLsp openDocs<cr>", { desc = "Open Rust Docs" })

-- Python-specific keymaps
map("n", "<leader>cp", function()
  require("dap-python").test_method()
end, { desc = "Python Test Method" })

-- Cargo commands
map("n", "<leader>cb", "<cmd>!cargo build<cr>", { desc = "Cargo Build" })
map("n", "<leader>ct", "<cmd>!cargo test<cr>", { desc = "Cargo Test" })
map("n", "<leader>cc", "<cmd>!cargo check<cr>", { desc = "Cargo Check" })
map("n", "<leader>cR", "<cmd>!cargo run<cr>", { desc = "Cargo Run" })
