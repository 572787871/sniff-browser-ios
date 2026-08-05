#!/usr/bin/env python3
"""Generate the bundled Safari content blocker rules for SniffBrowser.

Output: SniffBrowser/Resources/content-blocker-rules.json

Sources (fetched fresh when no local files are given):
  - AdGuard Base (EasyList + AdGuard English, Safari optimized): id=2
  - AdGuard Chinese (EasyList China + AdGuard Chinese, Safari optimized): id=224

WebKit content blockers reject regex disjunctions (``|``), lookarounds and
backreferences, and cap each rule list at 50,000 rules / 10MB. This script
emits one rule per pattern and chunks the result into multiple rule lists
(stored as one JSON array of arrays, ``[[rule...], [rule...]]``), so the
combined coverage can exceed a single list's limits:
  - domain blocks (``||domain^``)
  - path blocks (``||domain/path``, safe subset)
  - simple element hiding (``##selector``, domain-scoped or global)
  - plain exceptions (``@@||domain^`` / ``@@||domain/path``)
Plus a small curated site supplement for known ad containers.
"""

from __future__ import annotations

import json
import os
import re
import sys
import urllib.request

SOURCES = {
    "base": "https://filters.adtidy.org/extension/safari/filters/2_optimized.txt",
    "chinese": "https://filters.adtidy.org/extension/safari/filters/224_optimized.txt",
}
OUTPUT_PATH = "SniffBrowser/Resources/content-blocker-rules.json"

# 输出路径规则；配合多列表分块，不再受单列表 50k/10MB 上限约束。
INCLUDE_PATHS = True

# 单个 WKContentRuleList 分块上限（留余量给 WebKit 编译开销）。
MAX_RULES_PER_LIST = 45_000
MAX_BYTES_PER_LIST = 8 * 1024 * 1024

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

# 站点补充规则：覆盖中文站常见的站内广告容器（随机域名网络 + 站内 banner）。
SITE_SUPPLEMENTS = [
    ("hl365.com", ".article-ads-btn"),
    ("hl365.com", '[id^="article-top-banner"]'),
    ("hl365.com", ".horizontal-banner"),
]

SAFE_SELECTOR_RE = re.compile(r"^[a-zA-Z0-9#._\->+~\[\]=\"'^*$ ,]+$")
SAFE_PATH_RE = re.compile(r"^[a-zA-Z0-9._~%/,-]+$")
PLAIN_HOST_RE = re.compile(r"^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$")


def fetch(url: str) -> str:
    with urllib.request.urlopen(url, timeout=90) as response:
        return response.read().decode("utf-8", errors="ignore")


def is_plain_domain(host: str) -> bool:
    if not PLAIN_HOST_RE.fullmatch(host):
        return False
    if "." not in host or ".." in host or host.startswith(".") or host.endswith("."):
        return False
    return True


def escape_regex(value: str) -> str:
    return (
        value.replace(".", r"\.")
        .replace("-", r"\-")
        .replace("/", r"\/")
        .replace("?", r"\?")
        .replace("+", r"\+")
    )


def valid_selector(selector: str) -> bool:
    selector = selector.strip()
    if not selector:
        return False
    if ":" in selector or "(" in selector or ")" in selector:
        return False
    return bool(SAFE_SELECTOR_RE.fullmatch(selector))


def parse_filter(text: str):
    """Returns (host_blocks, path_blocks, cosmetics, exceptions).

    host_blocks: set[str]
    path_blocks: dict[str, set[str]]
    cosmetics: list[tuple[list[str] | None, str]]  (None = global)
    exceptions: list[tuple[str, str | None]]  (host, path-or-None)
    """
    host_blocks: set[str] = set()
    path_blocks: dict[str, set[str]] = {}
    cosmetics: list[tuple[list[str] | None, str]] = []
    exceptions: list[tuple[str, str | None]] = []

    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("!") or line.startswith("["):
            continue
        if "$" in line or "~" in line or "*" in line:
            # 跳过带选项、排除域或通配符的规则（v1 不做条件匹配）
            continue
        if line.startswith("#@#") or line.startswith("#?#"):
            continue
        if line.startswith("@@"):
            body = line[2:]
            host_match = re.fullmatch(r"\|\|([a-z0-9._-]+)\^", body)
            if host_match and is_plain_domain(host_match.group(1)):
                exceptions.append((host_match.group(1), None))
                continue
            if not INCLUDE_PATHS:
                continue
            path_match = re.fullmatch(
                r"\|\|([a-z0-9._-]+)/([a-zA-Z0-9._~%/,-]+)\^?", body
            )
            if path_match and is_plain_domain(path_match.group(1)):
                exceptions.append((path_match.group(1), path_match.group(2)))
            continue
        if line.startswith("||"):
            body = line[2:]
            host_match = re.fullmatch(r"([a-z0-9._-]+)\^", body)
            if host_match and is_plain_domain(host_match.group(1)):
                host_blocks.add(host_match.group(1))
                continue
            if not INCLUDE_PATHS:
                continue
            path_match = re.fullmatch(
                r"([a-z0-9._-]+)/([a-zA-Z0-9._~%/,-]+)\^?", body
            )
            if path_match:
                domain = path_match.group(1)
                path = path_match.group(2)
                if is_plain_domain(domain) and SAFE_PATH_RE.fullmatch(path):
                    path_blocks.setdefault(domain, set()).add(path)
            continue
        if "##" in line:
            head, _, selector = line.partition("##")
            if not head:
                if valid_selector(selector):
                    cosmetics.append((None, selector.strip()))
                continue
            if head.endswith(".") or head.startswith(".") or "#" in head:
                continue
            domains = [d.strip().lower() for d in head.split(",")]
            if all(is_plain_domain(d) for d in domains) and valid_selector(selector):
                cosmetics.append((domains, selector.strip()))
    return host_blocks, path_blocks, cosmetics, exceptions


