{ ... }:
{
  imports = [ ./nix-user-chroot.nix ];

  programs.git.settings.credential.helper = "store";

  # Manage ssh-agent on Linux without systemd. keychain reuses a
  # running agent if one is found and starts one otherwise, then
  # exposes SSH_AUTH_SOCK via the shell integrations.
  programs.keychain = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
    keys = [ "id_ed25519" ];
  };
}
