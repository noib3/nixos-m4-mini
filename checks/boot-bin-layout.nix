# Walks boot.bin the way m1n1's payload loader does, and fails unless it finds
# the device tree, the kernel, the initrd and the kernel command line, in that
# order, after m1n1.
{
  runCommand,
  python3,
  system,
  bootBin,
  m1n1,
}:

runCommand "boot-bin-layout"
  {
    nativeBuildInputs = [ python3 ];
  }
  ''
    python3 -I ${./boot-bin-layout.py} \
      ${m1n1}/lib/m1n1/m1n1.bin ${bootBin} ${system}
    touch $out
  ''
