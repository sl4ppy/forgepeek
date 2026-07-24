#!/usr/bin/env python3
"""Generate STL fixtures: a binary cube and an ASCII tetrahedron."""
import struct

CUBE_VERTS = [
    (-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),
    (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1),
]
# 12 triangles, outward winding
CUBE_TRIS = [
    (0, 3, 2), (0, 2, 1),  # bottom (z=-1)
    (4, 5, 6), (4, 6, 7),  # top (z=+1)
    (0, 1, 5), (0, 5, 4),  # y=-1
    (2, 3, 7), (2, 7, 6),  # y=+1
    (1, 2, 6), (1, 6, 5),  # x=+1
    (3, 0, 4), (3, 4, 7),  # x=-1
]

TETRA_VERTS = [(0, 0, 0), (2, 0, 0), (1, 2, 0), (1, 1, 2)]
TETRA_TRIS = [(0, 2, 1), (0, 1, 3), (1, 2, 3), (2, 0, 3)]


def normal(a, b, c):
    u = [b[i] - a[i] for i in range(3)]
    v = [c[i] - a[i] for i in range(3)]
    n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]]
    ln = max((n[0] ** 2 + n[1] ** 2 + n[2] ** 2) ** 0.5, 1e-9)
    return [x / ln for x in n]


def write_binary(path, verts, tris):
    with open(path, "wb") as f:
        f.write(b"forgepeek binary stl fixture".ljust(80, b"\0"))
        f.write(struct.pack("<I", len(tris)))
        for t in tris:
            a, b, c = (verts[i] for i in t)
            f.write(struct.pack("<3f", *normal(a, b, c)))
            for p in (a, b, c):
                f.write(struct.pack("<3f", *p))
            f.write(struct.pack("<H", 0))


def write_ascii(path, verts, tris):
    with open(path, "w") as f:
        f.write("solid forgepeek_ascii_fixture\n")
        for t in tris:
            a, b, c = (verts[i] for i in t)
            n = normal(a, b, c)
            f.write(f"  facet normal {n[0]:e} {n[1]:e} {n[2]:e}\n")
            f.write("    outer loop\n")
            for p in (a, b, c):
                f.write(f"      vertex {p[0]:e} {p[1]:e} {p[2]:e}\n")
            f.write("    endloop\n")
            f.write("  endfacet\n")
        f.write("endsolid forgepeek_ascii_fixture\n")


write_binary("cube-binary.stl", CUBE_VERTS, CUBE_TRIS)
write_ascii("tetra-ascii.stl", TETRA_VERTS, TETRA_TRIS)
with open("corrupt.stl", "wb") as f:
    f.write(b"solid nope\n\xff\xfe\xfd garbage that is neither ascii nor binary stl")
print("wrote cube-binary.stl tetra-ascii.stl corrupt.stl")
