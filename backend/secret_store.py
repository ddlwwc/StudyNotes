from __future__ import annotations

import os
import subprocess


SERVICE_NAME = "com.studynotes.model"
ACCOUNT_NAME = "openai-compatible"
_memory_secrets: dict[str, str] = {}


def _use_memory() -> bool:
    return (
        os.environ.get("STUDY_NOTES_SECRET_BACKEND") == "memory"
        or os.uname().sysname != "Darwin"
    )


def save_api_key(api_key: str) -> None:
    if _use_memory():
        _memory_secrets[ACCOUNT_NAME] = api_key
        return

    result = subprocess.run(
        [
            "security",
            "add-generic-password",
            "-U",
            "-s",
            SERVICE_NAME,
            "-a",
            ACCOUNT_NAME,
            "-w",
            api_key,
        ],
        capture_output=True,
        check=False,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError("无法把 API Key 写入系统 Keychain。")


def load_api_key() -> str:
    if _use_memory():
        return _memory_secrets.get(ACCOUNT_NAME, "")

    result = subprocess.run(
        [
            "security",
            "find-generic-password",
            "-s",
            SERVICE_NAME,
            "-a",
            ACCOUNT_NAME,
            "-w",
        ],
        capture_output=True,
        check=False,
        text=True,
    )
    if result.returncode != 0:
        return ""
    return result.stdout.strip()


def has_api_key() -> bool:
    return bool(load_api_key())
