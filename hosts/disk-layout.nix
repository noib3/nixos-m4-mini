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
}
