"""Checks the payloads of an m1n1 boot.bin, with the magic numbers of m1n1's
src/payload.c."""

import struct
import sys
import zlib

FDT_MAGIC = b"\xd0\x0d\xfe\xed"
GZIP_MAGIC = b"\x1f\x8b"
CPIO_MAGIC = b"070701"
# The arm64 kernel image header carries "ARM\x64" at offset 0x38.
KERNEL_MAGIC = b"ARM\x64"
# m1n1 ignores a variable whose value is longer than this.
MAX_VAR_SIZE = 1024


def fail(message):
    print(f"boot-bin-layout: {message}", file=sys.stderr)
    sys.exit(1)


def gunzip(data):
    decompressor = zlib.decompressobj(16 + zlib.MAX_WBITS)
    contents = decompressor.decompress(data)
    if not decompressor.eof:
        fail("a gzip payload is truncated")
    return contents, len(data) - len(decompressor.unused_data)


def payloads(data):
    offset = 0
    while offset < len(data):
        rest = data[offset:]
        if rest.startswith(FDT_MAGIC):
            (size,) = struct.unpack(">I", rest[4:8])
            yield "device tree", rest[:size]
            offset += size
        elif rest.startswith(GZIP_MAGIC):
            contents, size = gunzip(rest)
            if contents[0x38:0x3C] == KERNEL_MAGIC:
                yield "kernel", contents
            elif contents.startswith(CPIO_MAGIC):
                yield "initrd", contents
            else:
                fail(f"unknown gzip payload at offset {offset}")
            offset += size
        else:
            line, newline, _ = rest.partition(b"\n")
            name, equals, value = line.partition(b"=")
            if not newline or not equals:
                fail(f"unknown payload at offset {offset}")
            if len(value) > MAX_VAR_SIZE:
                fail(f"variable {name.decode()} is longer than {MAX_VAR_SIZE} bytes")
            yield "variable", line.decode()
            offset += len(line) + 1


def main():
    m1n1_path, boot_bin_path, system = sys.argv[1:]

    with open(m1n1_path, "rb") as f:
        m1n1 = f.read()
    with open(boot_bin_path, "rb") as f:
        boot_bin = f.read()

    if not boot_bin.startswith(m1n1):
        fail("boot.bin doesn't start with m1n1")

    found = list(payloads(boot_bin[len(m1n1) :]))
    kinds = [kind for kind, _ in found]
    expected = ["device tree", "kernel", "initrd", "variable"]
    if kinds != expected:
        fail(f"found payloads {kinds}, expected {expected}")

    with open(f"{system}/kernel", "rb") as f:
        if found[1][1] != f.read():
            fail(f"the kernel isn't {system}/kernel")

    bootargs = found[3][1]
    if not bootargs.startswith(f"chosen.bootargs=init={system}/init "):
        fail(f"the command line doesn't start {system}'s init: {bootargs}")

    print(f"boot-bin-layout: {kinds}, {bootargs}")


main()
