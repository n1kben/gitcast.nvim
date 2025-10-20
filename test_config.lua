-- test_config.lua - Test configuration for GitCast.nvim
-- Run with: nvim --clean -u test_config.lua

-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Configure lazy.nvim with GitCast
require("lazy").setup({
  {
    -- Use local development version
    dir = vim.fn.getcwd(),
    name = "gitcast.nvim",
    config = function()
      require("gitcast").setup({
        performance_tracking = true,  -- Enable for testing
      })
    end,
    cmd = "GitCast",
    keys = {
      { "<leader>gg", "<cmd>GitCast<cr>", desc = "Open GitCast dashboard" },
    },
  },
  -- Add snacks.nvim for dd() function
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {
      debug = { enabled = true },
    },
  },
})

-- Basic configuration
vim.g.mapleader = " "
vim.opt.number = true
vim.opt.signcolumn = "yes"

-- Test message
vim.defer_fn(function()
  print("GitCast.nvim test environment loaded!")
  print("Use :GitCast or <leader>gg to open the dashboard")
end, 100)