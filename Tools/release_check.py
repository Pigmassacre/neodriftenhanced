#!/usr/bin/env python3
"""Battle-tests the game before a release, and exits non-zero if anything failed.

Runs the game from Project/ with the Godot of Godot/ (or $GODOT), or with --exported the Linux build
Tools/build.py made in Builds/export/linux/, and runs, side by side:

  bots     the run bot (-- --bot <seed>, Project/testing/run_bot.gd) on many seeds, three games each:
           games through the real menus (Arcade, Freeplay's stages, the options changed at random,
           the pause menu) with an autopilot that steers for the course's waypoints, checking the
           machine, the menus and the screens as it goes, and the best times and options on disk
           after each game
  masher   the button masher (-- --masher <seed>, Project/testing/button_masher.gd): random keys,
           pad buttons, clicks and drags from the moment the game starts, as a new player, with the
           window losing focus, changing shape, the pad unplugged and long frames now and then
  saves    the game started on a broken settings.cfg, best_times.bin or mod: empty, cut short,
           garbage or of the wrong shape, then played by the bot and mashed through the menus
  mods     the bot and the masher with the example mods (mod_examples/) installed
  soak     one bot playing many games in a row, whose object, node and resource counts must not keep
           going up from game to game
  kills    a bot's game killed at random moments, and as soon as it writes the best times or the
           options, after which they must still read
  closes   the window closed at a random frame, by the bot mid-game and by the masher anywhere, after
           which the game must quit with no error or leak
  lint     the rules a script can be checked for: no easing by rate * delta, which flies apart on a
           long frame, no file written to user:// in place, which a kill leaves half written, and no
           quitting past game.gd's _quit(), which keeps the best times first
  oldsaves the files each release left (tests/saves/<release>/, made with --keep-saves <release>):
           the game must read them, and keep the options and best times as they were

Every run gets a user data directory of its own, so the player's options and best times are never
touched. A run fails when it crashes, hangs, says it failed, or prints a script error, an error or a
warning, leaks at exit included (the save checks allow errors from the engine reading a broken file,
but no script errors). A run is stopped at its first script error. Each failure is printed with the
command that reproduces it, and its user data directory is kept in Builds/ReleaseCheck/<date and time>/.

--quick runs a smaller set for a check before a commit; the default is the set for a release.
--only picks some of the checks (--only bots,masher). --window runs the masher in a window with the
real renderer instead, three seeds for three minutes one at a time, which also tests what headless
runs can't: shaders, drawing and the audio output. It takes over the screen while it runs.
"""
import argparse
import concurrent.futures
import datetime
import glob
import os
import random
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT = os.path.join(ROOT, "Project")
GODOT_VERSION = "4.7.2"
EXPORTED = os.path.join(ROOT, "Builds", "export", "linux", "NeoDriftOutEnhanced.x86_64")
CHECKS = ("bots", "masher", "saves", "mods", "soak", "kills", "closes", "lint", "oldsaves")
# How many of each run, quick and for a release.
SIZES = {
    "quick": {"bots": 6, "masher": 4, "masher_seconds": 300, "soak_games": 8, "kills": 2, "closes": 6},
    "full": {"bots": 24, "masher": 12, "masher_seconds": 900, "soak_games": 20, "kills": 6, "closes": 20},
}
# The masher runs in a window one at a time, at about the speed the game is drawn.
WINDOW_MASHERS = 3
WINDOW_MASHER_SECONDS = 180
TIMEOUT_SECONDS = 1800
# How long a run goes on after its first script error, for the rest of its output.
SCRIPT_ERROR_GRACE = 1.0
# Godot's errors and warnings, each followed by the line it was raised at.
PROBLEM = re.compile(r"^(USER )?(SCRIPT ERROR|ERROR|WARNING): ")
# Godot's script errors, which are always bugs, whatever file the game was given.
SCRIPT_ERROR = re.compile(r"^(USER )?SCRIPT ERROR: ")
# The soak fails when a count goes up by more than this of itself a game, over the second half of the games.
SOAK_GROWTH_PER_GAME = 0.005
# Godot keeps user:// for the project here, under XDG_DATA_HOME.
USER_DIR = os.path.join("godot", "app_userdata", "Neo Drift Out")
SAVE_FIXTURES = os.path.join(ROOT, "tests", "saves")
SETTINGS = "settings.cfg"
BEST_TIMES = "best_times.bin"
GODOT = None  # the editor binary, without --exported


