return {
  {
    "williamboman/mason-lspconfig.nvim",
    optional = false,
    opts = function(_, opts)
      -- ensure the language server is installed
      opts.ensure_installed = require("astrocore").list_insert_unique(opts.ensure_installed, { "elixirls" })
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter",
    optional = false,
    opts = function(_, opts)
      if opts.ensure_installed ~= "all" then
        opts.ensure_installed =
          -- ensure tresitter has the required parsers installed
          require("astrocore").list_insert_unique(opts.ensure_installed, { "elixir", "eex", "heex", "html" })
      end
    end,
  },
}
