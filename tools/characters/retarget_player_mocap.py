#!/usr/bin/env python3
"""Build in-place Godot clips from the two recorded CMU BVH trials."""
import argparse
import re
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "addons/godot_level_editor/assets/characters"
MOTION = ASSETS / "player_motion"
RIG = ASSETS / "quaternius_base/adapted_human.tscn"

# Map measured anatomical directions to matching segments on the Godot rig.
SEGMENTS = {
    "pelvis": ("Hips", "Spine", "spine_01"),
    "spine_01": ("Spine", "Spine1", "spine_02"),
    "spine_03": ("Spine1", "Neck1", "neck_01"),
    "neck_01": ("Neck1", "Head", "Head"),
}
for suffix, side in (("l", "Left"), ("r", "Right")):
    for bone, start, end, child in (
        ("clavicle", "Shoulder", "Arm", "upperarm"),
        ("upperarm", "Arm", "ForeArm", "lowerarm"),
        ("lowerarm", "ForeArm", "Hand", "hand"),
        ("hand", "Hand", "HandIndex1", "index_01"),
        ("thigh", "UpLeg", "Leg", "calf"),
        ("calf", "Leg", "Foot", "foot"),
        ("foot", "Foot", "ToeBase", "ball"),
    ):
        SEGMENTS[f"{bone}_{suffix}"] = (side + start, side + end, f"{child}_{suffix}")


def unit(vector):
    return vector / max(float(np.linalg.norm(vector)), 1e-9)


def rotation(axis, angle):
    x, y, z = unit(axis)
    cosine, sine = np.cos(angle), np.sin(angle)
    cross = np.array([[0, -z, y], [z, 0, -x], [-y, x, 0]])
    return cosine * np.eye(3) + sine * cross + (1 - cosine) * np.outer((x, y, z), (x, y, z))


def align_direction(start, end):
    start, end = unit(start), unit(end)
    axis = np.cross(start, end)
    length = np.linalg.norm(axis)
    cosine = float(start @ end)
    if length < 1e-8:
        if cosine > 0:
            return np.eye(3)
        fallback = np.eye(3)[np.argmin(np.abs(start))]
        return rotation(np.cross(start, fallback), np.pi)
    return rotation(axis, np.arctan2(length, cosine))


def quaternion(basis):
    # Get a unit quaternion via the symmetric eigenproblem. Values are x, y, z, w.
    xx, xy, xz, yx, yy, yz, zx, zy, zz = basis.flat
    system = np.array([
        [xx-yy-zz, xy+yx, xz+zx, zy-yz],
        [xy+yx, yy-xx-zz, yz+zy, xz-zx],
        [xz+zx, yz+zy, zz-xx-yy, yx-xy],
        [zy-yz, xz-zx, yx-xy, xx+yy+zz],
    ])
    _, vectors = np.linalg.eigh(system)
    return vectors[:, -1]


def parse_bvh(path):
    hierarchy, motion = path.read_text().split("MOTION", 1)
    tokens = iter(re.findall(r"[^\s{}]+|[{}]", hierarchy))
    assert next(tokens) == "HIERARCHY" and next(tokens) == "ROOT"
    nodes = []
    columns = 0

    def read_joint(name, parent):
        nonlocal columns
        assert next(tokens) == "{"
        assert next(tokens) == "OFFSET"
        offset = np.array([float(next(tokens)) for _ in range(3)])
        assert next(tokens) == "CHANNELS"
        channels = [next(tokens) for _ in range(int(next(tokens)))]
        index = len(nodes)
        nodes.append((name, parent, offset, channels, columns))
        columns += len(channels)
        for token in tokens:
            if token == "}":
                break
            if token == "JOINT":
                read_joint(next(tokens), index)
            elif token == "End":
                assert next(tokens) == "Site" and next(tokens) == "{" and next(tokens) == "OFFSET"
                for _ in range(3):
                    next(tokens)
                assert next(tokens) == "}"

    read_joint(next(tokens), -1)
    header, values = motion.split("Frame Time:", 1)
    frame_time, samples = values.strip().split("\n", 1)
    frames = np.fromstring(samples, sep=" ").reshape((-1, columns))
    assert len(frames) == int(header.split("Frames:")[1])
    basis_vectors = dict(zip("XYZ", np.eye(3)))
    all_positions = []
    for frame in frames:
        positions = {}
        bases = []
        for name, parent, offset, channels, first in nodes:
            local_position = offset.copy()
            relative = np.eye(3)
            for suffix, value in zip(channels, frame[first:]):
                axis = basis_vectors[suffix[0]]
                if suffix.endswith("rotation"):
                    relative = relative @ rotation(axis, np.deg2rad(value))
                else:
                    local_position += axis * value
            if parent < 0:
                positions[name] = local_position
                bases.append(relative)
            else:
                positions[name] = positions[nodes[parent][0]] + bases[parent] @ local_position
                bases.append(bases[parent] @ relative)
        all_positions.append(positions)
    return float(frame_time), all_positions