def _project_constant(path, name):
    with open(os.path.join(PROJECT, path), encoding="utf-8") as file:
        match = re.search(rf"^const {name} := (.+)$", file.read(), re.MULTILINE)
    return eval(match[1].strip(), {})  # a number or a string literal


# The size of best_times.bin (game/best_times.gd), and what boot.gd writes once it has made the pictures.
BEST_TIMES_SIZE = _project_constant("game/best_times.gd", "KEPT_SIZE")
BUILT_VERSION = _project_constant("boot.gd", "BUILT_VERSION")


class Result:
    def __init__(self, check, name, passed, message, command, data_home=None):
        self.check = check
        self.name = name
        self.passed = passed
        self.message = message
        self.command = command
        self.data_home = data_home


def game_command(window=False):
    base = [GODOT, "--path", PROJECT] if GODOT else [EXPORTED]
    return base + ([] if window else ["--headless"]) + ["--fixed-fps", "60"]


def user_dir(data_home):
    """The game's user:// in a user data directory. The exported game reads the ROMs and the pictures made
    from them from user://game (MachineLoader.repo_dir), which links to the repository's."""
    user = os.path.join(data_home, USER_DIR)
    os.makedirs(user, exist_ok=True)
    if not GODOT and not os.path.exists(os.path.join(user, "game")):
        game = os.path.join(user, "game")
        for name in ("neodrift", "neogeo"):
            os.makedirs(os.path.join(game, name))
            for file in os.listdir(os.path.join(ROOT, name)):
                os.symlink(os.path.join(ROOT, name, file), os.path.join(game, name, file))
        data = os.path.join(game, "data", "game")
        os.makedirs(data)
        for file in os.listdir(os.path.join(ROOT, "data", "game")):
            os.symlink(os.path.join(ROOT, "data", "game", file), os.path.join(data, file))
        with open(os.path.join(data, "built.txt"), "w") as built:
            built.write(BUILT_VERSION)
    return user


def start_game(args, data_home, window=False, output=None):
    user_dir(data_home)
    env = dict(os.environ, XDG_DATA_HOME=data_home)
    return subprocess.Popen(game_command(window) + ["--"] + args, env=env, stdout=output or subprocess.PIPE,
                            stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, text=True, errors="replace")


def run_game(args, data_home, timeout=TIMEOUT_SECONDS, window=False):
    """Runs the game with its own user data directory, and gives its exit code (None if it hung or was
    stopped at a script error) and output. Godot goes on after a script error, so a run is stopped a
    moment after its first one."""
    game = start_game(args, data_home, window)
    lines = []
    first_script_error = []

    def read():
        for line in game.stdout:
            lines.append(line.rstrip("\n"))
            if not first_script_error and SCRIPT_ERROR.match(line):
                first_script_error.append(time.monotonic())

    reader = threading.Thread(target=read, daemon=True)
    reader.start()
    deadline = time.monotonic() + timeout
    exit_code = None
    while True:
        try:
            exit_code = game.wait(timeout=0.2)
            break
        except subprocess.TimeoutExpired:
            pass
        now = time.monotonic()
        if now > deadline or (first_script_error and now > first_script_error[0] + SCRIPT_ERROR_GRACE):
            game.kill()
            game.wait()
            exit_code = None if now > deadline else 1
            break
    reader.join(timeout=5)
    output = "\n".join(lines)
    if exit_code == 1 and first_script_error:
        output += "\n(stopped after its first script error)"
    return exit_code, output


def problems(output, allow_engine_errors=False):
    """The errors and warnings in the output, each with the line it was raised at."""
    lines = output.splitlines()
    found = []
    for i, line in enumerate(lines):
        if not PROBLEM.match(line):
            continue
        if allow_engine_errors and not SCRIPT_ERROR.match(line):
            continue
        at = lines[i + 1].strip() if i + 1 < len(lines) and lines[i + 1].lstrip().startswith("at:") else ""
        found.append(f"{line} {at}".strip())
    return found


def result_line(output, prefix):
    """What follows the prefix on the line that says how the run ended: "PASS: ...", "FAIL: ..." or "QUIT: ..."."""
    for line in output.splitlines():
        if line.startswith(prefix) and line[len(prefix):].split(":")[0] in ("PASS", "FAIL", "QUIT"):
            return line[len(prefix):]
    return None


