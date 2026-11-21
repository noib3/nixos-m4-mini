# Boots the minimal system's kernel and initrd in QEMU, directly as m1n1 does,
# and checks that it reaches multi-user.target on Gravity's kernel.
{
  testers,
  self,
}:

testers.runNixOSTest {
  name = "vm-boots";

  node.pkgsReadOnly = false;

  nodes.machine =
    { lib, ... }:
    {
      imports = [
        self.nixosModules.default
        ../hosts/minimal.nix
      ];

      # The test VM has no EFI system partition, and its root is a plain disk
      # image in place of the encrypted btrfs filesystem.
      hardware.m4mini = {
        writeBootBin = false;
        loadVendorFirmware = false;
      };
      boot.initrd.luks.devices = lib.mkForce { };
      services.btrfs.autoScrub.enable = lib.mkForce false;
    };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.succeed("uname -r | grep -x 7.3.0")
    machine.succeed("grep -w idle=nop /proc/cmdline")
    machine.succeed("getconf PAGESIZE >&2")
  '';
}
