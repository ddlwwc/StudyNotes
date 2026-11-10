from __future__ import annotations

import os
from pathlib import Path
from typing import Iterable


SOURCE_SUFFIXES = {".md", ".pdf", ".txt"}


class WorkspaceFileError(ValueError):
    pass


def relative_parts_without_symlinks(
    workspace: Path,
    candidate: Path,
) -> tuple[str, ...]:
    root = workspace.resolve()
    raw_candidate = candidate if candidate.is_absolute() else root / candidate
    try:
        relative = raw_candidate.relative_to(root)
    except ValueError as error:
        raise WorkspaceFileError("文件路径无效。") from error

    current = root
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            raise WorkspaceFileError("不允许访问符号链接。")
    return relative.parts


def safe_workspace_file(
    workspace: Path,
    candidate: Path,
    *,
    allowed_suffixes: Iterable[str] = SOURCE_SUFFIXES,
) -> Path:
    root = workspace.resolve()
    relative_parts_without_symlinks(root, candidate)
    try:
        resolved = candidate.resolve(strict=True)
        resolved.relative_to(root)
    except (OSError, RuntimeError, ValueError) as error:
        raise WorkspaceFileError("文件路径无效。") from error
    if not resolved.is_file() or resolved.suffix.lower() not in set(allowed_suffixes):
        raise WorkspaceFileError("资料文件不存在。")
    return resolved


def safe_source_files(
    workspace: Path,
    *,
    suffixes: Iterable[str] = SOURCE_SUFFIXES,
) -> list[Path]:
    root = workspace.resolve()
    allowed = {suffix.lower() for suffix in suffixes}
    files: list[Path] = []
    for directory, directory_names, file_names in os.walk(
        root,
        followlinks=False,
    ):
        directory_path = Path(directory)
        directory_names[:] = sorted(
            name
            for name in directory_names
            if not name.startswith(".") and not (directory_path / name).is_symlink()
        )
        for name in sorted(file_names):
            if name.startswith("."):
                continue
            candidate = directory_path / name
            if candidate.suffix.lower() not in allowed:
                continue
            try:
                files.append(
                    safe_workspace_file(
                        root,
                        candidate,
                        allowed_suffixes=allowed,
                    )
                )
            except WorkspaceFileError:
                continue
    return sorted(files, key=lambda item: item.as_posix().casefold())


def safe_files_under(
    workspace: Path,
    relative_root: str,
    *,
    suffixes: Iterable[str],
) -> list[Path]:
    root = workspace.resolve()
    allowed = {suffix.lower() for suffix in suffixes}
    try:
        directory = safe_workspace_directory(root, root / relative_root)
    except WorkspaceFileError:
        return []
    files: list[Path] = []
    for candidate in directory.rglob("*"):
        if candidate.is_symlink() or not candidate.is_file():
            continue
        if candidate.suffix.lower() not in allowed:
            continue
        try:
            files.append(
                safe_workspace_file(
                    root,
                    candidate,
                    allowed_suffixes=allowed,
                )
            )
        except WorkspaceFileError:
            continue
    return sorted(files, key=lambda item: item.as_posix().casefold())


def safe_workspace_directory(workspace: Path, candidate: Path) -> Path:
    root = workspace.resolve()
    relative_parts_without_symlinks(root, candidate)
    try:
        resolved = candidate.resolve(strict=True)
        resolved.relative_to(root)
    except (OSError, RuntimeError, ValueError) as error:
        raise WorkspaceFileError("目录路径无效。") from error
    if not resolved.is_dir():
        raise WorkspaceFileError("目录不存在。")
    return resolved
