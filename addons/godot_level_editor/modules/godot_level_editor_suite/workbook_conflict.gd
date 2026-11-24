@tool
extends ConfirmationDialog
## Shared recovery choices when the workbook changed after it was opened.
func offer(owner_panel: Control, reload_disk: Callable, save_copy: Callable) -> void:
	title = "配表已在外部修改"
	dialog_text = "磁盘上的文件已有变化。可以将草稿另存为新文件，或放弃草稿并读取磁盘版本。"
	ok_button_text = "另存草稿"
	cancel_button_text = "保留草稿"
	add_button("放弃草稿并重读", false, "reload")
	owner_panel.add_child(self)
	confirmed.connect(save_copy)
	custom_action.connect(func(action: StringName):
		if action == &"reload":
			hide()
			reload_disk.call())
	visibility_changed.connect(func():
		if not visible: queue_free())
	popup_centered()
