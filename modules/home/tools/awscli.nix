{ ... }:
{
  flake.modules.homeManager.tools =
    { ... }:
    {
      programs.awscli = {
        enable = true;
        settings = {
          "default" = {
            region = "us-east-1";
            output = "json";
          };
          "profile b2" = {
            endpoint_url = "https://s3.us-east-005.backblazeb2.com";
          };
          "profile r2" = {
            endpoint_url = "https://1ece4a9a8f092f8cbdd679d22b9ecb1f.r2.cloudflarestorage.com";
            region = "auto";
          };
        };
      };
    };
}
