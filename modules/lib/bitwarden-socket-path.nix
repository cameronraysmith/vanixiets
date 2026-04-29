# Bitwarden Desktop SSH agent socket path by platform
# Source: https://bitwarden.com/help/ssh-agent/#tab-macos-6VN1DmoAVFvm7ZWD95curS
{ ... }:
{
  flake.lib.bitwardenSocketPath =
    {
      homeDirectory,
      isDarwin,
    }:
    if isDarwin then
      "${homeDirectory}/Library/Containers/com.bitwarden.desktop/Data/.bitwarden-ssh-agent.sock"
    else
      "${homeDirectory}/.bitwarden-ssh-agent.sock";
}
