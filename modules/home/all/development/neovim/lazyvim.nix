{ pkgs, ... }:

{
  programs.lazyvim = {
    enable = true;
    ai_cmp = false; # Disable blink-cmp-copilot; we'll provide blink-copilot instead
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
        astro.enable = true;
        # docker.enable = true;
        go.enable = true;
        json.enable = true;
        markdown.enable = true;
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
    plugins = with pkgs.vimPlugins; [ blink-copilot ];
    pluginsFile = {
      "lazyvim.lua".source = ./lazyvim/lazyvim.lua;
    };
    lazySpecs = {
      nvim-treesitter = [
        {
          ref = "nvim-treesitter/nvim-treesitter";
          opts = {
            auto_install = false;
          };
        }
      ];
    };
  };
}
