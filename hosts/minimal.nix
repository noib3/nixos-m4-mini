# The smallest system to bring up on the mini: a console and SSH login,
# Ethernet, Wi-Fi and Bluetooth, and Nix with flakes for switching to the
# full configuration.
{ pkgs, ... }:

let
  diskLayout = import ./disk-layout.nix;
in
{
  hardware.m4mini.enable = true;

  networking.hostName = "mini";

  boot.initrd.luks.devices = diskLayout.luksDevices;
  fileSystems = diskLayout.fileSystems;

  services.btrfs.autoScrub.enable = true;

  networking.networkmanager.enable = true;
  hardware.bluetooth.enable = true;

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  users.users.noib3 = {
    isNormalUser = true;
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    # The password of the first login. Change it with passwd.
    initialPassword = "nixos";
    openssh.authorizedKeys.keys = [ ];
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  environment.systemPackages = with pkgs; [
    git
    iw
    pciutils
    usbutils
  ];

  system.stateVersion = "26.11";
}
