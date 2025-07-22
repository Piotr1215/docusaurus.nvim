-- Minimal init.lua for running tests
local lazypath = "/tmp/lazy.nvim"

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

-- Add the plugin to runtimepath
vim.opt.rtp:prepend(".")

-- Setup dependencies
require("lazy").setup({
  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
  },
  {
    "nvim-lua/plenary.nvim",
  },
}, {
  root = "/tmp/lazy-test",
  lockfile = "/tmp/lazy-lock.json",
})