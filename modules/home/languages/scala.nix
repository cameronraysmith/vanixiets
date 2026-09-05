{ ... }:
{
  flake.modules.homeManager.languages =
    { pkgs, ... }:
    let
      # pin sbt to specific JDK
      jdk = pkgs.temurin-bin-21;
      sbtWithJdk = pkgs.sbt.override { jre = jdk; };
    in
    {
      home.packages = [ sbtWithJdk ];
    };
}
