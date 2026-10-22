#!/usr/bin/env bash
# Preserve F13-F15 aliases; forward F16-F20 as function keys on Hyprland.
set -euo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export HYPRLAND_INSTANCE_SIGNATURE="${HYPRLAND_INSTANCE_SIGNATURE:-$(systemctl --user show-environment | sed -n 's/^HYPRLAND_INSTANCE_SIGNATURE=//p')}"
: "${HYPRLAND_INSTANCE_SIGNATURE:?An active Hyprland session is required}"
python3 - "$repo_dir" <<'PYTHON'
import datetime, json, os, pathlib, shutil, subprocess, sys, time
repo = pathlib.Path(sys.argv[1])
config = pathlib.Path(os.environ.get("XDG_CONFIG_HOME", pathlib.Path.home() / ".config"))
state = pathlib.Path(os.environ.get("XDG_STATE_HOME", pathlib.Path.home() / ".local/state"))
input_file = config / "hypr/input.lua"
if not input_file.is_file() or input_file.is_symlink():
    raise SystemExit("Expected a host-owned Hyprland input.lua file")
options = json.loads(subprocess.check_output(["hyprctl", "getoption", "input:kb_options", "-j"]))["str"]
parts = [v for v in options.split(",") if v]
if "fkeys:basic_13-24" not in parts:
    parts.append("fkeys:basic_13-24")
options = ",".join(parts)
# Encode as a Lua string without inserting untrusted source code.
quoted = json.dumps(options)
lua = (repo / "config/hypr/waynergy-function-keys.lua").read_text().replace('"__KB_OPTIONS__"', quoted)
snippet = config / "waynergy/config.ini.d/macos-function-keys.ini"
helper = config / "hypr/waynergy-function-keys.lua"
hook = 'dofile((os.getenv("XDG_CONFIG_HOME") or os.getenv("HOME") .. "/.config") .. "/hypr/waynergy-function-keys.lua")'
input_text = input_file.read_text()
backup = state / "waynergy-backups" / ("macos-function-keys-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f"))
backup.mkdir(parents=True, mode=0o700)
for target in [snippet, helper, input_file]:
    if target.exists():
        shutil.copy2(target, backup / target.name)
    else:
        with (backup / "previously-absent").open("a") as out:
            out.write(str(target) + "\n")
snippet.parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile(repo / "config/waynergy/config.ini.d/macos-function-keys.ini", snippet)
snippet.chmod(0o600)
helper.write_text(lua)
if hook not in input_text.splitlines():
    input_file.write_text(input_text.rstrip() + "\n\n-- Waynergy function-key symbols (owned by its scoped installer).\n" + hook + "\n")
# A slow host config can time out the reload reply; verify the resulting state.
reload_result = subprocess.run(["hyprctl", "reload"], capture_output=True, text=True)
if reload_result.returncode:
    print("Reload reply failed; checking configuration and applied device options.", file=sys.stderr)
errors = subprocess.check_output(["hyprctl", "configerrors"], text=True).strip()
if errors:
    raise SystemExit("Hyprland reported configuration errors; backup: " + str(backup) + "\n" + errors)
active = subprocess.run(["systemctl", "--user", "is-active", "--quiet", "waynergy.service"]).returncode == 0
if active:
    subprocess.run(["systemctl", "--user", "restart", "waynergy.service"], check=True)
    for attempt in range(20):
        devices = json.loads(subprocess.check_output(["hyprctl", "devices", "-j"]))["keyboards"]
        matches = [d for d in devices if d["name"] == "hl-virtual-keyboard-waynergy"]
        if matches and matches[0]["options"] == options:
            break
        time.sleep(0.25)
    else:
        raise SystemExit("Waynergy device options did not converge; backup: " + str(backup))
elif reload_result.returncode:
    raise SystemExit("Reload was not confirmed; backup: " + str(backup))
print("Function-key configuration installed; backup:", backup)
PYTHON
