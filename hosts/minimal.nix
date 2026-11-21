# The smallest system to bring up on the mini: a console and SSH login,
# Ethernet, Wi-Fi and Bluetooth, and Nix with flakes for switching to the
# full configuration.
{ pkgs, ... }:

{
  hardware.m4mini.enable = true;

  networking.hostName = "mini";

  # The NixOS partition, GPT name "nixos", is a LUKS2 container holding one
  # btrfs filesystem with the subvolumes @root, @nix and @home. More LUKS
  # containers can join the filesystem later with `btrfs device add`, and
  # systemd's initrd tries the first passphrase on all of them.
  boot.initrd.luks.devices.cryptroot = {
    device = "/dev/disk/by-partlabel/nixos";
    allowDiscards = true;
    bypassWorkqueues = true;
  };

  fileSystems =
    let
      subvolume = name: {
        device = "/dev/mapper/cryptroot";
        fsType = "btrfs";
        options = [
          "subvol=${name}"
          "compress=zstd"
          "noatime"
        ];
      };
    in
    {
      "/" = subvolume "@root";
      "/nix" = subvolume "@nix";
      "/home" = subvolume "@home";

      # Gravity's installer formats the EFI system partition with volume ID
      # 0x1e99841a.
      "/boot" = {
        device = "/dev/disk/by-uuid/1E99-841A";
        fsType = "vfat";
        options = [
          "fmask=0077"
          "dmask=0077"
        ];
      };
    };

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
