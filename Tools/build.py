"""Export the game for Linux and Windows and pack each into a zip in Builds/.

Usage: python3 Tools/build.py [--version=VERSION] [linux] [windows]

With no platforms named, builds both. VERSION names the zips; it defaults
to `git describe`. Needs the Godot of Godot/ (or $GODOT) and its export
templates, which it downloads once from Godot's releases if missing.

The zips hold the exported game, a READ ME for players, MODDING.md and the
example mods: nothing from the ROMs. The game asks the player for their own
(Project/boot.gd). To be sure nothing made from the ROMs is packed, it
refuses to export while Project/ has files git does not track.
"""
import os
import shutil
import subprocess
import sys
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT = os.path.join(ROOT, "Project")
BUILDS = os.path.join(ROOT, "Builds")
GODOT_VERSION = "4.7.2"
GODOT = os.environ.get("GODOT", os.path.join(ROOT, "Godot", "Godot_v%s-stable_linux.x86_64" % GODOT_VERSION))
TEMPLATES = os.path.join(os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share")),
                         "godot", "export_templates", "%s.stable" % GODOT_VERSION)
TEMPLATES_URL = ("https://github.com/godotengine/godot/releases/download/%s-stable/"
                 "Godot_v%s-stable_export_templates.tpz" % (GODOT_VERSION, GODOT_VERSION))
NAME = "NeoDriftOutEnhanced"

# platform: (export preset, file exported, template it needs)
PLATFORMS = {
    "linux": ("Linux", NAME + ".x86_64", "linux_release.x86_64"),
    "windows": ("Windows", NAME + ".exe", "windows_release_x86_64.exe"),
}

PLAYER_README = """Neo Drift Out Enhanced {version}
{underline}

An enhanced remake of the Neo Geo rally game Neo Drift Out, rebuilt in the
Godot engine: wide screen, a map of the course, a new HUD, a CRT look,
a course editor and mods.

THE GAME IS NOT INCLUDED. You need your own copy of the original's ROMs, as
MAME has them: neodrift.zip and neogeo.zip (the Neo Geo board's BIOS). Put
both in this folder, next to the game, and start it. The first start takes
what it needs from them into the game's user folder; after that the zips
can go.

  Linux:   ./{linux}
  Windows: {windows}

Keys, until changed in Options: arrows, Z X C V for the buttons A B C D,
1 start, 5 coin, Esc pause. F2 the CRT look, F3 the HUD, M the map,
F11 full screen. Gamepads work too.

Mods go in a folder named mods next to the game. See MODDING.md, and the
examples in mod_examples.
"""


def run(*command, **kwargs):
    print("+", " ".join(command), flush=True)
    subprocess.run(command, check=True, **kwargs)


def version_from_git():
    out = subprocess.run(["git", "describe", "--tags", "--always", "--dirty"], cwd=ROOT,
                         capture_output=True, text=True)
    return out.stdout.strip() or "dev"


def check_project_is_tracked():
    """Stop if Project/ has any file git does not track, but Godot's cache."""
    out = subprocess.run(["git", "ls-files", "--others", "Project"], cwd=ROOT,
                         capture_output=True, text=True, check=True).stdout.split()
    stray = [path for path in out if not path.startswith("Project/.godot/")]
    if stray:
        sys.exit("Project/ has files git does not track, which would be exported:\n  "
                 + "\n  ".join(stray) + "\nCommit them or take them away first.")


def ensure_templates(platforms):
    if all(os.path.exists(os.path.join(TEMPLATES, PLATFORMS[p][2])) for p in platforms):
        return
    print("Export templates for Godot %s missing; downloading them (about 1 GB)." % GODOT_VERSION)
    os.makedirs(BUILDS, exist_ok=True)
    tpz = os.path.join(BUILDS, "export_templates.tpz")
    urllib.request.urlretrieve(TEMPLATES_URL, tpz)
    os.makedirs(TEMPLATES, exist_ok=True)
    with zipfile.ZipFile(tpz) as archive:
        for entry in archive.infolist():
            if entry.is_dir() or not entry.filename.startswith("templates/"):
                continue
            target = os.path.join(TEMPLATES, entry.filename[len("templates/"):])
            with archive.open(entry) as source, open(target, "wb") as out:
                shutil.copyfileobj(source, out)
            os.chmod(target, 0o755)
    os.remove(tpz)


def add_tree(archive, source, inside):
    for folder, _, files in os.walk(source):
        for file in sorted(files):
            path = os.path.join(folder, file)
            archive.write(path, os.path.join(inside, os.path.relpath(path, source)))


def package(platform, version):
    preset, exported, _ = PLATFORMS[platform]
    out_dir = os.path.join(BUILDS, "export", platform)
    shutil.rmtree(out_dir, ignore_errors=True)
    os.makedirs(out_dir)
    binary = os.path.join(out_dir, exported)
    run(GODOT, "--headless", "--path", PROJECT, "--export-release", preset, binary)
    if not os.path.exists(binary):
        sys.exit("Godot did not export %s" % binary)

    folder = "%s-%s-%s" % (NAME, version, platform)
    zip_path = os.path.join(BUILDS, folder + ".zip")
    readme = PLAYER_README.format(version=version, underline="=" * (len("Neo Drift Out Enhanced ") + len(version)),
                                  linux=PLATFORMS["linux"][1], windows=PLATFORMS["windows"][1])
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as archive:
        info = zipfile.ZipInfo(os.path.join(folder, exported))
        info.external_attr = 0o755 << 16
        info.compress_type = zipfile.ZIP_DEFLATED
        with open(binary, "rb") as f:
            archive.writestr(info, f.read())
        info = zipfile.ZipInfo(os.path.join(folder, "README.txt"))
        info.external_attr = 0o644 << 16
        archive.writestr(info, readme if platform != "windows" else readme.replace("\n", "\r\n"))
        archive.write(os.path.join(ROOT, "MODDING.md"), os.path.join(folder, "MODDING.md"))
        add_tree(archive, os.path.join(ROOT, "mod_examples"), os.path.join(folder, "mod_examples"))
        archive.writestr(os.path.join(folder, "mods") + "/", "")
    print("Made", os.path.relpath(zip_path, ROOT))
    return zip_path


def main(args):
    version = version_from_git()
    platforms = []
    for arg in args:
        if arg.startswith("--version="):
            version = arg[len("--version="):]
        elif arg in PLATFORMS:
            platforms.append(arg)
        else:
            sys.exit(__doc__)
    platforms = platforms or list(PLATFORMS)
    if not os.path.exists(GODOT):
        sys.exit("Godot not found at %s (set $GODOT)" % GODOT)
    check_project_is_tracked()
    ensure_templates(platforms)
    # a fresh clone has no import cache yet
    run(GODOT, "--headless", "--path", PROJECT, "--import")
    return [package(platform, version) for platform in platforms]


if __name__ == "__main__":
    main(sys.argv[1:])
