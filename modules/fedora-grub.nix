# TODO(fedora): transitional, for the first install only. Remove this module
# once NixOS boots from m1n1/boot.bin on the mini and Gravity's Fedora is
# deleted.
#
# Boots NixOS through Gravity's Fedora: GRUB stays the bootloader, and NixOS's
# bootloader hook writes its kernel, initrd and a Boot Loader Spec entry with
# ID "nixos" to Fedora's /boot. GRUB's default entry stays Fedora's, and
# `grub2-reboot nixos` boots NixOS once.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hardware.m4mini.fedoraGrub;

  installHook = pkgs.writeShellApplication {
    name = "install-fedora-grub-entry";
    runtimeInputs = with pkgs; [
      coreutils
      gzip
      util-linux
    ];
    text = ''
      system=$1
      boot=${lib.escapeShellArg cfg.mountPoint}

      if ! mountpoint -q "$boot"; then
        echo "install-fedora-grub-entry: Fedora's /boot is not mounted at $boot" >&2
        exit 1
      fi

      ${config.hardware.m4mini.initrdSecretsSetup}

      mkdir -p "$boot/nixos" "$boot/loader/entries"
      cp "$system/initrd" "$boot/nixos/initrd.new"
      chmod u+w "$boot/nixos/initrd.new"
      ${config.system.build.initialRamdiskSecretAppender}/bin/append-initrd-secrets "$boot/nixos/initrd.new"
      cp "$system/kernel" "$boot/nixos/Image.new"
      mv "$boot/nixos/initrd.new" "$boot/nixos/initrd"
      mv "$boot/nixos/Image.new" "$boot/nixos/Image"

      cat > "$boot/loader/entries/nixos.conf.new" <<EOF
      title NixOS
      version $(basename "$system")
      linux /nixos/Image
      initrd /nixos/initrd
      options init=$system/init $(cat "$system/kernel-params")
      EOF
      mv "$boot/loader/entries/nixos.conf.new" "$boot/loader/entries/nixos.conf"
      sync -f "$boot/nixos/Image"
    '';
  };
in
{
  options.hardware.m4mini.fedoraGrub = {
    enable = lib.mkEnableOption "booting NixOS through Gravity's Fedora GRUB";

    device = lib.mkOption {
      type = lib.types.str;
      # TODO(fedora): confirm the label on the mini. Kiwi, which builds Gravity's
      # image, labels the boot partition BOOT by default.
      default = "/dev/disk/by-label/BOOT";
      description = "The block device of Gravity's Fedora /boot partition.";
    };

    mountPoint = lib.mkOption {
      type = lib.types.str;
      default = "/fedora-boot";
      description = "The mount point of Gravity's Fedora /boot partition.";
    };
  };

  config = lib.mkIf (config.hardware.m4mini.enable && cfg.enable) {
    # GRUB loads the kernel from Fedora's /boot, and m1n1/boot.bin stays
    # Gravity's.
    hardware.m4mini.writeBootBin = false;
    boot.loader.external.installHook = lib.mkForce (lib.getExe installHook);
    boot.loader.supportsInitrdSecrets = lib.mkForce true;

    fileSystems.${cfg.mountPoint} = {
      inherit (cfg) device;
      fsType = "ext4";
      options = [ "nofail" ];
    };
  };
}
