#!/usr/bin/env python3
"""Writes src/shared/MeshLayout.luau from the character models in assets/characters.

For every mesh in every .glb file it records the centre and size of the mesh's box, in studs,
with the character standing at the origin facing -Z. The game uses this to put each imported
MeshPart exactly where it belongs, wherever Studio happened to drop the imported model.

Run it again whenever assets/characters changes:

    python3 tools/make_mesh_layout.py
"""
import glob
import json
import os
import struct

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "src", "shared", "MeshLayout.luau")


def read_gltf(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, _version, _length = struct.unpack("<III", data[:12])
    assert magic == 0x46546C67, f"{path} is not a .glb file"
    chunk_len, _chunk_type = struct.unpack("<II", data[12:20])
    return json.loads(data[20 : 20 + chunk_len])


def mesh_box(gltf, mesh_index):
    lo = [float("inf")] * 3
    hi = [float("-inf")] * 3
    for prim in gltf["meshes"][mesh_index]["primitives"]:
        acc = gltf["accessors"][prim["attributes"]["POSITION"]]
        for i in range(3):
            lo[i] = min(lo[i], acc["min"][i])
            hi[i] = max(hi[i], acc["max"][i])
    centre = [(lo[i] + hi[i]) / 2 for i in range(3)]
    size = [hi[i] - lo[i] for i in range(3)]
    return centre, size


def main():
    files = {}
    for path in sorted(glob.glob(os.path.join(ROOT, "assets", "characters", "*.glb"))):
        key = os.path.splitext(os.path.basename(path))[0]
        gltf = read_gltf(path)
        root = gltf["nodes"][gltf["scenes"][gltf.get("scene", 0)]["nodes"][0]]
        meshes = {}
        for node in gltf["nodes"]:
            if "mesh" not in node:
                continue
            # The exporter bakes every position into the vertices, so nodes have no transforms.
            assert not any(k in node for k in ("translation", "rotation", "scale", "matrix")), node["name"]
            meshes[node["name"]] = mesh_box(gltf, node["mesh"])
        files[key] = (root["name"], meshes)

    def num(v):
        s = f"{v:.4f}".rstrip("0").rstrip(".")
        return "0" if s in ("", "-0") else s

    lines = [
        "-- Made by tools/make_mesh_layout.py from assets/characters/*.glb. Don't edit by hand:",
        "-- run `python3 tools/make_mesh_layout.py` again instead.",
        "--",
        "-- For each model file: the name of its top group, and for every mesh the centre and size of",
        "-- its box in studs { x, y, z, width, height, depth }, standing at the origin facing -Z.",
        "",
        "return {",
    ]
    for key, (root_name, meshes) in files.items():
        lines.append(f'\t["{key}"] = {{')
        lines.append(f'\t\troot = "{root_name}",')
        lines.append("\t\tmeshes = {")
        for name, (c, s) in meshes.items():
            vals = ", ".join(num(v) for v in (*c, *s))
            lines.append(f'\t\t\t["{name}"] = {{ {vals} }},')
        lines.append("\t\t},")
        lines.append("\t},")
    lines.append("}")
    with open(OUT, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"Wrote {os.path.relpath(OUT, ROOT)} ({len(files)} files)")


if __name__ == "__main__":
    main()
