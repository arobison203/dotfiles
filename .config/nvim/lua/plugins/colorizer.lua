return {
  "catgoose/nvim-colorizer.lua",
  event = "BufReadPre",
  config = function()
    require("colorizer").setup {
      user_default_option = {
        tailwind = "lsp",
      },
    }
  end,
}
