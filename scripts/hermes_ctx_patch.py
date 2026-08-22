#!/usr/bin/env python3
"""Lower Hermes Agent's minimum-context floor without breaking the source.

The previous attempt at this was a hand edit that reflowed the constructor and
produced ``AttributeError: 'AIAgent' object has no attribute 'api_mode'``. This
script exists so that cannot happen again:

* it rewrites **only** integer literals, never whitespace, never a whole line;
* it backs up every file it touches before writing;
* it byte-compiles each file afterwards and rolls that file back on failure;
* ``--revert`` restores every backup it made.

It is still a patch against vendored source. Prefer raising the inference
server's context window first -- see docs/hermes-context-window.md.

Usage
-----
    python hermes_ctx_patch.py --root <install-dir>                 # dry run
    python hermes_ctx_patch.py --root <install-dir> --min-ctx 32768 --apply
    python hermes_ctx_patch.py --root <install-dir> --revert
"""

from __future__ import annotations

import argparse
import ast
import py_compile
import re
import shutil
import sys
from pathlib import Path

BACKUP_SUFFIX = ".ctxpatch.bak"

SKIP_DIRS = {
    ".git", "__pycache__", "node_modules", "site-packages",
    ".venv", "venv", ".mypy_cache", ".pytest_cache", "dist", "build",
}

# Matches 64000 / 64_000 as a standalone integer literal, not as part of a
# longer number and not immediately after a dot (so 1.64000 is left alone).
LITERAL_RE = re.compile(r"(?<![\w.])64_?000(?![\w.])")


def iter_sources(root: Path):
    for path in sorted(root.rglob("*.py")):
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        yield path


def find_literal_lines(text: str) -> list[tuple[int, str]]:
    """Return (1-based line number, line text) for lines holding the literal.

    Occurrences that sit only inside a trailing comment are skipped. An
    occurrence inside a string *is* rewritten on purpose: the floor is quoted
    back in the ValueError message, and leaving it stale would make the error
    text contradict the check.
    """
    hits: list[tuple[int, str]] = []
    for lineno, line in enumerate(text.splitlines(), start=1):
        if not LITERAL_RE.search(line):
            continue
        code = line.split("#", 1)[0]
        if not LITERAL_RE.search(code):
            continue
        hits.append((lineno, line))
    return hits


def patch_text(text: str, new_value: int) -> tuple[str, int]:
    """Replace the literal on code-bearing lines only. Returns (text, count)."""
    out: list[str] = []
    count = 0
    for line in text.splitlines(keepends=True):
        body = line.split("#", 1)[0]
        if LITERAL_RE.search(body):
            replaced, n = LITERAL_RE.subn(str(new_value), body)
            comment = line[len(body):]
            line = replaced + comment
            count += n
        out.append(line)
    return "".join(out), count


def verify(path: Path) -> str | None:
    """Return an error string if the file no longer compiles, else None."""
    try:
        source = path.read_text(encoding="utf-8")
    except UnicodeDecodeError as exc:
        return f"unreadable: {exc}"
    try:
        ast.parse(source, filename=str(path))
    except SyntaxError as exc:
        return f"SyntaxError line {exc.lineno}: {exc.msg}"
    try:
        py_compile.compile(str(path), doraise=True, quiet=2)
    except py_compile.PyCompileError as exc:
        return str(exc)
    return None


def do_revert(root: Path) -> int:
    backups = [p for p in root.rglob("*" + BACKUP_SUFFIX)
               if not any(part in SKIP_DIRS for part in p.parts)]
    if not backups:
        print("No backups found -- nothing to revert.")
        return 0
    for backup in sorted(backups):
        target = backup.with_suffix("")
        if target.suffix != ".py":
            target = Path(str(backup)[: -len(BACKUP_SUFFIX)])
        shutil.copy2(backup, target)
        backup.unlink()
        print(f"reverted  {target}")
    print(f"\n{len(backups)} file(s) restored.")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", required=True, type=Path,
                    help="Hermes Agent install directory")
    ap.add_argument("--min-ctx", type=int, default=32768,
                    help="replacement floor (default: 32768)")
    ap.add_argument("--apply", action="store_true",
                    help="write changes; without it this is a dry run")
    ap.add_argument("--revert", action="store_true",
                    help="restore every backup this script created")
    args = ap.parse_args()

    root: Path = args.root.expanduser()
    if not root.is_dir():
        print(f"error: not a directory: {root}", file=sys.stderr)
        return 2

    if args.revert:
        return do_revert(root)

    if args.min_ctx < 1024:
        print("error: --min-ctx below 1024 is almost certainly a typo", file=sys.stderr)
        return 2

    # --- survey -------------------------------------------------------------
    candidates: list[tuple[Path, list[tuple[int, str]]]] = []
    for path in iter_sources(root):
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        hits = find_literal_lines(text)
        if hits:
            candidates.append((path, hits))

    if not candidates:
        print("No 64000/64_000 literal found in any .py file under:")
        print(f"  {root}")
        print("\nThe floor is probably declared in config.yaml or another data")
        print("file. Run scripts/Repair-HermesInstall.ps1 -Verify to list them.")
        return 1

    print(f"Found the literal in {len(candidates)} file(s):\n")
    for path, hits in candidates:
        rel = path.relative_to(root)
        for lineno, line in hits:
            print(f"  {rel}:{lineno}")
            print(f"      - {line.strip()}")
            print(f"      + {LITERAL_RE.sub(str(args.min_ctx), line.split('#', 1)[0]).strip()}")
        print()

    if not args.apply:
        print("Dry run. Re-run with --apply to write these changes.")
        return 0

    # --- apply --------------------------------------------------------------
    changed = 0
    failed = 0
    for path, _hits in candidates:
        original = path.read_text(encoding="utf-8")
        patched, count = patch_text(original, args.min_ctx)
        if count == 0 or patched == original:
            continue

        backup = Path(str(path) + BACKUP_SUFFIX)
        if not backup.exists():
            shutil.copy2(path, backup)

        path.write_text(patched, encoding="utf-8")
        error = verify(path)
        if error:
            shutil.copy2(backup, path)
            backup.unlink()
            print(f"FAILED    {path.relative_to(root)}  ({error}) -- rolled back",
                  file=sys.stderr)
            failed += 1
            continue

        print(f"patched   {path.relative_to(root)}  ({count} literal(s))")
        changed += 1

    print(f"\n{changed} file(s) patched, {failed} rolled back.")
    if changed:
        print(f"Backups carry the suffix {BACKUP_SUFFIX}; undo with --revert.")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
