"""Build the game and publish it as a GitHub release.

Usage: python3 Tools/release.py VERSION [--draft] [--notes=FILE] [--dry-run]

VERSION is as 1.0 or 1.0.1; the release and its tag are vVERSION, made at
the commit checked out, which must be clean and pushed. Builds the zips of
Tools/build.py, tags, pushes the tag and creates the release with them
through the GitHub CLI (gh). The notes are FILE's, or else a few lines on
what players need, followed by GitHub's list of the changes since the last
release. --draft leaves the release a draft to look over and publish on
GitHub; --dry-run builds and checks, and tags and publishes nothing.
"""
import os
import re
import subprocess
import sys

import build

ROOT = build.ROOT

NOTES = """Neo Drift Out Enhanced {version}, for Linux and Windows (64-bit).

**The game is not included.** It runs on your own copy of the original's
ROMs, as MAME has them: put `neodrift.zip` and `neogeo.zip` beside the game
and start it. See README.txt in the zip.
"""


def git(*args, check=True):
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, check=check).stdout.strip()


def main(args):
    version = None
    draft = dry_run = False
    notes_file = None
    for arg in args:
        if arg == "--draft":
            draft = True
        elif arg == "--dry-run":
            dry_run = True
        elif arg.startswith("--notes="):
            notes_file = arg[len("--notes="):]
        elif not arg.startswith("-") and version is None:
            version = arg
        else:
            sys.exit(__doc__)
    if version is None or not re.fullmatch(r"\d+(\.\d+)*([-+][0-9A-Za-z.]+)?", version.removeprefix("v")):
        sys.exit(__doc__)
    version = version.removeprefix("v")
    tag = "v" + version

    if subprocess.run(["gh", "auth", "status"], capture_output=True).returncode != 0:
        sys.exit("The GitHub CLI is not logged in: run `gh auth login` first.")
    if git("status", "--porcelain"):
        sys.exit("The working tree has changes: commit or stash them first.")
    if git("tag", "--list", tag):
        sys.exit("The tag %s is there already." % tag)
    head = git("rev-parse", "HEAD")
    git("fetch", "--quiet", "origin")
    if not git("branch", "--remotes", "--contains", head):
        sys.exit("%s is not pushed: push it first." % head[:7])

    zips = build.main(["--version=" + version])
    if dry_run:
        print("Dry run: built %s; no tag, no release." % ", ".join(os.path.relpath(z, ROOT) for z in zips))
        return

    build.run("git", "-C", ROOT, "tag", "-a", tag, "-m", "Neo Drift Out Enhanced " + version)
    build.run("git", "-C", ROOT, "push", "origin", tag)
    command = ["gh", "release", "create", tag, *zips, "--verify-tag",
               "--title", "Neo Drift Out Enhanced " + version]
    if notes_file:
        command += ["--notes-file", notes_file]
    else:
        command += ["--notes", NOTES.format(version=version), "--generate-notes"]
    if draft:
        command.append("--draft")
    build.run(*command, cwd=ROOT)


if __name__ == "__main__":
    main(sys.argv[1:])
