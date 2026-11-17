# NPC structure regression checks

Run only in a copied project. The scripts refuse to run unless the copy contains
`.npc_structure_qa`. Give the copy a unique Godot application name and custom user
data directory; never reuse an author's editor cache or user data.

- `Godot --headless --path COPY --editor -- --test-npc-structure` checks built-in
  protection, personal saves, imported dependencies, UIDs, generated collision,
  native viewport placement, patrol markers, native scene saves and F6 playback.
- To test updating, hash `content/`, replace only `addons/godot_level_editor/`,
  remove the isolated external source-art fixture, and write
  `npc-update-expected.json` with `files` (res path to SHA256) and `uids` (res path
  to UID string). Run `--test-npc-structure-reopen --capture` in a rendered editor.
- The F6 harness writes `npc-structure-play.json`; editor/update checks write
  `npc-structure-result.json` / `npc-structure-update.json`. Capture output is
  `npc-structure-editor.png` and `npc-structure-play.png`.

The narrative receiver is explicitly connected to a permanent `npc_interact`
node. GuardAI model examples do not themselves provide narrative interaction;
that pre-existing boundary is recorded rather than disguised by the fixture.

The developer sample generator is the only caller using the storage helper's
explicit `allow_builtin` option. Editor actions always treat addon paths as
read-only. Rebuilding shipped examples remains a separate developer operation.
