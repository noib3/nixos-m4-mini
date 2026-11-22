# Partitions a disk as the real install does, then boots the minimal system
# from it directly, as m1n1 does: the initrd asks for the LUKS passphrase,
# mounts the btrfs subvolumes, and the system reaches multi-user.target. The
# test also installs boot.bin on the disk's EFI system partition.
{
  lib,
  qemu-utils,
  testers,
  self,
}:

let
  diskLayout = import ../hosts/disk-layout.nix;

  passphrase = "supersecret";

  # The disk both VMs attach, created by the test script. QEMU's start script
  # expands the path in the shell, and both VMs run in the test's build
  # directory.
  targetDrive = {
    file = ''"$NIX_BUILD_TOP"/target.img'';
    driveExtraOpts = {
      format = "raw";
      werror = "report";
    };
    deviceExtraOpts.serial = "target";
  };
in
testers.runNixOSTest {
  name = "vm-luks";

  node.pkgsReadOnly = false;

  nodes.installer =
    { pkgs, ... }:
    {
      virtualisation.qemu.drives = [ targetDrive ];
      environment.systemPackages = with pkgs; [
        btrfs-progs
        cryptsetup
        dosfstools
        gptfdisk
      ];
    };

  nodes.mini =
    { lib, ... }:
    {
      imports = [
        self.nixosModules.default
        ../hosts/minimal.nix
      ];

      hardware.m4mini.loadVendorFirmware = false;

      # The target disk replaces qemu-vm.nix's root disk image, and the
      # disk layout's filesystems replace its default ones. The Nix store
      # stays the host's.
      virtualisation = {
        diskImage = null;
        useDefaultFilesystems = false;
        mountHostNixStore = true;
        fileSystems = diskLayout.fileSystems;
        qemu.drives = [ targetDrive ];
        memorySize = 2048;
      };

      services.btrfs.autoScrub.enable = lib.mkForce false;

      # NixOS test VMs leave out switch-to-configuration by default, and the
      # test installs boot.bin through it.
      system.switch.enable = true;
    };

  testScript =
    { nodes, ... }:
    let
      system = nodes.mini.system.build.toplevel;
      m1n1Bin = "${self.packages.aarch64-linux.m1n1-gravity}/lib/m1n1/m1n1.bin";
    in
    ''
      import os
      import subprocess

      image = os.path.join(os.environ["NIX_BUILD_TOP"], "target.img")
      subprocess.run(["${lib.getExe' qemu-utils "qemu-img"}", "create", "-f", "raw", image, "4G"], check=True)

      with subtest("the installer partitions the disk"):
          installer.wait_for_unit("multi-user.target")
          disk = "/dev/disk/by-id/virtio-target"
          installer.succeed(
              f"sgdisk -n 1:0:+256M -t 1:ef00 -c 1:EFI -n 2:0:0 -t 2:8300 -c 2:nixos {disk}",
              "udevadm settle",
              "mkfs.vfat -F 32 -i 1E99841A /dev/disk/by-partlabel/EFI",
              "echo -n ${passphrase} | cryptsetup luksFormat --type luks2 --iter-time 1 -q /dev/disk/by-partlabel/nixos -",
              "echo -n ${passphrase} | cryptsetup open --key-file - /dev/disk/by-partlabel/nixos cryptroot",
              "mkfs.btrfs /dev/mapper/cryptroot",
              "mkdir -p /mnt",
              "mount /dev/mapper/cryptroot /mnt",
              "btrfs subvolume create /mnt/@root /mnt/@nix /mnt/@home",
              "umount /mnt",
              "cryptsetup close cryptroot",
              "sync",
          )
          installer.shutdown()

      with subtest("the initrd unlocks the disk and mounts the subvolumes"):
          mini.start()
          mini.wait_for_console_text("Please enter passphrase for disk")
          mini.send_console("${passphrase}\n")
          mini.wait_for_unit("multi-user.target")

          mounts = {
              "/": ("/dev/mapper/cryptroot", "btrfs", "subvol=/@root"),
              "/nix": ("/dev/mapper/cryptroot", "btrfs", "subvol=/@nix"),
              "/home": ("/dev/mapper/cryptroot", "btrfs", "subvol=/@home"),
              "/boot": ("/dev/vda1", "vfat", None),
          }
          for target, (source, fstype, option) in mounts.items():
              found = mini.succeed(f"findmnt -n -o SOURCE,FSTYPE,OPTIONS --mountpoint {target}").split()
              assert found[0].startswith(source), f"{target} is mounted from {found[0]}, not {source}"
              assert found[1] == fstype, f"{target} is {found[1]}, not {fstype}"
              if option is not None:
                  assert option in found[2].split(","), f"{target} lacks {option}: {found[2]}"

          mini.succeed("uname -r | grep -x 7.3.0")

      with subtest("installing the bootloader writes boot.bin"):
          mini.succeed("${system}/bin/switch-to-configuration boot")
          mini.succeed("cmp -n $(stat -c %s ${m1n1Bin}) ${m1n1Bin} /boot/m1n1/boot.bin")
          mini.succeed("grep -a -q 'chosen.bootargs=init=${system}/init ' /boot/m1n1/boot.bin")
          mini.fail("test -e /boot/m1n1/boot.bin.prev")

          # An identical boot.bin replaces nothing.
          mini.succeed("${system}/bin/switch-to-configuration boot")
          mini.fail("test -e /boot/m1n1/boot.bin.prev")
    '';
}
