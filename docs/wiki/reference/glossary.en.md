# Terms and shortcuts

## Terms

| Term | Meaning |
|---|---|
| Level | A complete `.tscn` map with layout, regions, mechanisms and NPCs |
| Room | A box trigger, not a separate architectural room scene |
| Whitebox | Editable prototype geometry for layout and scale |
| Asset | Reusable scene/definition; source changes can affect many instances |
| Instance | One placed copy with its own transform and identity |
| Assembly | A mechanism scene and its paired graph definition |
| Persistent level graph | Logic that runs independently of task acceptance |
| Event | An ordered group of tasks; it may span levels |
| Task | One objective, bound to exactly one level |
| Task-owned object | Enabled only during its owning task's active lifetime |
| Comment | One callable dialogue paragraph, inside an organizational group |
| Stable ID | The reference key; changing display text does not change it |
| State / event | A continuing fact / a pulse indicating something happened |

## Editing

| Action | Key or entry |
|---|---|
| Play main scene / current scene | F5 / F6 |
| Open or close wheel | 3D toolbar, backtick or mouse side-button tap |
| Place / place repeatedly | Left click on ground during placement |
| Rotate ±15° | R / Shift+R |
| Whitebox wheel page | Mouse wheel; middle-click advances one page |
| Return from submenu / finish placement | Right click; Esc also ends placement |
| Scene save / undo / redo | Native Godot shortcuts for your OS |
| Save editor data | Individual save buttons or the separate window's … menu |

## Player and camera

| Action | Key |
|---|---|
| Move / run | WASD / Shift |
| Jump / interact | Space / F |
| Look | Mouse movement |
| Closer inspection | Hold right mouse button |
| Swap shoulder | V |
| Camera distance | Mouse wheel |
| Recenter behind character | Middle mouse button |
| Release / restore control | Esc / click the game viewport |

These are the plugin's default play controls. Existing project input actions are preserved. The removed timeline/clone controls in old records are not current features.
