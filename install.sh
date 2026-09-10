#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

./build.sh
python3 - <<'PY'
from pathlib import Path
import os
import shutil

source = Path('dist/KeyClick.app').resolve()
applications = Path('/Applications/KeyClick.app')
desktop_link = Path.home() / 'Desktop' / '键点 KeyClick.app'

if applications.exists() or applications.is_symlink():
    if applications.is_symlink() or applications.is_file():
        applications.unlink()
    else:
        shutil.rmtree(applications)
shutil.copytree(source, applications, copy_function=shutil.copy2)

if desktop_link.is_symlink() or desktop_link.is_file():
    desktop_link.unlink()
elif desktop_link.exists():
    raise SystemExit(f'桌面已存在同名文件夹，未覆盖：{desktop_link}')
os.symlink(applications, desktop_link)
print(f'Installed: {applications}')
print(f'Desktop shortcut: {desktop_link}')
PY
codesign --verify --deep --strict /Applications/KeyClick.app
printf '✔ 已安装到 /Applications，并已创建桌面替身。\n'
