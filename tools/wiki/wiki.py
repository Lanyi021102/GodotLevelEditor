#!/usr/bin/env python3
"""Cross-platform entry point for the repository's MkDocs Wiki."""

import argparse
import os
from pathlib import Path
import subprocess
import sys
import venv

ROOT = Path(__file__).resolve().parents[2]
ENV = ROOT / ".venv-wiki"
PYTHON = ENV / ("Scripts/python.exe" if os.name == "nt" else "bin/python")
REQUIREMENTS = ROOT / "requirements-wiki.txt"


def run(arguments):
    subprocess.run([str(item) for item in arguments], cwd=ROOT, check=True)


def setup():
    if not PYTHON.exists():
        print("创建 Wiki 专用 Python 环境：.venv-wiki", flush=True)
        venv.EnvBuilder(with_pip=True).create(ENV)
    # Check declared versions without fetching the network on every launch.
    check = (
        "from importlib.metadata import version; from pathlib import Path; "
        "pairs=[line.strip().split('==') for line in "
        "Path('requirements-wiki.txt').read_text().splitlines() "
        "if line.strip() and not line.startswith('#')]; "
        "assert all(version(name)==expected for name,expected in pairs)"
    )
    installed = subprocess.run([str(PYTHON), "-c", check], cwd=ROOT, capture_output=True)
    if installed.returncode:
        print("安装固定版本的 Wiki 依赖（首次使用需要网络）…", flush=True)
        run([PYTHON, "-m", "pip", "install", "-r", REQUIREMENTS])


def main():
    parser = argparse.ArgumentParser(description="构建、检查或预览 GodotLevelEditor Wiki")
    parser.add_argument("command", choices=["setup", "build", "check", "serve"])
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--open", action="store_true", dest="open_browser")
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("端口必须在 1 到 65535 之间")
    setup()
    if args.command == "setup":
        print("Wiki 环境已就绪。")
    elif args.command in ("build", "check"):
        run([PYTHON, "-m", "mkdocs", "build", "--strict"])
        if args.command == "check":
            run([PYTHON, ROOT / "tools/wiki/check.py", "--site", ROOT / "site"])
    else:
        print(f"预览端口：{args.port}；具体地址见下方 MkDocs 输出，按 Ctrl+C 停止。", flush=True)
        command = [PYTHON, "-m", "mkdocs", "serve", "--dev-addr", f"127.0.0.1:{args.port}"]
        if args.open_browser:
            command.append("--open")
        run(command)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
    except subprocess.CalledProcessError as error:
        sys.exit(error.returncode)
