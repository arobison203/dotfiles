---@type LazySpec
return {
  {
    "williamboman/mason-lspconfig.nvim",
    opts = {
      ensure_installed = {
        "lua_ls",
        "elixirls",
        "eslint",
      },
      -- never, ever automatically install prettier.
      automatic_installation = {
        exclude = {
          "prettier",
          "prettierd",
        },
      },
    },
  },
  -- use mason-null-ls to configure Formatters/Linter installation for null-ls sources
  {
    "jay-babu/mason-null-ls.nvim",
    -- overrides `require("mason-null-ls").setup(...)`
    opts = {
      ensure_installed = {
        "stylua",
        "eslint_d",
        -- add more arguments for adding more null-ls sources
      },
      automatic_installation = {
        exclude = {
          "prettier",
          "prettierd",
        },
      },
    },
  },
}
