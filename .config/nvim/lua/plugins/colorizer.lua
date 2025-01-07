return {
  "catgoose/nvim-colorizer.lua",
  event = "BufReadPre",
  config = function()
    require("colorizer").setup({
      user_default_options = {
        mode = "virtualtext",
        virtualtext_inline = true,
        tailwind = "lsp" 
      }
    })
  end
}
