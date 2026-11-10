from __future__ import annotations

import hashlib
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch

import documents


class DocumentCommitTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.file_path = Path(self.temporary_directory.name) / "note.md"
        self.file_path.write_text("# 旧标题\n\n旧正文。\n", encoding="utf-8")

    def test_sidecar_write_failure_restores_markdown_and_block_metadata(self) -> None:
        initial_content = self.file_path.read_text(encoding="utf-8")
        initial_blocks = [
            {
                "id": "stable-block-id",
                "type": "paragraph",
                "props": {"textAlignment": "left"},
                "children": [],
            }
        ]
        documents.save_document(
            self.file_path,
            initial_content,
            initial_blocks,
            hashlib.sha256(initial_content.encode("utf-8")).hexdigest(),
        )
        previous = documents.load_document(self.file_path)
        self.assertEqual(previous["blocks"], initial_blocks)

        real_atomic_write = documents.atomic_write_text
        failed_once = False

        def fail_sidecar_once(file_path: Path, content: str) -> None:
            nonlocal failed_once
            if file_path.name.endswith(".note.json") and not failed_once:
                failed_once = True
                raise OSError("injected sidecar failure")
            real_atomic_write(file_path, content)

        with patch(
            "documents.atomic_write_text",
            side_effect=fail_sidecar_once,
        ):
            with self.assertRaises(OSError):
                documents.save_document(
                    self.file_path,
                    "# 新标题\n\n新正文。\n",
                    [
                        {
                            "id": "new-block-id",
                            "type": "paragraph",
                            "props": {},
                            "children": [],
                        }
                    ],
                    str(previous["revision"]),
                )

        recovered = documents.load_document(self.file_path)
        self.assertEqual(recovered["content"], initial_content)
        self.assertEqual(recovered["blocks"][0]["id"], "stable-block-id")
        self.assertEqual(recovered["sidecarStatus"], "valid")

    def test_reader_waits_for_an_inflight_pair_commit(self) -> None:
        initial_content = self.file_path.read_text(encoding="utf-8")
        initial_blocks = [
            {
                "id": "stable-block-id",
                "type": "paragraph",
                "props": {},
                "children": [],
            }
        ]
        initial_document = documents.save_document(
            self.file_path,
            initial_content,
            initial_blocks,
            hashlib.sha256(initial_content.encode("utf-8")).hexdigest(),
        )

        sidecar_started = threading.Event()
        release_sidecar = threading.Event()
        reader_recovery_started = threading.Event()
        reader_document: dict[str, object] = {}
        errors: list[BaseException] = []
        sidecar_path = documents.sidecar_path_for(self.file_path)
        real_atomic_write = documents.atomic_write_text
        real_recover = documents.recover_interrupted_commit

        def pause_sidecar(file_path: Path, content: str) -> None:
            if (
                file_path == sidecar_path
                and threading.current_thread().name == "document-writer"
            ):
                sidecar_started.set()
                release_sidecar.wait(5)
            real_atomic_write(file_path, content)

        def track_reader_recovery(file_path: Path) -> None:
            if threading.current_thread().name == "document-reader":
                reader_recovery_started.set()
            real_recover(file_path)

        def write_document() -> None:
            try:
                documents.save_document(
                    self.file_path,
                    "# 新标题\n\n新正文。\n",
                    [
                        {
                            "id": "new-block-id",
                            "type": "paragraph",
                            "props": {},
                            "children": [],
                        }
                    ],
                    str(initial_document["revision"]),
                )
            except BaseException as error:
                errors.append(error)

        def read_document() -> None:
            try:
                reader_document.update(documents.load_document(self.file_path))
            except BaseException as error:
                errors.append(error)

        with (
            patch("documents.atomic_write_text", side_effect=pause_sidecar),
            patch(
                "documents.recover_interrupted_commit",
                side_effect=track_reader_recovery,
            ),
        ):
            writer = threading.Thread(
                name="document-writer",
                target=write_document,
            )
            writer.start()
            self.assertTrue(sidecar_started.wait(2))

            reader = threading.Thread(
                name="document-reader",
                target=read_document,
            )
            reader.start()
            try:
                self.assertFalse(
                    reader_recovery_started.wait(0.5),
                    "reader must wait while a normal pair commit is in flight",
                )
            finally:
                release_sidecar.set()

            writer.join(5)
            reader.join(5)

        self.assertFalse(writer.is_alive())
        self.assertFalse(reader.is_alive())
        self.assertEqual(errors, [])
        self.assertEqual(reader_document["content"], "# 新标题\n\n新正文。\n")
        self.assertEqual(reader_document["blocks"][0]["id"], "new-block-id")
        self.assertEqual(reader_document["sidecarStatus"], "valid")


if __name__ == "__main__":
    unittest.main()
