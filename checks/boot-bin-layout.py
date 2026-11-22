"""Checks the payloads of an m1n1 boot.bin, with the magic numbers of m1n1's
src/payload.c."""

import argparse
import gzip
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


def cpio_names(data):
    """The file names of the concatenated newc cpio archives in data."""
    names = []
    offset = 0
    while offset < len(data):
        if data[offset : offset + 6] != CPIO_MAGIC:
            # Zero padding between and after archives.
            offset += 1
            continue
        header = data[offset : offset + 110]
        file_size = int(header[54:62], 16)
        name_size = int(header[94:102], 16)
        name = data[offset + 110 : offset + 110 + name_size - 1].decode()
        offset += (110 + name_size + 3) & ~3
        offset += (file_size + 3) & ~3
        if name != "TRAILER!!!":
            names.append(name)
    return names


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("m1n1")
    parser.add_argument("boot_bin")
    parser.add_argument("system")
    parser.add_argument("--initrd-contains", action="append", default=[], metavar="PATH")
    parser.add_argument("--initrd-out", metavar="FILE")
    args = parser.parse_args()
    m1n1_path, boot_bin_path, system = args.m1n1, args.boot_bin, args.system

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

    initrd = found[2][1]
    names = set(cpio_names(initrd))
    for path in args.initrd_contains:
        if path not in names:
            secrets = sorted(name for name in names if "initrd-secrets" in name)
            fail(f"the initrd has no {path}; its secrets are {secrets}")

    if args.initrd_out is not None:
        with open(args.initrd_out, "wb") as f:
            f.write(gzip.compress(initrd))

    print(f"boot-bin-layout: {kinds}, {bootargs}")


main()
