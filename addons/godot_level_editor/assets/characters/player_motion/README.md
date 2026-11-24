# CMU player motion clips

The data used in this project was obtained from mocap.cs.cmu.edu.

The [CMU Graphics Lab Motion Capture Database](https://mocap.cs.cmu.edu/) makes the recorded motions available for all uses. The two trials here were retrieved as the MotionBuilder BVH conversion from [una-dinosauria/cmu-mocap](https://github.com/una-dinosauria/cmu-mocap/tree/master/data/143). These clips retain the source terms.

| Godot clip | Motion | BVH source | SHA-256 |
|---|---|---|---|
| `ladder_climb.tres` | Climb Up And Down Ladder | [143_37.bvh](https://github.com/una-dinosauria/cmu-mocap/blob/master/data/143/143_37.bvh) | `534c04ac1f8299551407d127accef2421da0b5bfaa31b2934573abb5cecec235` |
| `step_over.tres` | Walk And Step Over | [143_14.bvh](https://github.com/una-dinosauria/cmu-mocap/blob/master/data/143/143_14.bvh) | `7d8c2eae5f612d165260362555d979cf70dabc84feeae5548425c79da9d25dc2` |

Godot resources retain the joint directions from the sampled motion, mapped to the bundled Quaternius character's rest skeleton, with root translation removed. The ladder clip uses the ascending section and loops. The step clip is centred on the raised foot.

Regenerate from the repository root with Python and NumPy.

```sh
python3 tools/characters/retarget_player_mocap.py \
  tools/characters/sources/player_motion/143_37.bvh \
  tools/characters/sources/player_motion/143_14.bvh
```
