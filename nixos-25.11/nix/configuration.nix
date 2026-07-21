# System configuration baked into the nixos-25.11 template.
# Credentials: vmlab / vmlab (passwordless sudo via wheel); root is locked.
{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nixos";
  networking.useDHCP = true;

  # vmlab guest agent: static musl binary copied from the VMLAB bootstrap
  # ISO by nix/install.sh; declared here so activation owns the unit.
  systemd.services.vmlab-agent = {
    description = "vmlab guest agent (terminals/exec/files over virtio-serial)";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "/usr/local/lib/vmlab/vmlab-agent";
      Restart = "always";
      RestartSec = 2;
    };
  };

  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = true;

  users.users.vmlab = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    hashedPassword = "$6$msm7717SQBFhDWd8$Or75iQS6wZyqEqcm3QhWTz8gktMIHyvDmqWhs8rATckOUtgRZyTfuQ5C2lPMKnN9PQGF5FxJwYDaU6wGafA/z0";
  };
  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "25.11";
}
