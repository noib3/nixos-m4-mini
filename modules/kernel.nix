{
  config,
  lib,
  pkgs,
  ...
}:

{
  config = lib.mkIf config.hardware.m4mini.enable {
    boot.kernelPackages = pkgs.linuxPackages-gravity;

    # Gravity's kernel command line, without its boot splash and HDMI audio.
    # The M4 cores lose state in WFI and WFIT, and the kernel hangs as soon as
    # a second core starts without these options.
    boot.kernelParams = [
      "nohlt"
      "idle=nop"
      "arm64.nowfxt"
      "console=tty0"
    ];

    # Gravity's configuration builds the Apple platform, storage, display and
    # USB drivers into the kernel, and drops the SoC families NixOS's default
    # initrd modules are for.
    boot.initrd.includeDefaultModules = false;
    boot.initrd.availableKernelModules = [
      "vfat"
      "nls_cp437"
      "nls_iso8859-1"
      "usb-storage"
    ];

    # m1n1 only decompresses gzip and xz payloads.
    boot.initrd.compressor = "gzip";

    # Suspend doesn't work on the M4 mini yet.
    systemd.targets = lib.genAttrs [ "sleep" "suspend" "hibernate" "hybrid-sleep" ] (_: {
      enable = false;
    });
    services.logind.settings.Login = {
      HandleSuspendKey = "ignore";
      HandleHibernateKey = "ignore";
      IdleAction = "ignore";
    };

    powerManagement.cpuFreqGovernor = lib.mkDefault "schedutil";
  };
}
