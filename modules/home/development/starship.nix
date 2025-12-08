# Enhanced starship prompt configuration
# Note: starship-jj intentionally EXCLUDED (see rationale below)
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
        programs.starship = {
          enable = true;
          # catppuccin.enable = true;  # Optional: uncomment if using catppuccin theme
          settings = {
            command_timeout = 2000;
            aws.disabled = true;
            gcloud.disabled = true;

            # starship-jj INTENTIONALLY EXCLUDED
            # Rationale:
            # - Custom Rust package requiring full Rust toolchain compilation
            # - Long compile time (10-30 minutes depending on hardware)
            # - Non-essential functionality (enhanced jujutsu integration for prompt)
            # - Basic starship configuration provides 95% of value without starship-jj overhead
            # - Enhanced jujutsu prompt can be added later if needed without blocking deployment
            #
            # Original vanixiets configuration (commented out):
            # custom.jj = {
            #   command = "prompt";
            #   format = "$output";
            #   ignore_timeout = true;
            #   shell = [
            #     "starship-jj"
            #     "--ignore-working-copy"
            #     "starship"
            #   ];
            #   use_stdin = false;
            #   when = true;
            # };
          };
        };
      };
  };
}