def reproduce(args):
    runner = "Godot/Godot_v%s-stable_linux.x86_64 --path Project" % GODOT_VERSION if GODOT \
        else "Builds/export/linux/NeoDriftOutEnhanced.x86_64"
    return f"XDG_DATA_HOME=$(mktemp -d) {runner} --headless --fixed-fps 60 -- {' '.join(args)}"


def judge(check, name, args, exit_code, output, prefix, allow_engine_errors=False, data_home=None):
    """A Result from a run of the game that prints "<prefix> PASS|FAIL|QUIT: ...", by its output and exit code."""
    command = reproduce(args)
    found = problems(output, allow_engine_errors)
    line = result_line(output, prefix + " ")
    if exit_code is None:
        tail = " | ".join(output.splitlines()[-5:])
        return Result(check, name, False, f"no result after {TIMEOUT_SECONDS} s (hung): {tail}", command, data_home)
    if line is None:
        if found:
            return Result(check, name, False, f"{found[0]}" + (f" (and {len(found) - 1} more)" if len(found) > 1 else ""),
                          command, data_home)
        tail = "\n    ".join(output.splitlines()[-15:])
        return Result(check, name, False, f"exit code {exit_code} without a result (crashed?):\n    {tail}", command, data_home)
    status, _, message = line.partition(": ")
    passed = status in ("PASS", "QUIT") and exit_code == 0 and not found
    if found:
        message += f", but it printed {len(found)} {'error or warning' if len(found) == 1 else 'errors or warnings'}, the first: {found[0]}"
    elif status not in ("PASS", "QUIT"):
        message = f"{status}: {message}"
    elif exit_code != 0:
        message += f", but it quit with exit code {exit_code}"
    return Result(check, name, passed, message, command, data_home)


def bot_job(check, seed, games, out_dir, extra=(), prepare=None):
    def job():
        with tempfile.TemporaryDirectory(prefix="bot-") as data_home:
            if prepare:
                prepare(user_dir(data_home))
            args = ["--bot", str(seed), "--games", str(games), *extra]
            exit_code, output = run_game(args, data_home)
            result = judge(check, f"bot seed {seed}", args, exit_code, output, "BOT", data_home=data_home)
            return keep(result, out_dir), output
    return job


def masher_job(check, seed, seconds, out_dir, window=False, prepare=None):
    def job():
        with tempfile.TemporaryDirectory(prefix="masher-") as data_home:
            if prepare:
                prepare(user_dir(data_home))
            args = ["--masher", str(seed), "--seconds", str(seconds)]
            exit_code, output = run_game(args, data_home, window=window)
            result = judge(check, f"masher seed {seed}", args, exit_code, output, "MASHER", data_home=data_home)
            # A menu that keyboard or pad input leaves without focus is a dead end for a player without a mouse.
            line = result_line(output, "MASHER ") or ""
            if result.passed and "without focus: none" not in line:
                result.passed = False
                result.message = "a menu was left without focus: " + line.partition("menus left without focus: ")[2]
            return keep(result, out_dir), output
    return job


def install_example_mods(user):
    shutil.copytree(os.path.join(ROOT, "mod_examples"), os.path.join(user, "mods"), dirs_exist_ok=True)


