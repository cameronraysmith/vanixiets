{ ... }:
{
  flake.modules = {
    homeManager.development =
      {
        pkgs,
        config,
        lib,
        flake,
        ...
      }:
      {
        programs.lazyvim = {
          enable = true;

          # Prefer nixpkgs plugin versions for better Nix integration
          # Specifically helps blink.cmp get proper Rust fuzzy library from nixpkgs
          pluginSource = "nixpkgs";

          installCoreDependencies = true;

          extras = {
            ai.copilot.enable = true;
            coding = {
              blink.enable = true;
              mini_surround.enable = true;
              yanky.enable = true;
            };
            # TODO: Re-enable DAP when vscode-js-debug builds with clang 21.x
            # Disabled due to build failure in vscode-js-debug 1.104.0:
            # - Transitive dependency: vscode-js-debug -> microtime -> node-addon-api
            # - Error: enum cast of -1 to napi_typedarray_type is outside valid range [0,15]
            # - Clang 21.x rejects: static_cast<napi_typedarray_type>(-1) in napi.h:806
            # Check status:
            # - nixpkgs: pkgs/by-name/vs/vscode-js-debug/package.nix
            # - upstream: https://github.com/nodejs/node-addon-api/blob/main/napi.h#L806
            dap.core.enable = false;
            editor.snacks_picker.enable = true;
            lang = {
              astro.enable = true;
              go.enable = true;
              json.enable = true;
              markdown = {
                enable = true;
                installDependencies = true;
              };
              nix.enable = true;
              python.enable = true;
              tailwind.enable = true;
              typescript.enable = true;
            };
            test.core.enable = true;
            util.dot.enable = true;
          };

          extraPackages = with pkgs; [
            vimPlugins.blink-copilot
            # astro-language-server for Astro LSP support (Mason is disabled)
            astro-language-server
            # markdown-toc for conform.nvim formatter (no lazyvim-nix mapping exists)
            markdown-toc
          ];

          plugins = {
            lazyvim = ''
              return {
                {
                  "LazyVim/LazyVim",
                  opts = {
                    colorscheme = "catppuccin",
                  },
                },
              }
            '';

            treesitter = ''
              return {
                "nvim-treesitter/nvim-treesitter",
                opts = {
                  auto_install = false,
                },
              }
            '';

            # blink.cmp: use Lua fuzzy implementation as fallback
            # nixpkgs blink-cmp should have Rust binary, but Lua is safe fallback
            blink = ''
              return {
                {
                  "saghen/blink.cmp",
                  opts = {
                    fuzzy = {
                      -- Use "prefer_rust" to try Rust first, silently fall back to Lua
                      -- Use "lua" to always use Lua (no warnings)
                      implementation = "prefer_rust",
                    },
                  },
                },
              }
            '';

            # astro: configure LSP without Mason path lookup
            # Bypasses LazyVim.get_pkg_path() which checks Mason directories
            astro = ''
              return {
                {
                  "neovim/nvim-lspconfig",
                  opts = function(_, opts)
                    -- Configure astro LSP server directly (Mason is disabled)
                    opts.servers = opts.servers or {}
                    opts.servers.astro = opts.servers.astro or {}
                    opts.servers.astro.cmd = { "astro-ls", "--stdio" }
                  end,
                },
              }
            '';
          };
        };
      };
  };
}
