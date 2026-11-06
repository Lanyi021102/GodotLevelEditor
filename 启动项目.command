#!/bin/zsh
task_root="$(cd -- "$(dirname -- "$0")" && pwd)"
exec /Applications/Godot.app/Contents/MacOS/Godot --path "$task_root"
