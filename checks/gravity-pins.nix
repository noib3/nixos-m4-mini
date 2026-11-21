# Fails when the kernel or bootloader input is not the commit gravity-packages'
# sources.json pins.
{
  lib,
  runCommand,
  inputs,
}:

let
  sources = lib.importJSON "${inputs.gravity-packages}/sources.json";

  pins = [
    {
      input = "gravity-linux";
      inherit (inputs.gravity-linux) rev;
      expected = sources.kernel.ref;
    }
    {
      input = "gravity-bootloader";
      inherit (inputs.gravity-bootloader) rev;
      expected = sources.gravity-bootloader.ref;
    }
  ];

  mismatches = lib.filter (pin: pin.rev != pin.expected) pins;

  report = lib.concatMapStringsSep "\n" (
    pin: "${pin.input} is at ${pin.rev}, gravity-packages pins ${pin.expected}"
  ) mismatches;
in
runCommand "gravity-pins" { } (
  if mismatches == [ ] then
    "touch $out"
  else
    ''
      cat >&2 <<'EOF'
      ${report}
      EOF
      exit 1
    ''
)
