# Makes boot.initrd.network.ssh work on the mini: the initrd gets the drivers
# of the mini's Ethernet controllers, and host keys missing when boot.bin is
# written are generated, so the boot.bin hook can append them as initrd
# secrets. The SSH server and the initrd's network stay the system's
# configuration.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  ssh = config.boot.initrd.network.ssh;
in
{
  config = lib.mkIf (config.hardware.m4mini.enable && ssh.enable) {
    assertions = [
      {
        assertion = config.boot.loader.supportsInitrdSecrets;
        message = "boot.initrd.network.ssh on the M4 mini needs hardware.m4mini.writeBootBin, which appends its host keys to the initrd.";
      }
    ];

    # The mini's 1 Gb/s and 10 Gb/s Ethernet controllers.
    boot.initrd.availableKernelModules = [
      "atlantic"
      "tg3"
    ];

    hardware.m4mini.initrdSecretsSetup = lib.concatMapStrings (key: ''
      if [ ! -e ${lib.escapeShellArg key} ]; then
        install -d -m 0755 "$(dirname ${lib.escapeShellArg key})"
        ${lib.getExe' pkgs.openssh "ssh-keygen"} -q -t ed25519 -N "" -f ${lib.escapeShellArg key}
      fi
    '') (map toString ssh.hostKeys);
  };
}
