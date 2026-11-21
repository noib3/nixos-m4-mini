# Loads the Wi-Fi and Bluetooth firmware Gravity's installer copies from macOS
# into vendorfw/firmware.cpio on the EFI system partition. Adapted from
# nixos-apple-silicon, after Asahi's dracut module.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hardware.m4mini;
in
{
  options.hardware.m4mini.loadVendorFirmware = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Whether the initrd unpacks vendorfw/firmware.cpio from the EFI system
      partition named by the device tree's `/chosen/gravity,efi-system-partition`
      property, and installs it to /lib/firmware/vendor.
    '';
  };

  config = lib.mkIf (cfg.enable && cfg.loadVendorFirmware) {
    boot.initrd.systemd = {
      extraBin.cpio = lib.getExe pkgs.cpio;

      mounts = [
        {
          what = "vendorfw";
          where = "/sysroot/lib/firmware/vendor";
          type = "tmpfs";
          options = "mode=0755";
          wantedBy = [ "initrd-fs.target" ];
        }
      ];

      services.m4mini-vendor-firmware = {
        description = "Unpack the vendor firmware from the EFI system partition";

        before = [
          "systemd-udevd.service"
          "systemd-udev-trigger.service"
          "sysinit.target"
          "shutdown.target"
        ];
        conflicts = [ "shutdown.target" ];
        wantedBy = [ "sysinit.target" ];

        unitConfig.DefaultDependencies = false;

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = ''
          # /lib is a store path in the initrd, so the link can't exist at build time.
          mkdir -p /lib/firmware
          ln -s /vendorfw /lib/firmware/vendor

          property=/proc/device-tree/chosen/gravity,efi-system-partition
          if [ ! -e "$property" ]; then
            echo "m4mini: no $property, not loading the vendor firmware"
            exit 0
          fi

          # nvme-apple is built into Gravity's kernel, so only the disk can be missing.
          for _ in $(seq 0 50); do
            [ -e /sys/bus/platform/drivers/nvme-apple/*.nvme/nvme/nvme*/nvme*n1/ ] && break
            sleep 0.1
          done

          if [ ! -e /sys/bus/platform/drivers/nvme-apple/*.nvme/nvme/nvme*/nvme*n1/ ]; then
            echo "m4mini: timed out waiting for the NVMe disk" >&2
            exit 1
          fi

          esp_uuid="$(tr -d '\0' < "$property")"
          mkdir -p /run/.system-efi
          mount "PARTUUID=$esp_uuid" /run/.system-efi

          if [ ! -e /run/.system-efi/vendorfw/firmware.cpio ]; then
            echo "m4mini: the EFI system partition has no vendorfw/firmware.cpio" >&2
            umount /run/.system-efi
            exit 1
          fi

          ( cd / && cpio --quiet -i < /run/.system-efi/vendorfw/firmware.cpio )
          umount /run/.system-efi
          echo "m4mini: unpacked the vendor firmware"
        '';
      };

      services.m4mini-vendor-firmware-install = {
        description = "Install the vendor firmware to the root filesystem";

        wantedBy = [ "initrd.target" ];
        before = [ "initrd.target" ];

        unitConfig = {
          ConditionPathExists = "/vendorfw";
          RequiresMountsFor = "/sysroot/lib/firmware/vendor";
        };

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "/bin/cp -a /vendorfw/. /sysroot/lib/firmware/vendor";
        };
      };
    };
  };
}
