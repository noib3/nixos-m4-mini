# Writes the stage-2 boot object m1n1 loads from m1n1/boot.bin on the EFI
# system partition. The file is m1n1 followed by its payloads: the device tree,
# the gzipped kernel, the gzipped initrd, and a `chosen.bootargs=` line m1n1
# copies into the device tree's /chosen node as the kernel command line.
{
  writeShellApplication,
  coreutils,
  gzip,
}:

writeShellApplication {
  name = "mk-m1n1-boot-bin";
  runtimeInputs = [
    coreutils
    gzip
  ];
  text = ''
    if [ "$#" -ne 4 ]; then
      echo "usage: mk-m1n1-boot-bin M1N1_BIN DEVICE_TREE SYSTEM OUT" >&2
      exit 2
    fi

    m1n1=$1
    dtb=$2
    system=$3
    out=$4

    if [ ! -f "$system/dtbs/$dtb" ]; then
      echo "mk-m1n1-boot-bin: $system has no device tree $dtb" >&2
      exit 1
    fi

    # m1n1 recognizes gzip and xz payloads only.
    if [ "$(head -c 2 "$system/initrd" | od -An -tx1 | tr -d ' ')" != "1f8b" ]; then
      echo "mk-m1n1-boot-bin: $system/initrd is not gzip-compressed" >&2
      exit 1
    fi

    bootargs="init=$system/init $(cat "$system/kernel-params")"

    # m1n1 ignores a variable whose value is longer than 1024 bytes.
    if [ "''${#bootargs}" -gt 1024 ]; then
      echo "mk-m1n1-boot-bin: the kernel command line is longer than m1n1's 1024-byte limit" >&2
      exit 1
    fi

    {
      cat "$m1n1"
      cat "$system/dtbs/$dtb"
      gzip -n -c "$system/kernel"
      cat "$system/initrd"
      printf 'chosen.bootargs=%s\n' "$bootargs"
    } > "$out"
  '';
}
