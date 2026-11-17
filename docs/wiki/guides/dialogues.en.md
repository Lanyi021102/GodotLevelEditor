# Dialogue modes

Open **台本** (Dialogue) in GodotLevelEditor. Existing XLSX and legacy `.tres` dialogue resources can be opened; legacy resources choose an XLSX destination when first saved.

## Choose the mode for each line

Select a group, then a Comment (a playable paragraph). The table shows ID, speaker, dialogue mode and content. Choose **自由对话** (Free) or **站桩对话** (Stationary) in the mode cell, or edit the line's details. Use **保存对白** to write the workbook.

| Mode | Player control | Advance |
|---|---|---|
| Free | Movement and camera remain available | Automatic after the reading duration |
| Stationary | Movement and camera input are blocked; the world continues | F, Enter or a left click |

Modes can be mixed inside one Comment. Finishing a Comment does not automatically play other Comments. Held input does not skip several lines, and the input that opens a conversation does not skip its first line.

## Reading duration

A duration of 0 estimates reading time: roughly five non-Latin characters per second or three Latin/numeric word groups per second, with punctuation pauses and a 2.5-second minimum. A positive duration overrides the estimate for free dialogue. Stationary dialogue always waits for input.

## Save and compatibility

Project dialogue normally lives at `content/tables/dialogues.xlsx`. The `对白` worksheet's `dialogue_mode` stores `free` or `stationary`. Older workbooks without the column are read as free dialogue and gain it when next saved. IDs, ordering, speaker colors, text and existing dialogue categories remain intact.

Edits support undo/redo. Open/save failures preserve the current library and drafts. If the mouse was already released before dialogue, finishing it does not force mouse capture.

See the original [dialogue interface](../../narrative_editor/INTERFACES.md) for schema details.
