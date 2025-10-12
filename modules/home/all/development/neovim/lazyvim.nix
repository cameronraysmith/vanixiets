{ pkgs, ... }:

{
  programs.lazyvim = {
    enable = true;
    extras = {
      ai = {
        copilot.enable = true;
      };
      coding = {
        blink.enable = true;
        mini-surround.enable = true;
        yanky.enable = true;
      };
      dap = {
        core.enable = true;
      };
      editor = {
        snacks_picker = {
          enable = true;
          db.sqlite3.enable = true;
        };
      };
      lang = {
        # docker.enable = true;
        json.enable = true;
        # markdown.enable = true; # render-markdown-nvim
        nix.enable = true;
        # nushell.enable = true;
        # ocaml.enable = true;
        python.enable = true;
        # rust.enable = true;
        # scala.enable = true;
        # sql.enable = true;
        # terraform.enable = true;
        # toml.enable = true;
        tailwind.enable = true;
        typescript.enable = true;
        # yaml.enable = true;
      };
      test = {
        core.enable = true;
      };
      util = {
        dot.enable = true;
      };
    };
    plugins = with pkgs.vimPlugins; [ ];
    pluginsFile = {
      "lazyvim.lua".source = ./lazyvim/lazyvim.lua;
    };
    lazySpecs = {
      extras.lang.python = [
        {
          ref = "linux-cultist/venv-selector.nvim";
          cmd = "VenvSelect";
          ft = "python";
          keys = [
            {
              lhs = "<leader>cv";
              rhs = "<cmd>VenvSelect<cr>";
              desc = "Select VirtualEnv";
              ft = "python";
            }
          ];
          opts = {
            options = {
              notify_user_on_venv_activation = true;
            };
          };
        }
      ];
    };
  };
}
