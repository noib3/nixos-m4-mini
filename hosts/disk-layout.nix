# The mini's disk layout. The NixOS partition, GPT name "nixos", is a LUKS2
# container holding one btrfs filesystem with the subvolumes @root, @nix and
# @home. More LUKS containers can join the filesystem later with
# `btrfs device add`, and systemd's initrd tries the first passphrase on all of
# them.
{
  luksDevices.cryptroot = {
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

      # The device is hardware.m4mini.espDevice, the udev link to the EFI
      # system partition named by the device tree.
      "/boot" = {
        device = "/dev/disk/gravity-esp";
        fsType = "vfat";
        options = [
          "fmask=0077"
          "dmask=0077"
        ];
      };
    };
}
