#!/usr/bin/env python3
"""Generate the bundled Safari content blocker rules from the current EasyList.

Output: SniffBrowser/Resources/content-blocker-rules.json

Usage:
    python3 scripts/build-content-blocker.py                 # fetch latest EasyList
    python3 scripts/build-content-blocker.py path/to/list.txt  # use a local file

The generated JSON only contains domain-wide block rules (``||domain^``) and
their exceptions, grouped into compact regular expressions so the file stays
well below WebKit content rule list limits.
"""

from __future__ import annotations

import json
import re
import sys
import urllib.request

EASYLIST_URL = "https://easylist.to/easylist/easylist.txt"
OUTPUT_PATH = "SniffBrowser/Resources/content-blocker-rules.json"
DOMAINS_PER_GROUP = 110

RESOURCE_TYPES = [
    "image",
    "style-sheet",
    "script",
    "font",
    "raw",
    "media",
    "popup",
    "ping",
]


def fetch_rules(source: str) -> str:
    if source:
        with open(source, encoding="utf-8", errors="ignore") as handle:
            return handle.read()
    with urllib.request.urlopen(EASYLIST_URL, timeout=60) as response:
        return response.read().decode("utf-8", errors="ignore")


def is_plain_domain(host: str) -> bool:
    if not re.fullmatch(r"[a-z0-9]([a-z0-9.-]*[a-z0-9])?", host):
        return False
    if "." not in host:
        return False
    if ".." in host or host.startswith(".") or host.endswith("."):
        return False
    return True


def parse_rules(text: str) -> tuple[set[str], set[str]]:
    block_domains: set[str] = set()
    exception_domains: set[str] = set()
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("!") or line.startswith("["):
            continue
        exception_match = re.fullmatch(r"@@\|\|([a-z0-9._-]+)\^", line)
        if exception_match:
            host = exception_match.group(1).lower()
            if is_plain_domain(host):
                exception_domains.add(host)
            continue
        block_match = re.fullmatch(r"\|\|([a-z0-9._-]+)\^", line)
        if block_match:
            host = block_match.group(1).lower()
            if is_plain_domain(host):
                block_domains.add(host)
    return block_domains, exception_domains


def escape_regex(value: str) -> str:
    return value.replace(".", r"\.")


def build_rule(domains: list[str], action_type: str) -> dict:
    escaped = [escape_regex(domain) for domain in domains]
    url_filter = (
        r"^https?://([^/:]+\.)?("
        + "|".join(escaped)
        + r")([/:]|$)"
    )
    return {
        "trigger": {
            "url-filter": url_filter,
            "load-type": ["third-party", "first-party"],
            "resource-type": RESOURCE_TYPES,
        },
        "action": {"type": action_type},
    }


def build_rules(block_domains: set[str], exception_domains: set[str]) -> list[dict]:
    sorted_blocks = sorted(block_domains - exception_domains)
    rules: list[dict] = []
    for index in range(0, len(sorted_blocks), DOMAINS_PER_GROUP):
        group = sorted_blocks[index : index + DOMAINS_PER_GROUP]
        rules.append(build_rule(group, "block"))
    for host in sorted(exception_domains):
        rules.append(build_rule([host], "ignore-previous-rules"))
    return rules


def main() -> int:
    source = sys.argv[1] if len(sys.argv) > 1 else ""
    text = fetch_rules(source)
    block_domains, exception_domains = parse_rules(text)
    if not block_domains:
        print("No block rules parsed; aborting.", file=sys.stderr)
        return 1
    rules = build_rules(block_domains, exception_domains)
    with open(OUTPUT_PATH, "w", encoding="utf-8") as handle:
        json.dump(rules, handle, ensure_ascii=False)
        handle.write("\n")
    payload_size = len(
        json.dumps(rules, ensure_ascii=False).encode("utf-8")
    )
    print(
        f"block domains: {len(block_domains)}, "
        f"exceptions: {len(exception_domains)}, "
        f"generated rules: {len(rules)}, "
        f"file size: {payload_size} bytes"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
