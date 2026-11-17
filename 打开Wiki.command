#!/bin/zsh
task_root="$(cd -- "$(dirname -- "$0")" && pwd)"
cd "$task_root" || exit 1
python3 tools/wiki/wiki.py serve --open
task_status=$?
if (( task_status != 0 )); then
  print "Wiki 未能启动，请查看上面的提示。按回车关闭。"
  read -r
fi
exit "$task_status"