# The broken files to start the game on: the file in user://, and what to write there, made from the
# newest kept one (tests/saves/) or "" without one.
def _cut(text):
    return text[: len(text) // 2]


def _set(section, key, value):
    """The file with one value replaced (or added), as a hand edit would."""
    def change(text):
        pattern = re.compile(rf"^{re.escape(key)}=.*$", re.MULTILINE)
        part = re.search(rf"^\[{section}\]$(.*?)(?=^\[|\Z)", text, re.MULTILINE | re.DOTALL)
        if part and pattern.search(part[1]):
            return text[:part.start(1)] + pattern.sub(lambda _: f"{key}={value}", part[1], count=1) + text[part.end(1):]
        return text + f"\n[{section}]\n{key}={value}\n"
    return change


def _bytes(make):
    """A change that makes bytes rather than text."""
    make.binary = True
    return make


def _random_bytes(size, seed):
    rng = random.Random(seed)
    return bytes(rng.randrange(256) for _ in range(size))


def _scrambled_entries(data):
    """The best times with their tables kept whole, the times and names in them garbage."""
    data = bytearray(data or bytes(BEST_TIMES_SIZE))
    rng = random.Random(5)
    # the tables of where the entries are come first; what follows them is the entries
    for i in range(0x40, len(data)):
        data[i] = rng.randrange(256)
    return bytes(data)


SAVE_CASES = {
    "options empty": (SETTINGS, lambda text: ""),
    "options garbage": (SETTINGS, lambda text: "\x00\xff not a save {[("),
    "options cut short": (SETTINGS, _cut),
    "options that are valid": (SETTINGS, lambda text: text),
    "options of the wrong types": (SETTINGS, lambda text: text +
        '\n[picture]\nfull_screen=7\nwindow_size="big"\nvsync=[]\nwide=null\ncrt_curve="x"\n'
        '[game]\ndifficulty="hard"\nhud=1.5\nmap={}\n[sound]\nvolume="loud"\nmusic=[1]\n[mods]\nmods_off="all"\n'),
    "options out of range": (SETTINGS, lambda text: text +
        '\n[picture]\nwindow_size=Vector2i(0, 0)\ncrt_curve=1e+09\n'
        '[game]\ndifficulty=99\nhud=-7\n[sound]\nvolume=-5.0\nmusic=400.0\neffects=nan\n[mods]\nmods_off=[1, null, {}]\n'),
    "controls of the wrong shape": (SETTINGS, lambda text: text +
        '\n[controls]\nup=["key:abc", "button:-5", "axis:99:+"]\ndown=[1, 2, 3]\nleft="key:4194319"\n'
        'right=["axis:0", "button:", ""]\na=["", "", ""]\nstart=[null, {}, []]\npause=["key:0", "button:999", "axis:-1:-"]\n'),
    "every control cleared": (SETTINGS, lambda text: text + "\n[controls]\n" + "".join(
        f'{action}=["", "", ""]\n' for action in ("up", "down", "left", "right", "a", "b", "c", "d", "start", "coin", "pause"))),
    "best times empty": (BEST_TIMES, _bytes(lambda data: b"")),
    "best times cut short": (BEST_TIMES, _bytes(lambda data: (data or bytes(BEST_TIMES_SIZE))[: BEST_TIMES_SIZE // 2])),
    "best times garbage": (BEST_TIMES, _bytes(lambda data: _random_bytes(BEST_TIMES_SIZE, 1))),
    "best times too long": (BEST_TIMES, _bytes(lambda data: (data or bytes(BEST_TIMES_SIZE)) + b"\x00" * 64)),
    "best times with garbage entries": (BEST_TIMES, _bytes(_scrambled_entries)),
    "mod garbage": (os.path.join("mods", "garbage", "mod.cfg"), lambda text: "\x00\xff not a mod {[(\n[mod\nname=\n"),
    "mod of the wrong types": (os.path.join("mods", "wrong_types", "mod.cfg"), lambda text:
        '[mod]\nname=5\ndescription=[]\n[car]\nreplaces="first"\nadds=7\ntop_speed="fast"\ngrip=-3.0\npanel=12\n'
        '[course]\nbase=99\nname={}\ntime="long"\n[graphics]\nscale=0\n[rom]\nnot_hex=5\n0x10=[1, "x"]\nFFFFFFFF=1\n'),
    "mod with a broken picture": (os.path.join("mods", "broken_picture", "graphics", "1.png"), lambda text:
        "\x89PNG\r\n\x1a\n not really a picture"),
}
SAVE_CASES["mod with a broken picture"][1].companion = (os.path.join("mods", "broken_picture", "mod.cfg"),
                                                        '[mod]\nname="Broken"\n[graphics]\nscale=2\n')


def newest_fixture(name):
    fixtures = sorted(glob.glob(os.path.join(SAVE_FIXTURES, "*", name)))
    return fixtures[-1] if fixtures else None


def save_job(case, out_dir):
    path, change = SAVE_CASES[case]
    binary = getattr(change, "binary", False)

    def job():
        with tempfile.TemporaryDirectory(prefix="saves-") as data_home:
            user = user_dir(data_home)
            original = b"" if binary else ""
            fixture = newest_fixture(os.path.basename(path))
            if fixture and not path.startswith("mods"):
                with open(fixture, "rb") as file:
                    original = file.read()
                if not binary:
                    original = original.decode("utf-8", errors="replace")
            target = os.path.join(user, path)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            outputs = []
            result = None
            for args, prefix in ((["--bot", "2", "--games", "2", "--minutes", "2"], "BOT"),
                                 (["--masher", "3", "--seconds", "180"], "MASHER")):
                # Each start reads the broken file again: the game's own play would write it over.
                if binary:
                    with open(target, "wb") as file:
                        file.write(change(original))
                else:
                    with open(target, "w", encoding="utf-8", errors="surrogateescape") as file:
                        file.write(change(original))
                companion = getattr(change, "companion", None)
                if companion:
                    with open(os.path.join(user, companion[0]), "w", encoding="utf-8") as file:
                        file.write(companion[1])
                exit_code, output = run_game(args, data_home)
                outputs.append(output)
                result = judge("saves", case, args, exit_code, output, prefix, allow_engine_errors=True, data_home=data_home)
                result.command = f"(write a broken {path} into the user data directory first) " + result.command
                if not result.passed:
                    return keep(result, out_dir), "\n".join(outputs)
            return result, "\n".join(outputs)
    return job


def soak_job(games, out_dir):
    def job():
        with tempfile.TemporaryDirectory(prefix="soak-") as data_home:
            args = ["--bot", "9000", "--games", str(games), "--minutes", "3"]
            exit_code, output = run_game(args, data_home, timeout=TIMEOUT_SECONDS * 3)
            result = judge("soak", f"{games} games in one run", args, exit_code, output, "BOT", data_home=data_home)
            if result.passed:
                growth = soak_growth(output)
                if growth:
                    result.passed = False
                    result.message = "it keeps growing from game to game: " + "; ".join(growth)
                else:
                    result.message += ", nothing kept growing"
            return keep(result, out_dir), output
    return job


def soak_growth(output):
    """What still goes up by more than SOAK_GROWTH_PER_GAME of itself a game over the second half of the games.
    The first games fill the caches, as sounds, pictures and shaders load when they're first needed, and then
    the counts level off; a leak keeps going up at the same pace."""
    samples = []
    for line in output.splitlines():
        match = re.match(r"BOT MEMORY \d+: objects (\d+), nodes (\d+), orphan nodes (\d+), resources (\d+)", line)
        if match:
            samples.append({"objects": int(match[1]), "nodes": int(match[2]), "orphan nodes": int(match[3]),
                            "resources": int(match[4])})
    second_half = samples[len(samples) // 2:]
    if len(second_half) < 4:
        return []
    grown = []
    for key in second_half[0]:
        values = [sample[key] for sample in second_half]
        per_game = (values[-1] - values[0]) / (len(values) - 1)
        if per_game > max(values[0] * SOAK_GROWTH_PER_GAME, 1.0):
            grown.append(f"{key} +{per_game:.1f} a game ({', '.join(str(sample[key]) for sample in samples)})")
    return grown


# How many times each kill job kills its game.
KILLS_PER_JOB = 6


def _written(user, before):
    """The kept files whose time of change differs from `before`'s, which it updates."""
    changed = False
    for name in (SETTINGS, BEST_TIMES):
        path = os.path.join(user, name)
        try:
            stamp = os.stat(path).st_mtime_ns
        except FileNotFoundError:
            stamp = None
        if before.get(name, stamp) != stamp:
            changed = True
        before[name] = stamp
    return changed


def kill_job(seed, out_dir):
    """Kills a bot's game, again and again in one user data directory: at a random moment, or as soon as it
    has changed the best times or the options. After each, they must still read."""
    def job():
        rng = random.Random(seed)
        mid_write = 0
        outputs = []
        result = None
        with tempfile.TemporaryDirectory(prefix="kills-") as data_home:
            user = user_dir(data_home)
            for kill in range(KILLS_PER_JOB):
                args = ["--bot", str(seed * 100 + kill), "--games", "5", "--minutes", "1"]
                game = start_game(args, data_home, output=subprocess.DEVNULL)
                # Every other kill waits for a write, the rest land anywhere.
                deadline = time.monotonic() + rng.uniform(1.0, 40.0)
                wait_for_write = kill % 2 == 1
                stamps = {}
                _written(user, stamps)
                while game.poll() is None and (wait_for_write or time.monotonic() < deadline):
                    if wait_for_write and _written(user, stamps):
                        mid_write += 1
                        break
                    if time.monotonic() > deadline + 300.0:
                        break
                    time.sleep(0.002)
                game.send_signal(signal.SIGKILL)
                game.wait()

                check_args = ["--bot", str(seed), "--check-save", "--stop-after", "5"]
                exit_code, output = run_game(check_args, data_home)
                outputs.append(output)
                result = judge("kills", f"seed {seed}", check_args, exit_code, output, "BOT", data_home=data_home)
                result.command = f"(kill a bot's game in the user data directory first) {result.command}"
                if not result.passed:
                    result.message = f"after kill {kill + 1}: {result.message}"
                    return keep(result, out_dir), "\n".join(outputs)
            result.message = f"{KILLS_PER_JOB} kills, {mid_write} of them just as a file was written, the files read after each"
            return result, "\n".join(outputs)
    return job


def close_job(seed, out_dir):
    """Closes the window at a random frame, from the bot partway into a game or the masher anywhere."""
    def job():
        rng = random.Random(seed)
        frame = rng.randint(60, 20000)
        with tempfile.TemporaryDirectory(prefix="closes-") as data_home:
            if seed % 2:
                args, prefix, name = ["--bot", str(seed), "--games", "5", "--close-at", str(frame)], "BOT", "bot"
            else:
                args, prefix, name = ["--masher", str(seed), "--seconds", "600", "--close-at", str(frame), "--no-quit"], "MASHER", "masher"
            exit_code, output = run_game(args, data_home)
            result = judge("closes", f"{name} seed {seed} at frame {frame}", args, exit_code, output, prefix, data_home=data_home)
            if result.passed and "closed the window" not in result.message:
                result.passed = False
                result.message = "it ended before the window was closed: " + result.message
            return keep(result, out_dir), output
    return job


# A lerp weighted by the frame time times a rate (lerp(a, b, rate * delta)) rather than 1 - exp(-rate * delta).
LERP_BY_DELTA = re.compile(r"\b(lerp|lerpf|lerp_angle|slerp)\((?:(?!exp\().)*\b(delta|dt)\b(?:(?!exp\().)*\)")
# A file opened for writing, or a ConfigFile or picture saved, in place rather than next to it and then put in
# place, which a kill partway leaves half written.
WRITE_IN_PLACE = re.compile(r"FileAccess\.open\(.*FileAccess\.(WRITE|READ_WRITE)\b|\b(file|config)\.save\(|\.save_png\(")
# Quitting past game.gd's _quit(), which keeps the best times first.
QUIT = re.compile(r"get_tree\(\)\.quit\(")
# What only writes for tools and tests, never a player's files, and the scripts that may quit.
# boot.gd copies the ROMs again when a copy is short, and makes the pictures again until it has written
# built.txt, last, so a kill partway through it costs nothing.
# safe_file.gd is what writes the player's files safely: to NAME.tmp, then put in place.
LINT_SKIPS = ("tools", "testing", os.path.join("mods", "graphics_dump.gd"), "main.gd", "boot.gd", "safe_file.gd")
# Lines of other scripts that write for developers only: screenshots, the views compared and the seed log.
DEVELOPERS_ONLY = ("shot_path", "save_png(path)", "_compare_folder", "seeds")
MAY_QUIT = ("game.gd", "boot.gd", "main.gd")


def lint_job():
    def job():
        found = []
        for path in sorted(glob.glob(os.path.join(PROJECT, "**", "*.gd"), recursive=True)):
            relative = os.path.relpath(path, PROJECT)
            if relative.split(os.sep)[0] in LINT_SKIPS or relative in LINT_SKIPS or relative.startswith("."):
                continue
            with open(path, encoding="utf-8", errors="replace") as file:
                for number, line in enumerate(file, 1):
                    code = line.split("#", 1)[0]
                    where = f"Project/{relative}:{number}"
                    if LERP_BY_DELTA.search(code) and re.search(r"\*\s*(delta|dt)\b|\b(delta|dt)\s*\*", code):
                        found.append(f"{where} eases by the frame time without exp: {code.strip()}")
                    if WRITE_IN_PLACE.search(code) and ".tmp" not in code and "SafeFile." not in code and not any(part in code for part in DEVELOPERS_ONLY):
                        found.append(f"{where} writes a file in place: {code.strip()}")
                    if QUIT.search(code) and relative not in MAY_QUIT:
                        found.append(f"{where} quits past game.gd's _quit(): {code.strip()}")
        return Result("lint", "scripts", not found, f"{len(found)} found" + ("".join(f"\n    {line}" for line in found)),
                      "python3 Tools/release_check.py --only lint"), ""
    return job


def keep_saves(name):
    """Plays as a player would, through the menus with the masher and games with the bot, and keeps the files it
    left in tests/saves/<name>/, for the builds after this release to read."""
    with tempfile.TemporaryDirectory(prefix="keep-saves-") as data_home:
        for args in (["--masher", "7", "--seconds", "240"], ["--bot", "1", "--games", "4", "--minutes", "3"]):
            exit_code, output = run_game(args, data_home)
            if exit_code != 0:
                print(f"{' '.join(args)} failed with exit code {exit_code}:\n{output[-2000:]}", file=sys.stderr)
                return 1
        target = os.path.join(SAVE_FIXTURES, name)
        os.makedirs(target, exist_ok=True)
        kept = 0
        for file in (SETTINGS, BEST_TIMES):
            source = os.path.join(user_dir(data_home), file)
            if os.path.exists(source):
                shutil.copy(source, target)
                kept += 1
        if not kept:
            print("The runs left nothing to keep.", file=sys.stderr)
            return 1
    print(f"Kept the files in {os.path.relpath(target, ROOT)}")
    return 0


def _config(path):
    """The options as {(section, key): value text}."""
    values = {}
    section = ""
    if os.path.exists(path):
        with open(path, encoding="utf-8", errors="replace") as file:
            text = file.read()
        # A value can run over several lines (arrays and dictionaries): a key starts a line, at no indent.
        for match in re.finditer(r"^\[([^\]\n]+)\]$|^([A-Za-z0-9_]+)=(.*?)(?=^\[|^[A-Za-z0-9_]+=|\Z)", text, re.MULTILINE | re.DOTALL):
            if match[1]:
                section = match[1]
            else:
                values[(section, match[2])] = match[3].strip()
    return values


def old_saves_job(fixture, out_dir):
    def job():
        name = f"files of {os.path.basename(fixture)}"
        with tempfile.TemporaryDirectory(prefix="oldsaves-") as data_home:
            user = user_dir(data_home)
            for file_name in os.listdir(fixture):
                shutil.copy(os.path.join(fixture, file_name), user)
            # The bot changes no option and finishes no race in the time it has, so nothing may change.
            args = ["--bot", "2", "--check-save", "--no-options", "--stop-after", "20"]
            exit_code, output = run_game(args, data_home)
            result = judge("oldsaves", name, args, exit_code, output, "BOT", data_home=data_home)
            result.command = f"(copy {os.path.relpath(fixture, ROOT)} into the user data directory first) {result.command}"
            found = []
            before = _config(os.path.join(fixture, SETTINGS))
            after = _config(os.path.join(user, SETTINGS))
            for key, value in before.items():
                if after.get(key) != value:
                    found.append(f"{key[0]}/{key[1]} went from {value[:60]} to {(after.get(key) or 'nothing')[:60]}")
            times = os.path.join(fixture, BEST_TIMES)
            if os.path.exists(times):
                with open(times, "rb") as old, open(os.path.join(user, BEST_TIMES), "rb") as new:
                    if old.read() != new.read():
                        found.append("the best times changed")
            if result.passed and found:
                result.passed = False
                result.message = "; ".join(found)
            return keep(result, out_dir), output
    return job


def keep(result, out_dir):
    """Keeps a failed run's user data directory, to look at what it left."""
    if not result.passed and result.data_home and os.path.isdir(result.data_home):
        kept = os.path.join(out_dir, re.sub(r"[^A-Za-z0-9]+", "-", f"{result.check} {result.name}").strip("-"))
        shutil.copytree(result.data_home, kept, dirs_exist_ok=True, symlinks=True)
        result.data_home = kept
    elif result.passed:
        result.data_home = None
    return result


def find_godot():
    godot = os.environ.get("GODOT") or os.path.join(ROOT, "Godot", f"Godot_v{GODOT_VERSION}-stable_linux.x86_64")
    folder = ROOT
    # a worktree has no Godot/ of its own: look in the folders above
    while not os.environ.get("GODOT") and not os.path.isfile(godot) and folder != os.path.dirname(folder):
        folder = os.path.dirname(folder)
        godot = os.path.join(folder, "Godot", f"Godot_v{GODOT_VERSION}-stable_linux.x86_64")
    return godot if os.path.isfile(godot) else None


def main():
    global GODOT
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--exported", action="store_true",
                        help="run the Linux build in Builds/export/linux/ (Tools/build.py linux) instead of the project")
    parser.add_argument("--quick", action="store_true", help="a smaller set, for a check before a commit")
    parser.add_argument("--only", default=",".join(CHECKS), help=f"the checks to run, of {', '.join(CHECKS)}")
    parser.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) - 2), help="how many games run at once")
    parser.add_argument("--seed", type=int, default=1, help="the first seed of the bots and the masher")
    parser.add_argument("--window", action="store_true", help="run the masher in a window with the real renderer, one at a time")
    parser.add_argument("--keep-saves", metavar="RELEASE", help="keep the files a player of this build leaves in "
                        "tests/saves/RELEASE/, for the oldsaves check of later builds, and do nothing else")
    args = parser.parse_args()

    checks = [check.strip() for check in args.only.split(",") if check.strip()]
    unknown = [check for check in checks if check not in CHECKS]
    if unknown:
        parser.error(f"unknown checks: {', '.join(unknown)}")
    size = SIZES["quick" if args.quick else "full"]

    for needed in ("neodrift", "neogeo", os.path.join("data", "game")):
        if not os.path.isdir(os.path.join(ROOT, needed)):
            print(f"{needed}/ is missing: the game needs the ROMs and what Tools/setup.sh makes of them.", file=sys.stderr)
            return 1
    if args.exported:
        if not os.path.isfile(EXPORTED):
            print(f"No build at {os.path.relpath(EXPORTED, ROOT)}: make one with python3 Tools/build.py linux.", file=sys.stderr)
            return 1
    else:
        GODOT = find_godot()
        if not GODOT:
            print(f"No Godot {GODOT_VERSION} editor found; set GODOT to it.", file=sys.stderr)
            return 1
        # A new class_name only gets known to the project on an import.
        subprocess.run([GODOT, "--headless", "--path", PROJECT, "--import"], capture_output=True)

    if args.keep_saves:
        return keep_saves(args.keep_saves)

    out_dir = os.path.join(ROOT, "Builds", "ReleaseCheck", datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S"))
    os.makedirs(out_dir, exist_ok=True)

    jobs = []
    window_jobs = []
    if "bots" in checks:
        for i in range(size["bots"]):
            jobs.append(bot_job("bots", args.seed + i, 3, out_dir))
    if "masher" in checks:
        # In a window the game plays at about the speed it is drawn, so fewer and shorter.
        count, seconds = (WINDOW_MASHERS, WINDOW_MASHER_SECONDS) if args.window else (size["masher"], size["masher_seconds"])
        for i in range(count):
            job = masher_job("masher", args.seed + i, seconds, out_dir, args.window)
            (window_jobs if args.window else jobs).append(job)
    if "saves" in checks:
        for case in SAVE_CASES:
            jobs.append(save_job(case, out_dir))
    if "mods" in checks:
        for i in range(2):
            jobs.append(bot_job("mods", args.seed + 500 + i, 3, out_dir, prepare=install_example_mods))
            jobs.append(masher_job("mods", args.seed + 500 + i, 300, out_dir, prepare=install_example_mods))
    if "kills" in checks:
        for i in range(size["kills"]):
            jobs.append(kill_job(args.seed + i, out_dir))
    if "closes" in checks:
        for i in range(size["closes"]):
            jobs.append(close_job(args.seed + i, out_dir))
    if "lint" in checks:
        jobs.append(lint_job())
    if "oldsaves" in checks:
        for fixture in sorted(glob.glob(os.path.join(SAVE_FIXTURES, "*"))):
            jobs.append(old_saves_job(fixture, out_dir))
    if "soak" in checks:
        # It goes first, as it takes the longest.
        jobs.insert(0, soak_job(size["soak_games"], out_dir))

    print(f"Running {len(jobs) + len(window_jobs)} checks, {args.jobs} at a time...", flush=True)
    results = []

    def report(result):
        results.append(result)
        print(f"{'PASS' if result.passed else 'FAIL'} {result.check}: {result.name}: {result.message}", flush=True)

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        for future in concurrent.futures.as_completed([pool.submit(job) for job in jobs]):
            report(future.result()[0])
    for job in window_jobs:
        report(job()[0])

    failed = [result for result in results if not result.passed]
    print()
    for check in checks:
        of_check = [result for result in results if result.check == check]
        print(f"{check}: {sum(result.passed for result in of_check)} of {len(of_check)} passed")
    if failed:
        print(f"\n{len(failed)} failed:")
        for result in failed:
            print(f"- {result.check}: {result.name}: {result.message}")
            if result.command:
                print(f"  reproduce: {result.command}")
            if result.data_home:
                print(f"  user data: {result.data_home}")
    else:
        shutil.rmtree(out_dir, ignore_errors=True)
        print("\nEverything passed.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
