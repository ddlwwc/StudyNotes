from __future__ import annotations

import hashlib
import os
from pathlib import Path
from typing import Protocol

import keyring
from keyring.errors import PasswordDeleteError


QINIU_SERVICE = "com.studynotes.qiniu"
ACCESS_KEY_ACCOUNT = "access-key"
SECRET_KEY_ACCOUNT = "secret-key"


class CredentialStore(Protocol):
    def get(self, account: str) -> str | None: ...

    def set(self, account: str, value: str) -> None: ...

    def delete(self, account: str) -> None: ...


class SystemKeychain:
    def get(self, account: str) -> str | None:
        return keyring.get_password(QINIU_SERVICE, account)

    def set(self, account: str, value: str) -> None:
        keyring.set_password(QINIU_SERVICE, account, value)

    def delete(self, account: str) -> None:
        try:
            keyring.delete_password(QINIU_SERVICE, account)
        except PasswordDeleteError:
            pass


class TestDirectoryCredentialStore:
    """Test-only adapter. Production always uses SystemKeychain."""

    def __init__(self, directory: Path):
        self.directory = directory
        self.directory.mkdir(parents=True, exist_ok=True)

    def path_for(self, account: str) -> Path:
        digest = hashlib.sha256(account.encode("utf-8")).hexdigest()
        return self.directory / f"{digest}.credential"

    def get(self, account: str) -> str | None:
        path = self.path_for(account)
        if not path.exists():
            return None
        return path.read_text(encoding="utf-8")

    def set(self, account: str, value: str) -> None:
        self.path_for(account).write_text(value, encoding="utf-8")

    def delete(self, account: str) -> None:
        self.path_for(account).unlink(missing_ok=True)


def credential_store() -> CredentialStore:
    test_directory = os.environ.get("STUDY_NOTES_TEST_KEYCHAIN_DIR")
    if test_directory:
        return TestDirectoryCredentialStore(Path(test_directory).resolve())
    return SystemKeychain()


def load_qiniu_credentials() -> tuple[str | None, str | None]:
    store = credential_store()
    return store.get(ACCESS_KEY_ACCOUNT), store.get(SECRET_KEY_ACCOUNT)


def save_qiniu_credentials(access_key: str, secret_key: str) -> None:
    store = credential_store()
    store.set(ACCESS_KEY_ACCOUNT, access_key)
    store.set(SECRET_KEY_ACCOUNT, secret_key)
