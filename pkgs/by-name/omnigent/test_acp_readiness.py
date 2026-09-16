import unittest
from unittest.mock import patch

from omnigent.harness_plugins import harness_catalog
from omnigent.onboarding import acp_auth, harness_readiness


class AcpReadinessTest(unittest.TestCase):
    def setUp(self):
        self.enterContext(
            patch("subprocess.Popen", side_effect=AssertionError("CLI probe"))
        )
        self.enterContext(
            patch("socket.socket.connect", side_effect=AssertionError("network"))
        )
        self.config = {}
        self.enterContext(patch.object(acp_auth, "load_config", lambda: self.config))
        availability = harness_readiness._harness_availability
        self.enterContext(
            patch.object(
                harness_readiness,
                "_harness_availability",
                side_effect=lambda harness: (
                    availability(harness)
                    if harness == "acp" or harness.startswith("acp:")
                    else "binary-missing"
                ),
            )
        )

    def test_registered_agents_have_exact_catalog_readiness_keys(self):
        self.config = {
            "acp": {
                "agents": [
                    {"name": "Atomic", "command": "bunx pi-acp@0.0.33"},
                    {"name": "OMP", "command": "omp acp"},
                ]
            }
        }
        catalog_ids = {
            row["id"] for row in harness_catalog() if row["id"].startswith("acp:")
        }
        self.assertEqual(catalog_ids, {"acp:atomic", "acp:omp"})
        configured = harness_readiness.configured_harness_map()
        for harness in catalog_ids:
            self.assertIs(configured.get(harness), True, harness)
        self.assertNotIn("acp:missing", configured)
        self.assertIs(configured["acp"], True)

    def test_unregistered_slug_does_not_inherit_generic_readiness(self):
        self.config = {"acp": {"agents": [{"name": "OMP", "command": "omp acp"}]}}
        self.assertTrue(harness_readiness.harness_is_configured("acp:omp"))
        self.assertFalse(harness_readiness.harness_is_configured("acp:atomic"))
        self.assertFalse(harness_readiness.harness_is_configured("acp:"))
        self.assertFalse(harness_readiness.harness_is_configured("acp:OMP"))

    def test_absent_and_malformed_registrations_are_not_advertised(self):
        for config in (
            {},
            {"acp": None},
            {"acp": {"agents": "invalid"}},
            {"acp": {"agents": [None, {"name": "Atomic"}]}},
            {
                "acp": {
                    "agents": [
                        {"name": "OMP", "command": "omp acp", "omnigent_mcp": "invalid"}
                    ]
                }
            },
        ):
            with self.subTest(config=config):
                self.config = config
                configured = harness_readiness.configured_harness_map()
                self.assertIs(configured["acp"], False)
                self.assertFalse(any(key.startswith("acp:") for key in configured))
                self.assertFalse(
                    any(row["id"].startswith("acp:") for row in harness_catalog())
                )
                self.assertFalse(harness_readiness.harness_is_configured("acp:atomic"))
        with patch.object(acp_auth, "load_config", side_effect=ValueError("malformed")):
            self.assertIs(harness_readiness.configured_harness_map()["acp"], False)
            self.assertFalse(harness_readiness.harness_is_configured("acp:omp"))

    def test_native_aliases_and_sdk_launch_behavior_are_unchanged(self):
        configured = harness_readiness.configured_harness_map()
        self.assertEqual(configured["codex"], "binary-missing")
        self.assertEqual(configured["codex-native"], configured["codex"])
        self.assertEqual(configured["native-pi"], configured["pi-native"])
        for harness in (
            "claude",
            "claude_sdk",
            "openai-agents",
            "agents_sdk",
            "unknown",
        ):
            self.assertTrue(harness_readiness.harness_is_configured(harness))
        for state, expected in (
            (True, True),
            ("binary-missing", False),
            ("version-too-low", False),
        ):
            with patch.object(
                harness_readiness, "_binary_availability_reason", return_value=state
            ):
                for harness in ("kiro-native", "native-kiro"):
                    self.assertIs(
                        harness_readiness.harness_is_configured(harness), expected
                    )


if __name__ == "__main__":
    unittest.main()
