from __future__ import annotations

from dataclasses import dataclass
import hashlib
import hmac
import json
import os
from pathlib import Path
import tempfile
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
import uuid

from credentials import load_qiniu_credentials
from storage import (
    application_data_directory,
    load_qiniu_settings,
    save_uploaded_image,
)


MAX_IMAGE_BYTES = 20 * 1024 * 1024
DEFAULT_UPLOAD_URL = "https://upload.qiniup.com"
DEFAULT_MANAGEMENT_URL = "https://rs.qiniu.com"
IMAGE_TYPES = {
    "image/png": (".png", lambda data: data.startswith(b"\x89PNG\r\n\x1a\n")),
    "image/jpeg": (".jpg", lambda data: data.startswith(b"\xff\xd8\xff")),
    "image/gif": (
        ".gif",
        lambda data: data.startswith((b"GIF87a", b"GIF89a")),
    ),
    "image/webp": (
        ".webp",
        lambda data: data.startswith(b"RIFF")
        and len(data) >= 12
        and data[8:12] == b"WEBP",
    ),
}


class QiniuError(RuntimeError):
    pass


@dataclass(frozen=True)
class QiniuConfig:
    access_key: str
    bucket: str
    domain: str
    secret_key: str


def load_qiniu_config() -> QiniuConfig:
    settings = load_qiniu_settings()
    access_key, secret_key = load_qiniu_credentials()
    if (
        settings is None
        or access_key is None
        or secret_key is None
        or not access_key
        or not secret_key
    ):
        raise QiniuError("请先在设置中配置七牛公开桶与凭据。")
    return QiniuConfig(
        access_key=access_key,
        bucket=str(settings["bucket"]),
        domain=str(settings["domain"]).rstrip("/"),
        secret_key=secret_key,
    )


def urlsafe_base64(value: bytes) -> str:
    import base64

    return base64.urlsafe_b64encode(value).decode("ascii").rstrip("=")


def qiniu_token(access_key: str, secret_key: str, encoded_value: str) -> str:
    signature = hmac.new(
        secret_key.encode("utf-8"),
        encoded_value.encode("ascii"),
        hashlib.sha1,
    ).digest()
    return f"{access_key}:{urlsafe_base64(signature)}:{encoded_value}"


def upload_token(config: QiniuConfig, object_key: str) -> str:
    policy = {
        "scope": f"{config.bucket}:{object_key}",
        "deadline": int(time.time()) + 3600,
        "insertOnly": 1,
    }
    encoded_policy = urlsafe_base64(
        json.dumps(policy, separators=(",", ":")).encode("utf-8")
    )
    return qiniu_token(config.access_key, config.secret_key, encoded_policy)


def encoded_entry(config: QiniuConfig, object_key: str) -> str:
    return urlsafe_base64(f"{config.bucket}:{object_key}".encode("utf-8"))


def management_authorization(config: QiniuConfig, object_key: str) -> str:
    entry = encoded_entry(config, object_key)
    return f"QBox {qiniu_token(config.access_key, config.secret_key, entry)}"


def workspace_hash(workspace: Path) -> str:
    return hashlib.sha256(str(workspace.resolve()).encode("utf-8")).hexdigest()[:16]


def validate_image(filename: str, content_type: str, data: bytes) -> str:
    if not filename or not content_type:
        raise QiniuError("图片文件名或类型无效。")
    if not data:
        raise QiniuError("图片内容为空。")
    if len(data) > MAX_IMAGE_BYTES:
        raise QiniuError("图片超过 20 MB 限制。")
    image_format = IMAGE_TYPES.get(content_type)
    if image_format is None:
        raise QiniuError("只支持 PNG、JPEG、GIF 和 WebP 图片。")
    extension, matches_signature = image_format
    if not matches_signature(data):
        raise QiniuError("图片内容与文件类型不匹配。")
    return extension


def multipart_body(
    fields: dict[str, str],
    *,
    file_field: str,
    filename: str,
    content_type: str,
    file_bytes: bytes,
) -> tuple[str, bytes]:
    boundary = f"studynotes-{uuid.uuid4().hex}"
    chunks: list[bytes] = []
    for name, value in fields.items():
        chunks.append(f"--{boundary}\r\n".encode("ascii"))
        chunks.append(
            f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode(
                "utf-8"
            )
        )
        chunks.append(value.encode("utf-8"))
        chunks.append(b"\r\n")
    chunks.append(f"--{boundary}\r\n".encode("ascii"))
    chunks.append(
        (
            f'Content-Disposition: form-data; name="{file_field}"; '
            f'filename="{filename}"\r\n'
            f"Content-Type: {content_type}\r\n\r\n"
        ).encode("utf-8")
    )
    chunks.append(file_bytes)
    chunks.append(b"\r\n")
    chunks.append(f"--{boundary}--\r\n".encode("ascii"))
    return f"multipart/form-data; boundary={boundary}", b"".join(chunks)


