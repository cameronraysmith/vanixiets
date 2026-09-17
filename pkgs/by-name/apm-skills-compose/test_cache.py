"""Run with the selected APM package's Python environment; no acquisition allowed."""

import hashlib
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from apm_cli.cache.git_cache import GitCache


class OfflineCheckoutTest(unittest.TestCase):
    def test_seeded_checkout_is_reused_without_acquisition(self):
        url = "https://github.com/example/offline-fixture"
        sha = "a" * 40
        shard = hashlib.sha256(url.encode()).hexdigest()[:16]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            checkout = root / "git" / "checkouts_v1" / shard / sha / "full"
            (checkout / ".git").mkdir(parents=True)
            (checkout / ".git" / "HEAD").write_text(sha + "\n")
            (checkout / "SKILL.md").write_text("fixture\n")
            cache = GitCache(root)
            with patch.object(
                subprocess, "run", side_effect=AssertionError("acquisition forbidden")
            ):
                with self.assertRaisesRegex(AssertionError, "acquisition forbidden"):
                    cache.get_checkout(url, sha)
                (checkout / ".git" / "config").write_text(
                    "[core]\n\tautocrlf = false\n"
                )
                self.assertEqual(cache.get_checkout(url, sha), checkout)
                self.assertEqual((checkout / "SKILL.md").read_text(), "fixture\n")


if __name__ == "__main__":
    unittest.main()