def read_rig():
    nodes = {}
    world = {}
    for _, name, parent, matrix in re.findall(r'bones/(\d+)/name = "([^"]+)"\nbones/\d+/parent = (-?\d+)\nbones/\d+/rest = Transform3D\(([^)]+)\)', RIG.read_text()):
        values = np.fromstring(matrix, sep=",")
        parent = list(nodes)[int(parent)] if int(parent) >= 0 else ""
        basis = values[:9].reshape(3, 3).T
        offset = values[9:]
        nodes[name] = parent, basis, offset
        basis_parent, position = world.get(parent, (np.eye(3), np.zeros(3)))
        world[name] = basis_parent @ basis, position + basis_parent @ offset
    return nodes, world


def clip_write(filename, title, time, poses, closing_loop):
    rig, rest = read_rig()
    source_left = np.mean([pose["LeftUpLeg"] - pose["RightUpLeg"] for pose in poses], axis=0)
    rig_left = rest["thigh_l"][1] - rest["thigh_r"][1]
    source_left[1] = rig_left[1] = 0
    forward = align_direction(source_left, rig_left)
    tracks = {name: [] for name in SEGMENTS}
    for pose in poses:
        world = {}
        for name, (parent, rest_basis, _) in rig.items():
            parent_basis = world.get(parent, np.eye(3))
            placed = parent_basis @ rest_basis
            if name in SEGMENTS:
                a, b, child = SEGMENTS[name]
                start = placed @ rig[child][2]
                target = forward @ (pose[b] - pose[a])
                placed = align_direction(start, target) @ placed
                value = quaternion(parent_basis.T @ placed)
                if tracks[name] and value @ tracks[name][-1] < 0:
                    value = -value
                tracks[name].append(value)
            world[name] = placed

    lines = ['[gd_resource type="Animation" format=3]', '', '[resource]', f'resource_name = "{title}"', f'length = {time:.7f}']
    if closing_loop:
        lines.append('loop_mode = 1')
    key_count = len(poses) + int(closing_loop)
    for index, (name, sequence) in enumerate(tracks.items()):
        if closing_loop:
            sequence.append(sequence[0] if sequence[0] @ sequence[-1] >= 0 else -sequence[0])
        values = []
        for key, value in enumerate(sequence):
            values.extend((key * time / (key_count - 1), 1.0, *value))
        prefix = f"tracks/{index}"
        lines.extend([
            f'{prefix}/type = "rotation_3d"',
            f'{prefix}/imported = true',
            f'{prefix}/enabled = true',
            f'{prefix}/path = NodePath("Body/Armature/Skeleton3D:{name}")',
            f'{prefix}/interp = 1',
            f'{prefix}/loop_wrap = true',
            f'{prefix}/keys = PackedFloat32Array(' + ", ".join(f"{x:.7g}" for x in values) + ")",
        ])
    (MOTION / filename).write_text("\n".join(lines) + "\n")
    print(f"{filename}: {len(tracks)} joints, {key_count} keys per joint, {time:.3f} s")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("climb", type=Path)
    parser.add_argument("step_over", type=Path)
    args = parser.parse_args()
    tick, poses = parse_bvh(args.climb)
    # Use the ascending portion with hands on the ladder. Drop absolute translation;
    # close the cycle across the last four original frames.
    ascending = poses[112:216:4]
    clip_write("ladder_climb.tres", "CMU Ladder Climb", 4 * len(ascending) * tick, ascending, True)
    tick, poses = parse_bvh(args.step_over)
    def foot_lift(pose):
        return max(pose["LeftFoot"][1], pose["RightFoot"][1])
    peak = max(range(30, len(poses) - 30), key=lambda index: foot_lift(poses[index]))
    start, end = max(12, peak - 31), min(len(poses) - 1, peak + 44)
    section = poses[start:end:4]
    clip_write("step_over.tres", "CMU Step Over", 4 * (len(section) - 1) * tick, section, False)


if __name__ == "__main__":
    main()
