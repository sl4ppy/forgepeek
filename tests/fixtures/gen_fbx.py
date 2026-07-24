#!/usr/bin/env python3
"""Generate a minimal ASCII FBX 7.4 cube fixture (readable by three.js
FBXLoader's text parser). Hand-rolled: no FBX SDK dependency."""

CUBE_VERTS = [
    -1, -1, -1, 1, -1, -1, 1, 1, -1, -1, 1, -1,
    -1, -1, 1, 1, -1, 1, 1, 1, 1, -1, 1, 1,
]
CUBE_TRIS = [
    (0, 3, 2), (0, 2, 1),
    (4, 5, 6), (4, 6, 7),
    (0, 1, 5), (0, 5, 4),
    (2, 3, 7), (2, 7, 6),
    (1, 2, 6), (1, 6, 5),
    (3, 0, 4), (3, 4, 7),
]

# FBX polygon encoding: last index of each polygon is XOR'd with -1.
indices = []
for a, b, c in CUBE_TRIS:
    indices += [a, b, c ^ -1]

verts_s = ",".join(str(v) for v in CUBE_VERTS)
idx_s = ",".join(str(i) for i in indices)

FBX = f"""; FBX 7.4.0 project file
; forgepeek test fixture: 2x2x2 cube, no materials, no textures

FBXHeaderExtension:  {{
\tFBXHeaderVersion: 1003
\tFBXVersion: 7400
\tCreator: "forgepeek fixture generator"
}}
GlobalSettings:  {{
\tVersion: 1000
\tProperties70:  {{
\t\tP: "UpAxis", "int", "Integer", "",1
\t\tP: "UpAxisSign", "int", "Integer", "",1
\t\tP: "FrontAxis", "int", "Integer", "",2
\t\tP: "FrontAxisSign", "int", "Integer", "",1
\t\tP: "CoordAxis", "int", "Integer", "",0
\t\tP: "CoordAxisSign", "int", "Integer", "",1
\t\tP: "UnitScaleFactor", "double", "Number", "",1
\t}}
}}
Definitions:  {{
\tVersion: 100
\tCount: 2
\tObjectType: "Geometry" {{
\t\tCount: 1
\t}}
\tObjectType: "Model" {{
\t\tCount: 1
\t}}
}}
Objects:  {{
\tGeometry: 1000000, "Geometry::cube", "Mesh" {{
\t\tVertices: *{len(CUBE_VERTS)} {{
\t\t\ta: {verts_s}
\t\t}}
\t\tPolygonVertexIndex: *{len(indices)} {{
\t\t\ta: {idx_s}
\t\t}}
\t\tGeometryVersion: 124
\t}}
\tModel: 2000000, "Model::cube", "Mesh" {{
\t\tVersion: 232
\t\tProperties70:  {{
\t\t\tP: "Lcl Translation", "Lcl Translation", "", "A",0,0,0
\t\t\tP: "Lcl Rotation", "Lcl Rotation", "", "A",0,0,0
\t\t\tP: "Lcl Scaling", "Lcl Scaling", "", "A",1,1,1
\t\t}}
\t\tShading: T
\t\tCulling: "CullingOff"
\t}}
}}
Connections:  {{
\t;Model::cube, Model::RootNode
\tC: "OO",2000000,0
\t;Geometry::cube, Model::cube
\tC: "OO",1000000,2000000
}}
"""

with open("cube-ascii.fbx", "w") as f:
    f.write(FBX)
with open("corrupt.fbx", "wb") as f:
    f.write(b"Kaydara FBX Binary  \x00\x1a\x00" + b"\x00" * 40 + b"truncated garbage")
print("wrote cube-ascii.fbx corrupt.fbx")