def block_trigger(url_filter: str) -> dict:
    return {
        "url-filter": url_filter,
        "load-type": ["third-party", "first-party"],
        "resource-type": RESOURCE_TYPES,
    }


def host_rule(domain: str, action: str) -> dict:
    return {
        "trigger": block_trigger(
            r"^https?://([^/:]+\.)?" + escape_regex(domain) + r"[:/]"
        ),
        "action": {"type": action},
    }


def path_rule(domain: str, path: str, action: str) -> dict:
    return {
        "trigger": block_trigger(
            r"^https?://([^/:]+\.)?"
            + escape_regex(domain)
            + r"/"
            + escape_regex(path)
        ),
        "action": {"type": action},
    }


def cosmetic_rule(domains: list[str] | None, selector: str) -> dict:
    trigger: dict = {"url-filter": ".*"}
    if domains:
        trigger["if-domain"] = domains
    return {
        "trigger": trigger,
        "action": {"type": "css-display-none", "selector": selector},
    }


def build_rules(
    host_blocks: set[str],
    path_blocks: dict[str, set[str]],
    cosmetics: list[tuple[list[str] | None, str]],
    exceptions: list[tuple[str, str | None]],
    supplements: list[tuple[str, str]],
) -> list[dict]:
    rules: list[dict] = []

    exception_hosts = {host for host, _ in exceptions if host}
    for domain in sorted(host_blocks - exception_hosts):
        rules.append(host_rule(domain, "block"))

    exception_paths = {
        (host, path) for host, path in exceptions if path is not None
    }
    for domain in sorted(path_blocks):
        for path in sorted(path_blocks[domain]):
            if (domain, path) in exception_paths:
                continue
            rules.append(path_rule(domain, path, "block"))

    for domains, selector in cosmetics:
        for part in selector.split(","):
            part = part.strip()
            if valid_selector(part):
                rules.append(cosmetic_rule(domains, part))

    for domain, selector in supplements:
        rules.append(cosmetic_rule([domain], selector))

    for host, path in exceptions:
        if path is None:
            rules.append(host_rule(host, "ignore-previous-rules"))
        else:
            rules.append(path_rule(host, path, "ignore-previous-rules"))
    return rules


def chunk_rules(rules: list[dict]) -> list[list[dict]]:
    """把规则按条数与估算体积切成多个分块，每个分块可单独编译。"""
    chunks: list[list[dict]] = []
    current: list[dict] = []
    current_bytes = 0
    for rule in rules:
        # 估算用与最终写入一致的紧凑序列化，避免分块超限误判。
        encoded = json.dumps(rule, ensure_ascii=False, separators=(",", ":"))
        rule_bytes = len(encoded.encode("utf-8")) + 1
        if current and (
            len(current) + 1 > MAX_RULES_PER_LIST
            or current_bytes + rule_bytes > MAX_BYTES_PER_LIST
        ):
            chunks.append(current)
            current = []
            current_bytes = 0
        current.append(rule)
        current_bytes += rule_bytes
    if current:
        chunks.append(current)
    return chunks


def main() -> int:
    local_files = sys.argv[1:]
    if local_files:
        texts = [open(path, encoding="utf-8", errors="ignore").read() for path in local_files]
    else:
        texts = [fetch(url) for url in SOURCES.values()]

    host_blocks: set[str] = set()
    path_blocks: dict[str, set[str]] = {}
    cosmetics: list[tuple[list[str] | None, str]] = []
    exceptions: list[tuple[str, str | None]] = []
    for text in texts:
        hb, pb, cs, ex = parse_filter(text)
        host_blocks |= hb
        for domain, paths in pb.items():
            path_blocks.setdefault(domain, set()).update(paths)
        cosmetics.extend(cs)
        exceptions.extend(ex)

    rules = build_rules(
        host_blocks,
        path_blocks,
        cosmetics,
        exceptions,
        SITE_SUPPLEMENTS,
    )
    if not rules:
        print("没有解析到任何规则", file=sys.stderr)
        return 1

    chunks = chunk_rules(rules)
    for index, chunk in enumerate(chunks):
        size = len(
            json.dumps(
                chunk,
                ensure_ascii=False,
                separators=(",", ":"),
            ).encode("utf-8")
        )
        if len(chunk) > MAX_RULES_PER_LIST or size > MAX_BYTES_PER_LIST:
            print(
                f"分块 {index} 超出上限: {len(chunk)} 条 / {size} 字节",
                file=sys.stderr,
            )
            return 1

    os.makedirs(os.path.dirname(OUTPUT_PATH) or ".", exist_ok=True)
    with open(OUTPUT_PATH, "w", encoding="utf-8") as handle:
        json.dump(chunks, handle, ensure_ascii=False, separators=(",", ":"))
        handle.write("\n")

    print(
        f"host_blocks={len(host_blocks)} path_blocks={sum(len(v) for v in path_blocks.values())} "
        f"cosmetics={len(cosmetics)} exceptions={len(exceptions)} "
        f"total_rules={len(rules)} "
        f"chunks={len(chunks)} per_chunk={[len(c) for c in chunks]} "
        f"file_bytes={os.path.getsize(OUTPUT_PATH)}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
