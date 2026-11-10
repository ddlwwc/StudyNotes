from __future__ import annotations

import hashlib
import tempfile
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


if __name__ == "__main__":
    unittest.main()
