# Boots the system straight from m1n1, without U-Boot or an EFI bootloader.
# Each generation's kernel, initrd and command line go into m1n1/boot.bin on
# the EFI system partition, and the boot.bin it replaces is kept as
# m1n1/boot.bin.prev.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hardware.m4mini;

  mkBootBin = lib.getExe pkgs.mk-m1n1-boot-bin;
  m1n1Bin = "${pkgs.m1n1-gravity}/lib/m1n1/m1n1.bin";

  installHook = pkgs.writeShellApplication {
    name = "install-m1n1-boot-bin";
    runtimeInputs = with pkgs; [
      coreutils
      diffutils
      util-linux
    ];
    text = ''
      system=$1
      esp=${lib.escapeShellArg cfg.espMountPoint}

      if ! mountpoint -q "$esp"; then
        echo "install-m1n1-boot-bin: $esp is not mounted" >&2
        exit 1
      fi

      mkdir -p "$esp/m1n1"
      ${mkBootBin} ${m1n1Bin} ${lib.escapeShellArg cfg.deviceTree} "$system" "$esp/m1n1/boot.bin.new"

      if [ -e "$esp/m1n1/boot.bin" ] && cmp -s "$esp/m1n1/boot.bin" "$esp/m1n1/boot.bin.new"; then
        rm "$esp/m1n1/boot.bin.new"
        exit 0
      fi

      if [ -e "$esp/m1n1/boot.bin" ]; then
        mv "$esp/m1n1/boot.bin" "$esp/m1n1/boot.bin.prev"
      fi
      mv "$esp/m1n1/boot.bin.new" "$esp/m1n1/boot.bin"
      sync -f "$esp/m1n1/boot.bin"
    '';
  };

  skipHook = pkgs.writeShellScript "skip-m1n1-boot-bin" ''
    echo "hardware.m4mini.writeBootBin is off, leaving m1n1/boot.bin alone"
  '';
in
{
  options.hardware.m4mini = {
    espMountPoint = lib.mkOption {
      type = lib.types.str;
      default = "/boot";
      description = "The mount point of the EFI system partition.";
    };

    deviceTree = lib.mkOption {
      type = lib.types.str;
      default = "apple/t8132-j773g.dtb";
      description = "The kernel device tree, relative to the kernel's dtbs directory, that goes into boot.bin.";
    };

    writeBootBin = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether installing the bootloader writes m1n1/boot.bin. Off, NixOS
        leaves the EFI system partition alone, as when another system's
        bootloader starts NixOS's kernel.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    boot.loader.external = {
      enable = true;
      installHook = if cfg.writeBootBin then lib.getExe installHook else skipHook;
    };

    system.build.m1n1BootBin = pkgs.runCommand "m1n1-boot.bin" { } ''
      ${mkBootBin} ${m1n1Bin} ${lib.escapeShellArg cfg.deviceTree} ${config.system.build.toplevel} $out
    '';
  };
}
