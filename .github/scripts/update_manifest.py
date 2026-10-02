"""Writes version.json and manifest.json for the in-game theme updater
(Scripts/SL-Helpers-ThemeUpdate.lua).

manifest.json lists every file the theme ships (files in the commit, leaving out
dotfiles and .github/) with its SHA-256 and size. version.json only names the commit and
its version, so the startup check stays small.

The version is ThemeInfo.ini's major.minor and the number of commits, e.g. 1.0.42, so
every published commit gets a new one without anyone editing ThemeInfo.ini (bump its
major or minor there for a bigger release). Needs the full history (fetch-depth: 0).

Usage: python3 .github/scripts/update_manifest.py <output dir>
"""
import hashlib
import json
import os
import subprocess
import sys


def git(*args):
    return subprocess.check_output(["git", *args]).decode("utf-8").strip()


def theme_version():
    base = "1.0"
    try:
        info = git("show", "HEAD:ThemeInfo.ini")
    except subprocess.CalledProcessError:
        info = ""
    for line in info.splitlines():
        key, _, value = line.partition("=")
        parts = value.strip().split(".")
        if key.strip().lower() == "version" and len(parts) >= 2 and parts[0].isdigit() and parts[1].isdigit():
            base = f"{int(parts[0])}.{int(parts[1])}"
    return f"{base}.{git('rev-list', '--count', 'HEAD')}"


def main(out):
    os.makedirs(out, exist_ok=True)
    version = {
        "commit": git("rev-parse", "HEAD"),
        "version": theme_version(),
        "date": git("show", "-s", "--format=%cI", "HEAD"),
        "message": git("show", "-s", "--format=%s", "HEAD"),
    }
    # Hash the committed blobs, which is exactly what raw.githubusercontent.com serves
    # (the working tree could differ, e.g. in line endings).
    entries = []
    for line in subprocess.check_output(["git", "ls-tree", "-r", "-z", "--full-tree", "HEAD"]).decode("utf-8").split("\0"):
        if not line:
            continue
        meta, path = line.split("\t", 1)
        mode, kind, sha = meta.split()
        # Regular files only (no symlinks or submodules), and no dotfiles or .github/.
        if kind == "blob" and mode in ("100644", "100755") and not any(part.startswith(".") for part in path.split("/")):
            entries.append((path, sha))

    batch = subprocess.Popen(["git", "cat-file", "--batch"], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    files = {}
    for path, sha in entries:
        batch.stdin.write(sha.encode() + b"\n")
        batch.stdin.flush()
        size = int(batch.stdout.readline().split()[2])
        data = batch.stdout.read(size)
        batch.stdout.read(1)  # trailing newline
        files[path] = {"sha256": hashlib.sha256(data).hexdigest(), "size": size}
    batch.stdin.close()
    batch.wait()

    with open(os.path.join(out, "version.json"), "w") as fh:
        json.dump(version, fh, indent=1)
    with open(os.path.join(out, "manifest.json"), "w") as fh:
        json.dump({**version, "files": files}, fh, separators=(",", ":"), sort_keys=True)
    print(f"{len(files)} files for {version['commit']} (v{version['version']})")


if __name__ == "__main__":
    main(sys.argv[1])
