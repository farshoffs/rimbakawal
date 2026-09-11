#!/usr/bin/env python3
"""Generate the ZPatrol 1024px launcher/PWA icon using only Python stdlib."""

from __future__ import annotations

import binascii
import math
import struct
import sys
import zlib
from pathlib import Path

WIDTH = HEIGHT = 1024
OUTER = (57, 25, 105)
INNER = (16, 15, 24)
WHITE = (248, 247, 255)
LAVENDER = (184, 166, 255)


def _inside_rounded_rect(x: int, y: int, left: int, top: int, right: int, bottom: int, radius: int) -> bool:
    if left + radius <= x <= right - radius or top + radius <= y <= bottom - radius:
        return left <= x <= right and top <= y <= bottom
    cx = left + radius if x < left + radius else right - radius
    cy = top + radius if y < top + radius else bottom - radius
    return (x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2


def _distance_sq_to_segment(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
    dx = bx - ax
    dy = by - ay
    if dx == 0 and dy == 0:
        return (px - ax) ** 2 + (py - ay) ** 2
    t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)
    t = max(0.0, min(1.0, t))
    qx = ax + t * dx
    qy = ay + t * dy
    return (px - qx) ** 2 + (py - qy) ** 2


def _inside_polygon(x: float, y: float, points: list[tuple[int, int]]) -> bool:
    inside = False
    j = len(points) - 1
    for i, (xi, yi) in enumerate(points):
        xj, yj = points[j]
        intersects = ((yi > y) != (yj > y)) and (
            x < (xj - xi) * (y - yi) / ((yj - yi) or 1e-9) + xi
        )
        if intersects:
            inside = not inside
        j = i
    return inside


def _png_chunk(kind: bytes, payload: bytes) -> bytes:
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", binascii.crc32(kind + payload) & 0xFFFFFFFF)


def generate(path: Path) -> None:
    pixels = bytearray(OUTER) * (WIDTH * HEIGHT)

    def set_pixel(x: int, y: int, colour: tuple[int, int, int]) -> None:
        if 0 <= x < WIDTH and 0 <= y < HEIGHT:
            offset = (y * WIDTH + x) * 3
            pixels[offset : offset + 3] = bytes(colour)

    # Dark inset panel.
    left = top = 46
    right = bottom = 977
    radius = 244
    for y in range(top, bottom + 1):
        for x in range(left, right + 1):
            if _inside_rounded_rect(x, y, left, top, right, bottom, radius):
                set_pixel(x, y, INNER)

    # Shield outline.
    shield = [
        (512, 162),
        (775, 267),
        (775, 500),
        (742, 622),
        (681, 724),
        (602, 804),
        (512, 851),
        (422, 804),
        (343, 724),
        (282, 622),
        (249, 500),
        (249, 267),
        (512, 162),
    ]
    half_width_sq = 29 * 29
    for y in range(132, 882):
        for x in range(218, 806):
            if any(
                _distance_sq_to_segment(x, y, *shield[i], *shield[i + 1]) <= half_width_sq
                for i in range(len(shield) - 1)
            ):
                set_pixel(x, y, WHITE)

    # Angular Z / lightning mark.
    z_mark = [
        (354, 351),
        (673, 351),
        (613, 431),
        (513, 548),
        (666, 548),
        (423, 730),
        (470, 598),
        (348, 598),
        (431, 501),
        (523, 393),
        (354, 393),
    ]
    for y in range(338, 742):
        for x in range(334, 686):
            if _inside_polygon(x + 0.5, y + 0.5, z_mark):
                set_pixel(x, y, LAVENDER)

    raw = bytearray()
    stride = WIDTH * 3
    for y in range(HEIGHT):
        raw.append(0)
        start = y * stride
        raw.extend(pixels[start : start + stride])

    png = bytearray(b"\x89PNG\r\n\x1a\n")
    png.extend(_png_chunk(b"IHDR", struct.pack(">IIBBBBB", WIDTH, HEIGHT, 8, 2, 0, 0, 0)))
    png.extend(_png_chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
    png.extend(_png_chunk(b"IEND", b""))

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)
    print(f"Generated {path} ({len(png)} bytes)")


if __name__ == "__main__":
    output = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("assets/branding/zpatrol_icon.png")
    generate(output)
