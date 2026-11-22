# Bluetooth in the initrd, so a paired Bluetooth keyboard can type the LUKS
# passphrase. Modeled on dracut's bluetooth module: the initrd carries the
# Bluetooth driver, bluetoothd and its D-Bus policy, and the pairing keys from
# /var/lib/bluetooth, which the boot.bin hook appends as initrd secrets. A
# keyboard paired later works at the next boot after `nixos-rebuild boot`.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hardware.m4mini;

  bluez = config.hardware.bluetooth.package;
in
{
  options.hardware.m4mini.initrdBluetooth.enable = lib.mkEnableOption ''
    bluetoothd in the initrd, with this system's pairings, so a Bluetooth
    keyboard can type the LUKS passphrase. It needs hardware.bluetooth and a
    bootloader that appends initrd secrets, since the pairing keys must not
    enter the Nix store
  '';

  config = lib.mkIf (cfg.enable && cfg.initrdBluetooth.enable) {
    assertions = [
      {
        assertion = config.hardware.bluetooth.enable;
        message = "hardware.m4mini.initrdBluetooth.enable needs hardware.bluetooth.enable.";
      }
      {
        assertion = config.boot.loader.supportsInitrdSecrets;
        message = "hardware.m4mini.initrdBluetooth.enable needs a bootloader that appends initrd secrets, or the pairing keys would enter the Nix store.";
      }
    ];

    boot.initrd.availableKernelModules = [
      "bluetooth"
      "hci_bcm4377"
      "hid_logitech_dj"
      "hid_logitech_hidpp"
    ];

    # bluez creates input devices through uhid, and hidp handles devices
    # without its userspace HID support. Neither module has a device that
    # makes udev load it.
    boot.initrd.kernelModules = [
      "hidp"
      "uhid"
    ];

    boot.initrd.secrets."/var/lib/bluetooth" = "/var/lib/bluetooth";

    hardware.m4mini.initrdSecretsSetup = ''
      install -d -m 0700 /var/lib/bluetooth
    '';

    boot.initrd.systemd = {
      storePaths = [
        "${bluez}/libexec/bluetooth/bluetoothd"
        "${bluez}/share/dbus-1/system.d"
      ];

      # The initrd's D-Bus configuration, with bluez's policy for org.bluez.
      contents."/etc/dbus-1".source = lib.mkForce (
        pkgs.makeDBusConf.override {
          inherit (config.services.dbus) apparmor;
          dbus = config.services.dbus.dbusPackage;
          suidHelper = "/bin/false";
          serviceDirectories = [
            config.services.dbus.dbusPackage
            config.boot.initrd.systemd.package
            bluez
          ];
        }
      );

      # A paired keyboard connects to the host, so the adapter must be on and
      # connectable before the passphrase prompt.
      contents."/etc/bluetooth/main.conf".text = ''
        [General]
        FastConnectable=true

        [Policy]
        AutoEnable=true
      '';

      services.bluetooth = {
        description = "Bluetooth in the initrd";
        wantedBy = [ "cryptsetup.target" ];
        before = [ "cryptsetup-pre.target" ];
        after = [
          "dbus.socket"
          "initrd-nixos-copy-secrets.service"
          "m4mini-vendor-firmware.service"
        ];
        requires = [ "dbus.socket" ];
        unitConfig.DefaultDependencies = false;
        serviceConfig = {
          Type = "dbus";
          BusName = "org.bluez";
          ExecStart = "${bluez}/libexec/bluetooth/bluetoothd --nodetach";
        };
      };
    };
  };
}
