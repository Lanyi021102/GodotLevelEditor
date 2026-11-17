# Sky and environment

Open **天空** (Sky). Pick a preset on the left and edit the relevant category on the right. Preview and level binding are separate actions.

## Parameter groups

| Group | Controls |
|---|---|
| Sky background | Procedural sky, HDRI or lighting template; colors, brightness, HDRI import/rotation |
| Time and sun | Time, sun elevation/azimuth, path rotation, light color/energy, size and shadows |
| Ambient light | Fill source, color, energy and fixed exposure |
| Clouds | Enabled state, coverage, color, height, scale and seed |
| Fog | Enabled state, color, start/end distance and density |

Time accepts values such as `07:30`. Numbers support typing, arrows and sliders. Colors support the picker or `#RRGGBB`. Cloud coverage and fog density are displayed as percentages; distances use meters. Invalid values restore the previous valid value and show the reason.

## Sun position

Time mode computes sun angles. Switching to manual angles keeps the current computed position in the same undo action. The illustrative path uses 06:00 sunrise, 12:00 noon and 18:00 sunset; it does not use geographic coordinates or astronomical dates. A below-horizon sun disables direct sunlight.

HDRI's photographed sun/clouds do not move with this clock. The scene's directional sun is configured independently. Procedural clouds are static sky parameters; this editor does not generate a cloud sea.

## Preview, save, bind

1. Open the target map in the native editor.
2. Pick/edit a preset and use **临时预览** (Temporary preview). Changes update the viewport; ending preview restores its environment.
3. Use the neutral check or compare-bound option when assessing lighting.
4. Save the preset. Built-ins are saved as a new custom preset under `content/resources/sky_presets/custom/`.
5. Use **绑定到当前关卡** (Bind to current level), then save the scene. Save a dirty preset before binding it.

The level root's native `sky_preset` property also holds this reference. A temporary preview does not change the stored binding.

Inherited maps retain and display their template's sky unless overridden. Native Save and Save As refresh the preset's level references. My Levels details and Level Editing also show the actual sky name.

HDRI is copied into the project's `content/assets/sky_hdri/`. While importing, preset switching/new/copy/restore/save and binding are blocked to protect the correct draft; unrelated values in the same draft remain editable. Ending preview and closing the window remain available. See [HDRI troubleshooting](../faq.md#hdri-import).
