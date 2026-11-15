"""Write a small PNG (a 64x64 colour gradient) to the path given as argument.

Used by lab.sh as the picture to upload. Only the standard library is needed.
"""
import struct
import sys
import zlib

SIZE = 64


def chunk(kind: bytes, data: bytes) -> bytes:
    crc = zlib.crc32(kind + data) & 0xFFFFFFFF
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", crc)


rows = b"".join(
    b"\x00" + b"".join(bytes((x * 4, y * 4, 160)) for x in range(SIZE))
    for y in range(SIZE)
)
header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)  # 8-bit RGB
png = (
    b"\x89PNG\r\n\x1a\n"
    + chunk(b"IHDR", header)
    + chunk(b"IDAT", zlib.compress(rows))
    + chunk(b"IEND", b"")
)

with open(sys.argv[1], "wb") as out:
    out.write(png)
