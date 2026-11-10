from __future__ import annotations

import posixpath
import re
from pathlib import Path
from urllib.parse import unquote

from workspace_files import safe_source_files


STANDARD_LINK_RE = re.compile(r"(?<!!)\[([^\]]*)\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
WIKI_LINK_RE = re.compile(r"\[\[([^\]]+)\]\]")
REMOTE_LINK_RE = re.compile(r"^[a-z][a-z0-9+.-]*:", re.IGNORECASE)


def _normalize_target(value: str, source_path: str, *, wiki: bool) -> str | None:
    raw_target = unquote(value.strip().split("#", 1)[0])
    if not raw_target or raw_target.startswith("#") or REMOTE_LINK_RE.match(raw_target):
        return None
    if wiki and not raw_target.startswith("/") and not posixpath.splitext(raw_target)[1]:
        raw_target = f"{raw_target}.md"
    source_directory = posixpath.dirname(source_path)
    if raw_target.startswith("/"):
        resolved = posixpath.normpath(raw_target.lstrip("/"))
    else:
        resolved = posixpath.normpath(posixpath.join(source_directory, raw_target))
    if resolved in {".", ".."} or resolved.startswith("../"):
        return None
    return resolved


def extract_links(markdown: str, source_path: str) -> list[dict[str, str]]:
    links: list[dict[str, str]] = []
    for line in markdown.splitlines():
        for match in STANDARD_LINK_RE.finditer(line):
            target = _normalize_target(match.group(2), source_path, wiki=False)
            if target is None:
                continue
            links.append(
                {
                    "sourcePath": source_path,
                    "targetPath": target,
                    "label": match.group(1).strip() or target,
                    "syntax": "markdown",
                    "context": line.strip(),
                }
            )
        for match in WIKI_LINK_RE.finditer(line):
            raw_target = match.group(1).split("|", 1)[0].strip()
            target = _normalize_target(raw_target, source_path, wiki=True)
            if target is None:
                continue
            label = (
                match.group(1).split("|", 1)[1].strip()
                if "|" in match.group(1)
                else raw_target
            )
            links.append(
                {
                    "sourcePath": source_path,
                    "targetPath": target,
                    "label": label,
                    "syntax": "wiki",
                    "context": line.strip(),
                }
            )
    unique: list[dict[str, str]] = []
    seen: set[tuple[str, str, str]] = set()
    for link in links:
        key = (link["sourcePath"], link["targetPath"], link["syntax"])
        if key in seen:
            continue
        seen.add(key)
        unique.append(link)
    return unique


def workspace_link_graph(workspace: Path, current_path: str) -> dict[str, object]:
    root = workspace.resolve()
    markdown_files = safe_source_files(root, suffixes={".md"})
    existing_paths = {
        file_path.relative_to(root).as_posix() for file_path in markdown_files
    }
    outgoing: list[dict[str, str]] = []
    backlinks: list[dict[str, str]] = []
    unresolved: list[dict[str, str]] = []
    for file_path in markdown_files:
        source_path = file_path.relative_to(root).as_posix()
        try:
            markdown = file_path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        for link in extract_links(markdown, source_path):
            if link["targetPath"] not in existing_paths:
                if source_path == current_path:
                    unresolved.append(link)
                continue
            if source_path == current_path:
                outgoing.append(link)
            if link["targetPath"] == current_path and source_path != current_path:
                backlinks.append(link)
    return {
        "backlinks": backlinks,
        "outgoing": outgoing,
        "unresolved": unresolved,
    }
