"""Local negative controls for the observation probe; no account or host actions."""
import importlib.util
import io
import json
import pathlib
import types
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("worker_live", pathlib.Path(__file__).with_name("live.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class ProbeChecks(unittest.TestCase):
    def test_private_non_admin_prepared_account(self):
        workers = {"cameron": {"user": "fixture", "home": "/fixture"}}
        with (
            patch.object(probe, "account", return_value={"uid": 2000, "gid": 2000, "home": "/fixture"}),
            patch.object(probe.os, "getgrouplist", return_value=[2000]),
            patch.object(probe.grp, "getgrgid", return_value=types.SimpleNamespace(gr_name="fixture")),
            patch.object(probe.pathlib.Path, "is_dir", return_value=True),
            patch.object(probe.os, "stat", return_value=types.SimpleNamespace(st_mode=0o40700, st_uid=2000)),
        ):
            result = probe.observe("magnetite", workers, False)["cameron"]
            self.assertTrue(result["homePrivate"])
            self.assertTrue(result["nonAdmin"])
            with patch.object(probe.grp, "getgrgid", return_value=types.SimpleNamespace(gr_name="wheel")):
                self.assertFalse(probe.observe("magnetite", workers, False)["cameron"]["nonAdmin"])
            with patch.object(probe.os, "stat", return_value=types.SimpleNamespace(st_mode=0o40755, st_uid=2000)):
                self.assertFalse(probe.observe("magnetite", workers, False)["cameron"]["homePrivate"])

    def test_account_launcher_uses_argv_and_cleared_environment(self):
        with patch.object(probe, "run") as run, patch.object(probe.os, "uname", return_value=types.SimpleNamespace(sysname="Linux")):
            probe.as_user("fixture", {"HOME": "/fixture", "PATH": "/fixture/bin"}, ["gh", "api", "user"])
            self.assertEqual(run.call_args.args[0], ["runuser", "-u", "fixture", "--", "env", "-i", "HOME=/fixture", "PATH=/fixture/bin", "gh", "api", "user"])

    def test_failed_runtime_probe_cannot_report_success(self):
        row = {"account": {"uid": 2000, "home": "/fixture"}, "configuredHome": "/fixture", "homePrivate": True, "nonAdmin": True, "active": False}
        with (
            patch("sys.argv", ["live.py", "running", "magnetite", '{"cameron":{"user":"fixture"}}']),
            patch.object(probe, "observe", return_value={"cameron": row}),
            redirect_stdout(io.StringIO()) as output,
            self.assertRaises(SystemExit) as stopped,
        ):
            probe.main()
        self.assertEqual(stopped.exception.code, 1)
        self.assertFalse(json.loads(output.getvalue())["passed"])


if __name__ == "__main__":
    unittest.main()
