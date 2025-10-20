{
  config,
  pkgs,
  lib,
  flake,
  ...
}:
let
  home = config.home.homeDirectory;
  # Look up user config based on home.username (set by each home configuration)
  user = flake.config.${config.home.username};
  # Construct user-specific secrets path
  # Secrets file structure: secrets/users/{sopsIdentifier}/mcp-api-keys.yaml
  # Requires corresponding .sops.yaml rule: path_regex: secrets/users/{sopsIdentifier}/.*\.yaml$
  mcpSecretsFile = flake.inputs.self + "/secrets/users/${user.sopsIdentifier}/mcp-api-keys.yaml";
in
{
  # Ensure ~/.mcp directory exists before templates are written
  home.file.".mcp/.keep".text = "";

  # Define sops secrets for the 3 MCP servers requiring API keys
  sops.secrets = {
    "mcp-firecrawl-api-key" = {
      sopsFile = mcpSecretsFile;
      key = "firecrawl-api-key";
    };
    "mcp-huggingface-token" = {
      sopsFile = mcpSecretsFile;
      key = "huggingface-token";
    };
    "mcp-context7-api-key" = {
      sopsFile = mcpSecretsFile;
      key = "context7-api-key";
    };
  };

  # Generate MCP server configuration files using sops templates
  # Each server gets its own JSON file for manual composition via --mcp-config
  sops.templates = {
    # --- Servers WITH secrets (3) ---

    # Firecrawl: Web scraping with API key
    # Pattern: env block (secure - secrets not in argv)
    # Note: Improved from backup which used env wrapper (exposed secrets in process args)
    mcp-firecrawl = {
      mode = "0400";
      path = "${home}/.mcp/firecrawl.json";
      content = builtins.toJSON {
        mcpServers = {
          firecrawl = {
            type = "stdio";
            command = "npx";
            args = [
              "-y"
              "firecrawl-mcp"
            ];
            env = {
              FIRECRAWL_API_KEY = config.sops.placeholder."mcp-firecrawl-api-key";
            };
          };
        };
      };
    };

    # Context7: Context management with API key
    # Pattern: --api-key argument
    mcp-context7 = {
      mode = "0400";
      path = "${home}/.mcp/context7.json";
      content = builtins.toJSON {
        mcpServers = {
          context7 = {
            type = "stdio";
            command = "npx";
            args = [
              "-y"
              "@upstash/context7-mcp"
              "--api-key"
              config.sops.placeholder."mcp-context7-api-key"
            ];
            env = { };
          };
        };
      };
    };

    # Hugging Face: AI model access with token
    # Pattern: --header Authorization: Bearer <token>
    # Note: mcp-remote requires full header value as single arg (exposes token in process args)
    mcp-huggingface = {
      mode = "0400";
      path = "${home}/.mcp/huggingface.json";
      content = builtins.toJSON {
        mcpServers = {
          "hf-mcp-server" = {
            command = "npx";
            args = [
              "mcp-remote"
              "https://huggingface.co/mcp"
              "--header"
              "Authorization: Bearer ${config.sops.placeholder."mcp-huggingface-token"}"
            ];
          };
        };
      };
    };

    # --- Servers WITHOUT secrets (8) ---

    # Chrome DevTools: Browser automation
    mcp-chrome = {
      mode = "0400";
      path = "${home}/.mcp/chrome.json";
      content = builtins.toJSON {
        mcpServers = {
          "chrome-devtools" = {
            command = "npx";
            args = [ "chrome-devtools-mcp@latest" ];
          };
        };
      };
    };

    # Cloudflare: Documentation via SSE remote
    mcp-cloudflare = {
      mode = "0400";
      path = "${home}/.mcp/cloudflare.json";
      content = builtins.toJSON {
        mcpServers = {
          cloudflare = {
            command = "npx";
            args = [
              "mcp-remote"
              "https://docs.mcp.cloudflare.com/sse"
            ];
          };
        };
      };
    };

    # DuckDB: In-memory database via uvx
    mcp-duckdb = {
      mode = "0400";
      path = "${home}/.mcp/duckdb.json";
      content = builtins.toJSON {
        mcpServers = {
          "mcp-server-motherduck" = {
            command = "uvx";
            args = [
              "mcp-server-motherduck"
              "--db-path"
              ":memory:"
            ];
          };
        };
      };
    };

    # Historian: Claude conversation history
    mcp-historian = {
      mode = "0400";
      path = "${home}/.mcp/historian.json";
      content = builtins.toJSON {
        mcpServers = {
          "claude-historian" = {
            type = "stdio";
            command = "npx";
            args = [ "claude-historian" ];
            env = { };
          };
        };
      };
    };

    # MCP Prompt Server: Local project-based prompts
    # SPECIAL CASE: Uses local workspace project, not npm package
    # Requires separate build: cd ~/projects/planning-workspace/mcp-prompts-server && npm run build
    mcp-mcp-prompt-server = {
      mode = "0400";
      path = "${home}/.mcp/mcp-prompt-server.json";
      content = builtins.toJSON {
        mcpServers = {
          "mcp-prompt-server" = {
            command = "node";
            args = [
              "${home}/projects/planning-workspace/mcp-prompts-server/dist/server.js"
            ];
          };
        };
      };
    };

    # NixOS: Nix ecosystem tools via uvx
    mcp-nixos = {
      mode = "0400";
      path = "${home}/.mcp/nixos.json";
      content = builtins.toJSON {
        mcpServers = {
          nixos = {
            command = "uvx";
            args = [ "mcp-nixos" ];
          };
        };
      };
    };

    # Playwright: Browser automation
    mcp-playwright = {
      mode = "0400";
      path = "${home}/.mcp/playwright.json";
      content = builtins.toJSON {
        mcpServers = {
          playwright = {
            type = "stdio";
            command = "npx";
            args = [
              "@playwright/mcp@latest"
              "--extension"
            ];
            env = { };
          };
        };
      };
    };

    # Terraform: Infrastructure as code via docker
    mcp-terraform = {
      mode = "0400";
      path = "${home}/.mcp/terraform.json";
      content = builtins.toJSON {
        mcpServers = {
          terraform = {
            type = "stdio";
            command = "docker";
            args = [
              "run"
              "-i"
              "--rm"
              "hashicorp/terraform-mcp-server"
            ];
            env = { };
          };
        };
      };
    };
  };

  # Runtime dependencies for MCP servers
  home.packages = with pkgs; [
    nodejs_22
    # For npx: firecrawl, huggingface, chrome, cloudflare, historian, playwright
    # Also provides node binary for mcp-prompt-server
    uv # For uvx: duckdb, nixos
    docker # For terraform container (requires OrbStack, Docker Desktop, or Colima on macOS)
  ];
}
