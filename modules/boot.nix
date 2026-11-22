# Boots the system straight from m1n1, without U-Boot or an EFI bootloader.
# Each generation's kernel, initrd and command line go into m1n1/boot.bin on
# the EFI system partition, and the boot.bin it replaces is kept as
# m1n1/boot.bin.prev. The initrd in boot.bin carries boot.initrd.secrets,
# appended when boot.bin is written.
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
      gnugrep
      gzip
      util-linux
    ];
    text = ''
      system=$1
      esp=${lib.escapeShellArg cfg.espMountPoint}

      if ! mountpoint -q "$esp"; then
        echo "install-m1n1-boot-bin: $esp is not mounted" >&2
        exit 1
      fi

      tmp=$(mktemp -d)
      trap 'rm -rf "$tmp"' EXIT

      # The secrets' sources must exist before they are appended.
      ${cfg.initrdSecretsSetup}

      # append-initrd-secrets adds a second gzip member, and m1n1 may only read
      # the first, so the result is recompressed as one stream.
      cp "$system/initrd" "$tmp/initrd"
      chmod u+w "$tmp/initrd"
      ${config.system.build.initialRamdiskSecretAppender}/bin/append-initrd-secrets "$tmp/initrd"
      gzip -d -c "$tmp/initrd" | gzip -n -c > "$tmp/initrd.gz"

      mkdir -p "$esp/m1n1"
      ${mkBootBin} ${m1n1Bin} ${lib.escapeShellArg cfg.deviceTree} "$system" "$esp/m1n1/boot.bin.new" "$tmp/initrd.gz"

      if [ -e "$esp/m1n1/boot.bin" ] && cmp -s "$esp/m1n1/boot.bin" "$esp/m1n1/boot.bin.new"; then
        rm "$esp/m1n1/boot.bin.new"
        exit 0
      fi

      # TODO(fedora): remove once Gravity's Fedora is deleted. The first
      # boot.bin NixOS replaces is Gravity's, kept as boot.bin.fedora for good,
      # while boot.bin.prev only holds the previous generation.
      if [ -e "$esp/m1n1/boot.bin" ] && [ ! -e "$esp/m1n1/boot.bin.fedora" ] \
        && ! grep -a -q 'chosen.bootargs=init=/nix/store/' "$esp/m1n1/boot.bin"; then
        cp "$esp/m1n1/boot.bin" "$esp/m1n1/boot.bin.fedora"
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

    initrdSecretsSetup = lib.mkOption {
      type = lib.types.lines;
      default = "";
      internal = true;
      description = ''
        The shell commands, run as root before boot.bin is written, that
        create missing sources of boot.initrd.secrets.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    boot.loader.external = {
      enable = true;
      installHook = if cfg.writeBootBin then lib.getExe installHook else skipHook;
    };

    boot.loader.supportsInitrdSecrets = cfg.writeBootBin;

    system.build.m1n1BootBin = pkgs.runCommand "m1n1-boot.bin" { } ''
      ${mkBootBin} ${m1n1Bin} ${lib.escapeShellArg cfg.deviceTree} ${config.system.build.toplevel} $out
    '';
  };
}
