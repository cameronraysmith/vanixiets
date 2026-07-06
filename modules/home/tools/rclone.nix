{ ... }:
{
  flake.modules.homeManager.tools =
    { config, ... }:
    {
      programs.rclone = {
        enable = true;
        remotes = {
          gcs.config = {
            type = "google cloud storage";
            env_auth = true;
          };
          r2.config = {
            type = "s3";
            provider = "Cloudflare";
            env_auth = true;
            profile = "r2";
            shared_credentials_file = "${config.home.homeDirectory}/.aws/credentials";
            endpoint = "https://1ece4a9a8f092f8cbdd679d22b9ecb1f.r2.cloudflarestorage.com";
            region = "auto";
            no_check_bucket = true;
            acl = "private";
          };
        };
      };
    };
}
