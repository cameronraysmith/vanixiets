# Starts crs58's LazyVim headless from the Neovim files his home generates,
# offline, and fails when lazy.nvim cannot map a Nix-linked plugin back to its
# spec or reports a failed init or config while the start-up plugins load.
#
# lazy.nvim loads a lazy plugin on require() only when Plugin.find, which
# names a plugin by the directory before /lua/, finds its spec. lazyvim-nix
# v16.0.2 linked every plugin as <owner>--<repo> (pfassina/lazyvim-nix#115), so
# require("trouble") from LazyVim's lualine opts returned the module without
# loading trouble.nvim, and lualine's config failed at every start; nixbot
# passed that bump (#4120) because nothing ran the editor.
#
# The probe asserts that mapping for every dev plugin with Lua modules, fires
# VeryLazy as a UI start does (lualine loads on it), and fails on any
# "Failed to ..." report from lazy.nvim. Plugins lazyvim-nix does not provide
# are cloned by lazy.nvim at run time; offline those clones fail and lazy.nvim
# reports "Too many rounds of missing plugins", which is not judged. Until
# lazyvim-nix v16.0.2 the generated init.lua bootstraps lazy.nvim from
# stdpath("data")/lazy/lazy.nvim, so that path links the lazy.nvim the home
# already ships, as a used machine has.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    lib.optionalAttrs (system == "x86_64-linux") {
      testSizes.checks = {
        # one headless Neovim start, about 1 s on stibnite
        lazyvim-startup = {
          class = "small";
          measured = false;
        };
      };
      checks.lazyvim-startup =
        let
          home = self.homeConfigurations."crs58@${system}".config;
          # Only the home's Neovim files, so the check does not wait on the
          # rest of home-manager-files.
          files = pkgs.linkFarm "lazyvim-startup-files" (
            map
              (file: {
                name = file.target;
                path = file.source;
              })
              (
                lib.filter (
                  file:
                  file.enable
                  && (lib.hasPrefix ".config/nvim/" file.target || lib.hasPrefix ".local/share/nvim/" file.target)
                ) (lib.attrValues home.home.file)
              )
          );
          probe = pkgs.writeText "lazyvim-startup.lua" ''
            vim.api.nvim_create_autocmd("VimEnter", {
              once = true,
              callback = function()
                local Config = require("lazy.core.config")
                local Plugin = require("lazy.core.plugin")
                local Util = require("lazy.core.util")
                -- lazy.nvim reports a failed init or config from a scheduled
                -- callback through Util.error, and LazyVim and noice.nvim replace
                -- vim.notify, so record the report itself. Reports scheduled
                -- during start-up run after this autocmd.
                local failures = {}
                local lazy_error = Util.error
                Util.error = function(msg, opts)
                  if type(msg) == "string" and msg:match("^Failed to ") then
                    table.insert(failures, msg)
                  end
                  return lazy_error(msg, opts)
                end
                local unmapped, mapped = {}, 0
                for name, plugin in pairs(Config.plugins) do
                  if plugin.dev and vim.fn.isdirectory(plugin.dir .. "/lua") == 1 then
                    if Plugin.find(plugin.dir .. "/lua/probe.lua") == plugin then
                      mapped = mapped + 1
                    else
                      table.insert(unmapped, name .. " at " .. plugin.dir)
                    end
                  end
                end
                vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy", modeline = false })
                -- Queued after the reports of the plugins VeryLazy loaded.
                vim.schedule(function()
                  local lualine = Config.plugins["lualine.nvim"]
                  local out = io.stdout
                  table.sort(unmapped)
                  out:write(("\ndev plugins mapped back to their spec: %d\n"):format(mapped))
                  for _, line in ipairs(unmapped) do
                    out:write("unmapped: " .. line .. "\n")
                  end
                  for _, msg in ipairs(failures) do
                    out:write("lazy.nvim: " .. msg .. "\n")
                  end
                  if not (lualine and lualine._.loaded) then
                    out:write("lualine.nvim did not load on VeryLazy\n")
                  end
                  local ok = mapped > 0 and #unmapped == 0 and #failures == 0 and lualine and lualine._.loaded ~= nil
                  out:write(ok and "lazyvim-startup: ok\n" or "lazyvim-startup: failed\n")
                  vim.cmd(ok and "qa!" or "cq!")
                end)
              end,
            })
          '';
        in
        pkgs.runCommand "lazyvim-startup" { } ''
          export HOME=$TMPDIR/home
          data=$HOME/.local/share/nvim
          mkdir -p "$HOME/.config" "$data/site" "$data/lazy"
          cp -RL ${files}/.config/nvim "$HOME/.config/nvim"
          chmod -R u+w "$HOME/.config/nvim"
          for entry in ${files}/.local/share/nvim/site/*; do
            ln -s "$entry" "$data/site/"
          done
          ln -s ${files}/.local/share/nvim/site/pack/hm/start/lazy.nvim "$data/lazy/lazy.nvim"
          cd "$TMPDIR"
          status=0
          timeout 50 ${lib.getExe home.programs.neovim.finalPackage} --headless \
            --cmd "luafile ${probe}" > log 2>&1 || status=$?
          if [ "$status" -ne 0 ] || ! grep -qx 'lazyvim-startup: ok' log; then
            cat log
            echo "lazyvim-startup: nvim exited $status" >&2
            exit 1
          fi
          grep -E '^(dev plugins|lazyvim-startup)' log
          touch $out
        '';
    };
}
