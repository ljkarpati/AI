#!/usr/bin/env python3
"""Report the endpoint / context / model fields in a Hermes Agent config.yaml.

Written because the config could not be inspected directly: it lives on a
Windows filesystem this tooling has no access to. Run it locally and the
output is enough to review the structure.

It reads and reports; it never writes. Findings are ranked:

  ERROR  -- will break at runtime
  WARN   -- probably wrong, worth a look
  INFO   -- context for review

Usage:
    python inspect_config.py --config "<path-to-config.yaml>"
    python inspect_config.py --config ... --probe    # also test the endpoint
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

try:
    import yaml
except ImportError:
    print("error: PyYAML is required.  pip install pyyaml", file=sys.stderr)
    raise SystemExit(2)

# Keys worth surfacing, matched case-insensitively against the flattened path.
INTERESTING = (
    "base_url", "api_base", "endpoint", "url", "host", "port",
    "model", "model_name",
    "context", "n_ctx", "ctx", "max_tokens", "window",
    "api_key", "api_mode", "provider", "backend",
)

SECRETISH = ("api_key", "token", "secret", "password")

findings: list[tuple[str, str]] = []


def note(level: str, msg: str) -> None:
    findings.append((level, msg))


def flatten(node, prefix=""):
    """Yield (dotted.path, value) for every scalar in a nested structure."""
    if isinstance(node, dict):
        for key, value in node.items():
            yield from flatten(value, f"{prefix}.{key}" if prefix else str(key))
    elif isinstance(node, list):
        for index, value in enumerate(node):
            yield from flatten(value, f"{prefix}[{index}]")
    else:
        yield prefix, node


def redact(path: str, value):
    if any(s in path.lower() for s in SECRETISH) and isinstance(value, str) and value:
        return f"<set, {len(value)} chars>"
    return value


def check_base_url(path: str, value: str) -> None:
    """A malformed base_url is the single most common cause of silent fallback."""
    if not isinstance(value, str) or not value.startswith(("http://", "https://")):
        return

    host_part = re.sub(r"^https?://", "", value).split("/", 1)[0]
    host = host_part.rsplit(":", 1)[0] if ":" in host_part else host_part

    # A dotted-quad that is not four octets, e.g. the reported "127.0.0".
    if re.fullmatch(r"[\d.]+", host) and len(host.split(".")) != 4:
        note("ERROR", f"{path}: '{value}' -- '{host}' is not a valid IPv4 address "
                      f"(expected four octets). Use http://127.0.0.1:8080/v1")
        return

    if host in ("127.0.0.1", "localhost") and ":" not in host_part:
        note("WARN", f"{path}: '{value}' has no port. llama-server defaults to 8080; "
                     f"most clients will try 80. Use http://127.0.0.1:8080/v1")

    if "127.0.0.1" in value or "localhost" in value:
        if not re.search(r"/v\d+/?$", value.rstrip("/") + "/"):
            note("WARN", f"{path}: '{value}' does not end in /v1. llama-server's "
                         f"OpenAI-compatible routes are served under /v1.")

    if re.search(r"(groq|openai|anthropic)\.com", value):
        note("WARN", f"{path}: '{value}' points at a public endpoint, not the "
                     f"local server.")


def probe(base_url: str) -> None:
    root = re.sub(r"/v\d+/?$", "", base_url.rstrip("/"))
    try:
        with urllib.request.urlopen(f"{root}/props", timeout=5) as resp:
            props = json.load(resp)
    except (urllib.error.URLError, OSError, json.JSONDecodeError) as exc:
        note("ERROR", f"probe: no answer from {root}/props ({exc}). "
                      f"Is llama-server running?")
        return

    settings = props.get("default_generation_settings", {}) or {}
    n_ctx = settings.get("n_ctx") or settings.get("n_ctx_per_seq") or props.get("n_ctx")
    note("INFO", f"probe: server answered at {root}")
    if n_ctx:
        note("INFO", f"probe: server n_ctx = {int(n_ctx):,}")
        if int(n_ctx) < 64000:
            note("WARN", f"probe: {int(n_ctx):,} is below Hermes' 64,000 floor -- "
                         f"it will refuse until the floor is lowered or the "
                         f"context raised.")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--config", required=True, type=Path)
    ap.add_argument("--probe", action="store_true",
                    help="also query the configured endpoint's /props")
    args = ap.parse_args()

    path: Path = args.config.expanduser()
    if not path.is_file():
        print(f"error: no such file: {path}", file=sys.stderr)
        return 2

    raw = path.read_text(encoding="utf-8")
    try:
        data = yaml.safe_load(raw)
    except yaml.YAMLError as exc:
        print(f"error: {path} is not valid YAML:\n{exc}", file=sys.stderr)
        return 1

    if data is None:
        print(f"error: {path} parsed as empty.", file=sys.stderr)
        return 1
    if not isinstance(data, (dict, list)):
        print(f"error: {path} is a bare scalar, not a mapping.", file=sys.stderr)
        return 1

    print(f"# {path}")
    print(f"# {len(raw.splitlines())} lines, top-level keys: "
          f"{', '.join(data) if isinstance(data, dict) else '(list)'}\n")

    pairs = list(flatten(data))
    shown = [(p, v) for p, v in pairs
             if any(k in p.lower() for k in INTERESTING)]

    print("## Fields relevant to the endpoint and context window\n")
    if shown:
        width = max(len(p) for p, _ in shown)
        for p, v in shown:
            print(f"  {p:<{width}}  = {redact(p, v)!r}")
    else:
        print("  none matched -- the config may nest them under names not "
              "searched for.\n  Top-level keys are listed above.")
    print()

    base_urls: list[str] = []
    for p, v in pairs:
        low = p.lower()
        if isinstance(v, str) and any(k in low for k in ("base_url", "api_base", "endpoint")):
            check_base_url(p, v)
            if v.startswith(("http://", "https://")):
                base_urls.append(v)
        # A configurable floor makes the source patch unnecessary -- always
        # prefer changing it here.
        if isinstance(v, int) and re.search(r"min(imum)?_?_?context|context_?min", low):
            note("WARN", f"{p} = {v:,} -- the 64,000 floor appears to be a CONFIG "
                         f"value, not a hardcoded constant. Lower it here instead "
                         f"of patching Python source.")
        elif any(k in low for k in ("context", "n_ctx")) and isinstance(v, int):
            if v < 64000:
                note("INFO", f"{p} = {v:,} (below the 64,000 floor)")

    if args.probe:
        if base_urls:
            probe(base_urls[0])
        else:
            note("WARN", "probe: no base_url found in the config to probe.")

    print("## Findings\n")
    if not findings:
        print("  Nothing flagged.")
    else:
        order = {"ERROR": 0, "WARN": 1, "INFO": 2}
        for level, msg in sorted(findings, key=lambda f: order[f[0]]):
            print(f"  [{level:<5}] {msg}")
    print()
    return 1 if any(l == "ERROR" for l, _ in findings) else 0


if __name__ == "__main__":
    raise SystemExit(main())
