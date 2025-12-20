# MCP server configurations for Claude Code CLI
{ ... }:
{
  flake.modules = {
    homeManager.ai =
      {
        pkgs,
        config,
        lib,
        flake,
        ...
      }:
      let
        home = config.home.homeDirectory;
      in
      {
        # Ensure ~/.mcp directory exists before templates are written
        home.file.".mcp/.keep".text = "";

        # MCP servers using sops-nix for API keys
        # 3 MCP servers use secrets: firecrawl, huggingface, agent-mail

        # Generate MCP server configuration files using sops templates
        # Each server gets its own JSON file for manual composition via --mcp-config
        sops.templates = {
          # Firecrawl: Web scraping with API key
          # Pattern: env block (secure - secrets not in argv)
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
                    FIRECRAWL_API_KEY = config.sops.placeholder."firecrawl-api-key";
                  };
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
                    "Authorization: Bearer ${config.sops.placeholder."huggingface-token"}"
                  ];
                };
              };
            };
          };

          # Agent Mail: Git-backed agent coordination messaging
          # Pattern: HTTP transport with Bearer token authentication
          # Server must be running before client can connect
          mcp-agent-mail = {
            mode = "0400";
            path = "${home}/.mcp/agent-mail.json";
            content = builtins.toJSON {
              mcpServers = {
                "mcp-agent-mail" = {
                  type = "http";
                  url = "http://127.0.0.1:8765/mcp/";
                  headers = {
                    Authorization = "Bearer ${config.sops.placeholder."mcp-agent-mail-bearer-token"}";
                  };
                };
              };
            };
          };
        };

        # --- Servers WITHOUT secrets (8) ---

        # MCP server configuration files (servers without secrets)
        # Each server gets its own JSON file for manual composition via --mcp-config

        # Chrome DevTools: Browser automation
        home.file.".mcp/chrome.json".text = builtins.toJSON {
          mcpServers = {
            "chrome-devtools" = {
              command = "npx";
              args = [ "chrome-devtools-mcp@latest" ];
            };
          };
        };

        # Cloudflare: Documentation via SSE remote
        home.file.".mcp/cloudflare.json".text = builtins.toJSON {
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

        # DuckDB: In-memory database via uvx
        home.file.".mcp/duckdb.json".text = builtins.toJSON {
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

        # Historian: Claude conversation history
        home.file.".mcp/historian.json".text = builtins.toJSON {
          mcpServers = {
            "claude-historian" = {
              type = "stdio";
              command = "npx";
              args = [ "claude-historian" ];
              env = { };
            };
          };
        };

        # MCP Prompt Server: Local project-based prompts
        # SPECIAL CASE: Uses local workspace project, not npm package
        # Requires separate build: cd ~/projects/planning-workspace/mcp-prompts-server && npm run build
        home.file.".mcp/mcp-prompt-server.json".text = builtins.toJSON {
          mcpServers = {
            "mcp-prompt-server" = {
              command = "node";
              args = [
                "${home}/projects/planning-workspace/mcp-prompts-server/dist/server.js"
              ];
            };
          };
        };

        # NixOS: Nix ecosystem tools via uvx
        home.file.".mcp/nixos.json".text = builtins.toJSON {
          mcpServers = {
            nixos = {
              command = "uvx";
              args = [ "mcp-nixos" ];
            };
          };
        };

        # Playwright: Browser automation
        home.file.".mcp/playwright.json".text = builtins.toJSON {
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

        # Terraform: Infrastructure as code via docker
        home.file.".mcp/terraform.json".text = builtins.toJSON {
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

        # Google Cloud: GCP operations via gcloud CLI
        home.file.".mcp/gcloud.json".text = builtins.toJSON {
          mcpServers = {
            gcloud = {
              command = "npx";
              args = [
                "-y"
                "@google-cloud/gcloud-mcp"
              ];
            };
          };
        };

        # Google Cloud Storage: GCS bucket operations via gcloud CLI
        home.file.".mcp/gcs.json".text = builtins.toJSON {
          mcpServers = {
            storage = {
              command = "npx";
              args = [
                "-y"
                "@google-cloud/storage-mcp"
              ];
            };
          };
        };

        # Runtime dependencies for MCP servers
        home.packages = with pkgs; [
          nodejs_22
          # For npx: firecrawl, huggingface, chrome, cloudflare, historian, playwright, gcloud, gcs
          # Also provides node binary for mcp-prompt-server
          uv # For uvx: duckdb, nixos
          docker # For terraform container (requires OrbStack, Docker Desktop, or Colima on macOS)
          # google-cloud-sdk installed in modules/home/all/terminal/default.nix (required for gcloud/gcs MCP)
        ];
      };
  };
}
