return {
  {
    "williamboman/mason-lspconfig.nvim",
    optional = false,
    opts = function(_, opts)
      opts.ensure_installed = require("astrocore").list_insert_unique(opts.ensure_installed, { "elixirls" })
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter",
    optional = false,
    opts = function(_, opts)
      if opts.ensure_installed ~= "all" then
        opts.ensure_installed = require("astrocore").list_insert_unique(opts.ensure_installed, { "elixir", "heex" })
      end
    end,
  },
  {
    "AstroNvim/astrolsp",
    optional = false,
    opts = {
      config = {
        tailwindcss = {
          root_dir = function(fname)
            local root_pattern = require("lspconfig").util.root_pattern(
              "tailwind.config.mjs",
              "tailwind.config.cjs",
              "tailwind.config.js",
              "tailwind.config.ts",
              "postcss.config.js",
              "config/tailwind.config.js",
              "assets/tailwind.config.js",
              "apps/**/assets/tailwind.config.js"
            )
            return root_pattern(fname)
          end,
          init_options = {
            userLanguages = {
              heex = "html",
              elixir = "html",
            },
          },
          settings = {
            tailwindCSS = {
              experimental = {
                classRegex = {
                  'class[:]\\s*"([^"]*)"',
                },
              },
            },
          },
        },
      },
    },
  },
}
