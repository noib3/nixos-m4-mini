# Partitions a disk as the real install does, then boots the minimal system
# from it directly, as m1n1 does. The first boot uses the system's initrd and
# answers the LUKS prompt on the console, then installs boot.bin on the disk's
# EFI system partition. The second boot uses the initrd inside that boot.bin,
# with its appended secrets, and answers the prompt over SSH from the test
# driver, through a port QEMU forwards into the VM. Both boots run bluetoothd in
# the initrd, which has no adapter to find here.
{
  lib,
  openssh,
  path,
  python3,
  qemu-utils,
  testers,
  self,
}:

let
  diskLayout = import ../hosts/disk-layout.nix;

  passphrase = "supersecret";

  # nixpkgs' test key pair for initrd SSH.
  clientKey = "${path}/nixos/tests/initrd-network-ssh/id_ed25519";

  # The port on the test driver's host that QEMU forwards to the initrd's SSH
  # server.
  sshPort = 2222;

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

      # SSH in the initrd, configured as a user would. The m4mini module
      # makes it work on the mini.
      boot.initrd.network.ssh = {
        enable = true;
        port = sshPort;
        authorizedKeys = [ (lib.readFile "${clientKey}.pub") ];
        hostKeys = [ "/etc/ssh/initrd_ssh_host_ed25519_key" ];
      };
      boot.initrd.systemd.network = {
        enable = true;
        networks."10-ethernet" = {
          matchConfig.Type = "ether";
          networkConfig.DHCP = "yes";
        };
      };

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
        # The initrd gets an address on QEMU's user-mode network over DHCP.
        forwardPorts = [
          {
            from = "host";
            host.port = sshPort;
            guest.port = sshPort;
          }
        ];
      };

      services.btrfs.autoScrub.enable = lib.mkForce false;

      # qemu-vm.nix turns initrd secrets off at priority 10, since QEMU boots
      # the system's initrd. The mini's boot.bin hook appends them, and the
      # second boot uses boot.bin's initrd.
      boot.loader.supportsInitrdSecrets = lib.mkOverride 5 true;

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

      build = os.environ["NIX_BUILD_TOP"]
      image = os.path.join(build, "target.img")
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
          mini.succeed("journalctl -b --grep 'Started Bluetooth in the initrd'")

      with subtest("installing the bootloader writes boot.bin with the initrd secrets"):
          mini.succeed("${system}/bin/switch-to-configuration boot")
          mini.fail("test -e /boot/m1n1/boot.bin.prev")

          # An identical boot.bin replaces nothing.
          mini.succeed("${system}/bin/switch-to-configuration boot")
          mini.fail("test -e /boot/m1n1/boot.bin.prev")

          mini.copy_from_machine("/boot/m1n1/boot.bin")
          initrd = os.path.join(build, "initrd-with-secrets.gz")
          subprocess.run(
              [
                  "${lib.getExe python3}", "-I", "${./boot-bin-layout.py}",
                  "${m1n1Bin}", os.path.join(os.environ["out"], "boot.bin"), "${system}",
                  "--initrd-contains", ".initrd-secrets/var/lib/bluetooth",
                  "--initrd-contains", ".initrd-secrets/etc/ssh/initrd_ssh_host_ed25519_key",
                  "--initrd-out", initrd,
              ],
              check=True,
          )
          mini.shutdown()

      with subtest("the boot.bin initrd unlocks the disk over SSH"):
          # QEMU takes the last -initrd, so this replaces the system's initrd
          # with the one from boot.bin.
          os.environ["QEMU_OPTS"] = f"-initrd {initrd}"
          mini.start()

          # ssh refuses a private key other users can read.
          key = os.path.join(build, "client-key")
          with open("${clientKey}", "rb") as source, open(key, "wb") as target:
              target.write(source.read())
          os.chmod(key, 0o600)
          ssh = [
              "${lib.getExe' openssh "ssh"}", "-i", key,
              "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
              "-o", "ConnectTimeout=5", "-p", "${toString sshPort}", "root@127.0.0.1",
          ]

          def initrd_ssh_is_up(_):
              return subprocess.run(ssh + ["true"], capture_output=True).returncode == 0

          retry(initrd_ssh_is_up, timeout_seconds=600)
          subprocess.run(
              ssh + ["-tt", "systemd-tty-ask-password-agent", "--query"],
              input=b"${passphrase}\n",
              check=True,
              timeout=120,
          )
          mini.wait_for_unit("multi-user.target")
          mini.succeed("journalctl -b --grep 'Started Bluetooth in the initrd'")
          mini.succeed("findmnt -n --mountpoint / -o SOURCE | grep -q '^/dev/mapper/cryptroot'")
    '';
}
