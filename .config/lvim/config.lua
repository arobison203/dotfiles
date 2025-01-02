-- Read the docs: https://www.lunarvim.org/docs/configuration
-- Example configs: https://github.com/LunarVim/starter.lvim
-- Video Tutorials: https://www.youtube.com/watch?v=sFA9kX-Ud_c&list=PLhoH5vyxr6QqGu0i7tt_XoVK9v-KvZ3m6
-- Forum: https://www.reddit.com/r/lunarvim/
-- Discord: https://discord.com/invite/Xb9B4Ny

-- kj to exit insert mode is love, and life
lvim.keys.insert_mode["kj"] = "<Esc>"

-- x should not overwrite the register
lvim.keys.normal_mode["x"] = '"_x'

-- use the system clipboard
vim.o.clipboard = "unnamedplus"

lvim.plugins = {
  "catppuccin/nvim"
}

lvim.colorscheme = "catppuccin-mocha"

lvim.builtin.treesitter.ensure_installed = {
  "eex",
  "elixir",
  "erlang",
  "heex",
  "html",
}

