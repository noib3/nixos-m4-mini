# Links /dev/disk/gravity-esp to the EFI system partition whose PARTUUID
# Gravity's installer writes to m1n1's configuration, and m1n1 passes to Linux
# as the device tree's `/chosen/gravity,efi-system-partition` property.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hardware.m4mini;

  # Exits successfully when its argument is the PARTUUID in espPartUuidFile.
  isEsp = pkgs.writeShellScript "m4mini-is-esp" ''
    file=${lib.escapeShellArg cfg.espPartUuidFile}
    [ -r "$file" ] || exit 1
    [ "$(${lib.getExe' pkgs.coreutils "tr"} -d '\0' < "$file" \
      | ${lib.getExe' pkgs.coreutils "tr"} '[:upper:]' '[:lower:]')" = "$1" ]
  '';
in
{
  options.hardware.m4mini = {
    espDevice = lib.mkOption {
      type = lib.types.str;
      default = "/dev/disk/gravity-esp";
      readOnly = true;
      description = "The udev link to the EFI system partition.";
    };

    espPartUuidFile = lib.mkOption {
      type = lib.types.str;
      default = "/proc/device-tree/chosen/gravity,efi-system-partition";
      description = "The file holding the PARTUUID of the EFI system partition.";
    };
  };

  config = lib.mkIf cfg.enable {
    # 60-persistent-storage.rules sets ID_PART_ENTRY_UUID, and extraRules go
    # into 99-local.rules, after it.
    services.udev.extraRules = ''
      SUBSYSTEM=="block", ENV{DEVTYPE}=="partition", ENV{ID_PART_ENTRY_UUID}=="?*", PROGRAM="${isEsp} $env{ID_PART_ENTRY_UUID}", SYMLINK+="${lib.removePrefix "/dev/" cfg.espDevice}"
    '';
  };
}
