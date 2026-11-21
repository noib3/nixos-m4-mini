# The minimal system as a QEMU virtual machine on the Mac. QEMU starts the
# kernel and initrd directly, as m1n1 does on the mini, so the VM boots the
# same kernel, initrd and command line without U-Boot or an EFI bootloader.
{ lib, modulesPath, ... }:

{
  imports = [ "${modulesPath}/virtualisation/qemu-vm.nix" ];

  virtualisation = {
    graphics = false;
    cores = 4;
    memorySize = 4096;
    diskSize = 8192;
  };

  # The VM has no EFI system partition, and qemu-vm.nix replaces the encrypted
  # btrfs root with a plain disk image.
  hardware.m4mini = {
    writeBootBin = false;
    loadVendorFirmware = false;
  };
  boot.initrd.luks.devices = lib.mkForce { };
  services.btrfs.autoScrub.enable = lib.mkForce false;

  services.getty.autologinUser = "noib3";
}