def cache_uploaded_image(
    workspace: Path,
    object_key: str,
    data: bytes,
) -> str | None:
    suffix = Path(object_key).suffix
    cache_dir = (
        application_data_directory()
        / "image-cache"
        / workspace_hash(workspace)
    )
    try:
        cache_dir.mkdir(parents=True, exist_ok=True)
        descriptor, temporary_name = tempfile.mkstemp(
            prefix=".image-", suffix=".tmp", dir=cache_dir
        )
        temporary_path = Path(temporary_name)
        try:
            with os.fdopen(descriptor, "wb") as handle:
                handle.write(data)
                handle.flush()
                os.fsync(handle.fileno())
            destination = cache_dir / f"{uuid.uuid4().hex}{suffix}"
            os.replace(temporary_path, destination)
        except Exception:
            temporary_path.unlink(missing_ok=True)
            raise
    except OSError:
        return None
    return str(destination)


def request_json(
    request: Request,
    *,
    error_message: str,
) -> dict[str, object]:
    try:
        with urlopen(request, timeout=20) as response:
            body = response.read()
    except HTTPError as error:
        try:
            error.read()
        except OSError:
            pass
        raise QiniuError(error_message) from error
    except (URLError, TimeoutError, OSError) as error:
        raise QiniuError(error_message) from error
    try:
        payload = json.loads(body.decode("utf-8") or "{}")
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise QiniuError(error_message) from error
    if not isinstance(payload, dict):
        raise QiniuError(error_message)
    return payload


def upload_image(
    workspace: Path,
    filename: str,
    content_type: str,
    data: bytes,
) -> dict[str, object]:
    config = load_qiniu_config()
    extension = validate_image(filename, content_type, data)
    key_hash = workspace_hash(workspace)
    object_key = f"images/{key_hash}/{uuid.uuid4().hex}{extension}"
    upload_url = os.environ.get(
        "STUDY_NOTES_QINIU_UPLOAD_URL", DEFAULT_UPLOAD_URL
    )
    content_type_header, body = multipart_body(
        {
            "token": upload_token(config, object_key),
            "key": object_key,
        },
        file_field="file",
        filename=Path(filename).name,
        content_type=content_type,
        file_bytes=data,
    )
    request = Request(
        upload_url,
        data=body,
        method="POST",
        headers={"Content-Type": content_type_header},
    )
    payload = request_json(request, error_message="图片上传到七牛失败。")
    returned_key = payload.get("key", object_key)
    if returned_key != object_key:
        raise QiniuError("七牛返回了意外的对象键。")

    url = f"{config.domain}/{object_key}"
    cached_path = cache_uploaded_image(workspace, object_key, data)
    uploaded = save_uploaded_image(
        workspace=workspace,
        object_key=object_key,
        url=url,
        mime_type=content_type,
        size=len(data),
        cached_path=cached_path,
    )
    return {
        "cached": cached_path is not None,
        "objectKey": object_key,
        "url": url,
        "uploadedAt": uploaded["created_at"],
    }


def delete_image(workspace: Path, url: str) -> dict[str, object]:
    if not url.startswith("https://"):
        raise QiniuError("只能删除 HTTPS 云端图片。")
    root = workspace.resolve()
    for markdown_path in root.rglob("*.md"):
        if markdown_path.is_file() and url in markdown_path.read_text(
            encoding="utf-8", errors="ignore"
        ):
            return {"deleted": False, "status": "still_referenced"}

    config = load_qiniu_config()
    domain_prefix = f"{config.domain}/"
    if not url.startswith(domain_prefix):
        raise QiniuError("图片不属于当前七牛访问域名。")
    object_key = url[len(domain_prefix):].split("?", 1)[0]
    if not object_key or ".." in object_key or "<" in object_key:
        raise QiniuError("图片对象键无效。")

    management_url = os.environ.get(
        "STUDY_NOTES_QINIU_MANAGEMENT_URL", DEFAULT_MANAGEMENT_URL
    ).rstrip("/")
    request = Request(
        f"{management_url}/delete/{encoded_entry(config, object_key)}",
        data=b"",
        method="POST",
        headers={
            "Authorization": management_authorization(config, object_key),
            "Content-Type": "application/x-www-form-urlencoded",
        },
    )
    request_json(request, error_message="删除七牛图片失败。")
    return {"deleted": True, "status": "deleted"}
