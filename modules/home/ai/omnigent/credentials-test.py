"""In-process tests of the worker credential consumer and its delivery helpers.

Every external effect (subprocess.run, os.execve, urllib) is patched, so the
pure selection logic is exercised without spawning provider tools.
Usage: python3 credentials-test.py CREDENTIALS DELIVERY DELIVERY_FIXTURES KEYCHAIN KEYCHAIN_FIXTURES
"""

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SOURCES = dict(
    zip(
        ("credentials", "delivery", "delivery_fixtures", "keychain", "keychain_fixtures"),
        sys.argv[1:6],
    )
)
del sys.argv[1:6]


def load(name: str):
    spec = importlib.util.spec_from_file_location(name, SOURCES[name])
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


credentials = load("credentials")
SIGNING_PUBLIC = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdamAGCsQq31Uv+08lkBzoO4XLz2qYjJa8CGmj3B1Ea"


def private_file(path: pathlib.Path, value: str, mode: int = 0o400) -> pathlib.Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        path.chmod(0o600)
    path.write_text(value)
    path.chmod(mode)
    return path


class Fixture(unittest.TestCase):
    def setUp(self) -> None:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = pathlib.Path(directory.name).resolve()
        self.home = self.root / "home"
        self.home.mkdir(mode=0o700)
        self.work = self.root / "work" / "project"
        self.work.mkdir(parents=True)
        secrets = self.root / "secrets"
        self.tokens = {
            "first": "first-token-sentinel",
            "second": "second-token-sentinel",
            "linear": "linear-key-sentinel",
            "claude": "claude-token-sentinel",
        }
        paths = {
            name: private_file(secrets / name, value) for name, value in self.tokens.items()
        }
        linear = {
            "path": str(paths["linear"]),
            "workspace": str(private_file(secrets / "workspace", "fixture")),
            "workspaceId": str(private_file(secrets / "workspace-id", "workspace-id")),
            "viewerEmail": str(private_file(secrets / "viewer", "viewer@example.invalid")),
        }
        self.linear_credentials = private_file(
            self.home / ".config/linear/credentials.toml",
            'default = "fixture"\nfixture = "linear-key-sentinel"\n',
        )
        signing = private_file(secrets / "signing", "synthetic private key")
        self.policy = {
            "home": str(self.home),
            "serverUrl": "https://fixture.invalid",
            "defaultOwner": "first",
            "expected": {
                "gitEmail": "fixture@example.invalid",
                "omnigentEmail": "fixture@example.invalid",
                "signingPublicKey": SIGNING_PUBLIC,
            },
            "signingKey": str(signing),
            "githubTokens": {
                owner: {"path": str(paths[owner]), "expectedLogin": "fixture-human"}
                for owner in ("first", "second")
            },
            "claudeSetupToken": str(paths["claude"]),
            "linearCredentials": str(self.linear_credentials),
            "linearRendered": str(self.linear_credentials),
            "linearApiKeys": {"personal": linear},
            "requiredFiles": [
                str(paths["first"]),
                str(paths["second"]),
                str(paths["claude"]),
                str(signing),
                *linear.values(),
                str(self.linear_credentials),
            ],
            "executables": {
                "gh": "/synthetic/gh",
                "git": "/synthetic/git",
                "linear": "/synthetic/linear",
                "claude": "/synthetic/claude",
                "ssh-keygen": "/synthetic/ssh-keygen",
            },
        }
        environment = patch.dict(
            os.environ,
            {
                "PATH": os.environ.get("PATH", ""),
                "HOME": str(self.home),
                "XDG_CONFIG_HOME": str(self.home / ".config"),
            },
            clear=True,
        )
        environment.start()
        self.addCleanup(environment.stop)
        cwd = os.getcwd()
        os.chdir(self.work)
        self.addCleanup(os.chdir, cwd)
        self.origin = None
        self.git_root = str(self.work)
        runner = patch.object(credentials.subprocess, "run", side_effect=self.run_fake)
        self.run_mock = runner.start()
        self.addCleanup(runner.stop)

    # Fake for every subprocess the consumer spawns; providers answer from these fields.
    login = {"first": "fixture-human", "second": "fixture-human"}
    viewer = "viewer@example.invalid"
    organization = {"id": "workspace-id", "urlKey": "fixture"}
    signer = SIGNING_PUBLIC + " synthetic"
    signer_status = 0
    keychain_status = 44

    def run_fake(self, arguments, **kwargs):
        executables = self.policy["executables"]
        if arguments[:3] == [executables["git"], "remote", "get-url"]:
            if self.origin is None:
                return subprocess.CompletedProcess(arguments, 2, b"", b"")
            return subprocess.CompletedProcess(arguments, 0, self.origin.encode() + b"\n", b"")
        if arguments[:2] == ["git", "rev-parse"]:
            return subprocess.CompletedProcess(arguments, 0, self.git_root.encode() + b"\n", b"")
        if arguments[0] == executables["gh"]:
            owner = next(
                owner
                for owner, value in self.tokens.items()
                if value == kwargs["env"]["GH_TOKEN"]
            )
            body = json.dumps({"login": self.login[owner]})
            return subprocess.CompletedProcess(arguments, 0, body.encode(), b"")
        if arguments[0] == executables["linear"]:
            assert kwargs["env"]["LINEAR_IGNORE_ENV_FILE"] == "1"
            body = json.dumps(
                {"data": {"viewer": {"email": self.viewer}, "organization": self.organization}}
            )
            return subprocess.CompletedProcess(arguments, 0, body.encode(), b"")
        if arguments[0] == executables["ssh-keygen"]:
            return subprocess.CompletedProcess(
                arguments, self.signer_status, self.signer.encode(), b""
            )
        if arguments[:2] == ["/usr/bin/security", "find-generic-password"]:
            return subprocess.CompletedProcess(arguments, self.keychain_status)
        raise AssertionError(f"unexpected subprocess {arguments}")

    def rejects(self, operation, *errors):
        """The operation fails closed and its error text never carries a credential."""
        with self.assertRaises(errors or (credentials.CredentialError,)) as raised:
            operation()
        for value in self.tokens.values():
            self.assertNotIn(value, str(raised.exception))
        return raised.exception


class Material(Fixture):
    def test_owner_mode_and_content(self) -> None:
        path = self.policy["githubTokens"]["first"]["path"]
        self.assertEqual(credentials.token(path), "first-token-sentinel")
        self.rejects(lambda: credentials.material(path, os.getuid() + 1))
        pathlib.Path(path).chmod(0o644)
        self.rejects(lambda: credentials.token(path))
        private_file(pathlib.Path(path), "  \n")
        self.rejects(lambda: credentials.token(path))
        private_file(pathlib.Path(path), "two tokens")
        self.rejects(lambda: credentials.token(path))

    def test_ready_requires_every_file(self) -> None:
        credentials.ready(self.policy)
        os.unlink(self.policy["linearRendered"])
        self.rejects(lambda: credentials.ready(self.policy), OSError)


class GithubOwner(Fixture):
    def owner(self, arguments=(), **environment):
        os.environ.update(environment)
        return credentials.github_owner(self.policy, list(arguments))

    def test_environment_precedes_origin(self) -> None:
        self.origin = "https://github.com/second/repo.git"
        self.assertEqual(self.owner(OMNIGENT_GH_OWNER="first"), "first")
        self.run_mock.assert_not_called()

    def test_origin_precedes_default(self) -> None:
        for origin in (
            "https://github.com/second/repo.git",
            "git@github.com:second/repo.git",
            "ssh://git@github.com/second/repo.git",
            "https://github.com/second/repo/",
        ):
            self.origin = origin
            self.assertEqual(self.owner(), "second", origin)

    def test_unknown_origin_owner_never_falls_back(self) -> None:
        self.origin = "https://github.com/unknown/repo.git"
        error = self.rejects(self.owner)
        self.assertIn("OMNIGENT_GH_OWNER", str(error))

    def test_default_without_origin(self) -> None:
        self.assertEqual(self.owner(), "first")
        self.policy["defaultOwner"] = None
        self.rejects(self.owner)

    def test_undeclared_selection(self) -> None:
        for owner in ("unknown", ""):
            self.rejects(lambda: self.owner(OMNIGENT_GH_OWNER=owner))

    def test_repository_selectors_must_match(self) -> None:
        for arguments in (
            ["pr", "view", "-R", "first/repo"],
            ["pr", "view", "--repo=first/repo"],
            ["pr", "view", "-Rfirst/repo"],
            ["pr", "view", "-R=first/repo"],
            ["pr", "view", "--repo", "https://github.com/first/repo"],
            ["pr", "view", "-R"],
        ):
            self.rejects(lambda: self.owner(arguments, OMNIGENT_GH_OWNER="second"))
        for arguments in (
            ["pr", "create", "-R", "second/repo"],
            ["pr", "view", "--repo", "github.com/second/repo"],
            ["repo", "view", "unknown/repo"],
            ["api", "repos/unknown/repo"],
            ["api", "user", "--", "-R", "first/repo"],
        ):
            self.assertEqual(self.owner(arguments, OMNIGENT_GH_OWNER="second"), "second")

    def test_gh_repo_environment(self) -> None:
        self.rejects(lambda: self.owner(OMNIGENT_GH_OWNER="second", GH_REPO="first/repo"))
        self.assertEqual(
            self.owner(OMNIGENT_GH_OWNER="second", GH_REPO="github.com/second/repo"), "second"
        )


class GithubEnvironment(Fixture):
    def test_selected_token_only(self) -> None:
        environment = credentials.github_environment(self.policy, "second")
        self.assertEqual(environment["GH_TOKEN"], "second-token-sentinel")
        os.environ["GH_TOKEN"] = "second-token-sentinel"
        credentials.github_environment(self.policy, "second")
        for name in ("GH_TOKEN", "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN"):
            with patch.dict(os.environ, {name: "unapproved-ambient-grant"}):
                self.rejects(lambda: credentials.github_environment(self.policy, "second"))
        self.rejects(lambda: credentials.github_environment(self.policy, "unknown"))


class GithubCredentialHelper(Fixture):
    def helper(self, arguments, request: str) -> str:
        output = io.StringIO()
        with patch.object(credentials.sys, "stdin", io.StringIO(request)):
            with contextlib.redirect_stdout(output):
                credentials.github_credential(self.policy, arguments)
        return output.getvalue()

    def test_owner_from_request_path(self) -> None:
        os.environ["OMNIGENT_GH_OWNER"] = "unknown"
        for owner in ("first", "second"):
            self.assertEqual(
                self.helper(["get"], f"protocol=https\nhost=github.com\npath={owner}/repo.git\n\n"),
                f"username=x-access-token\npassword={owner}-token-sentinel\n\n",
            )

    def test_rejected_requests_print_nothing(self) -> None:
        for request in (
            "protocol=https\nhost=github.com\npath=unknown/repo.git",
            "protocol=https\nhost=github.com",
            "protocol=https\nhost=github.com\npath=first",
            "protocol=https\nhost=other.invalid\npath=first/repo.git",
            "protocol=http\nhost=github.com\npath=first/repo.git",
        ):
            self.assertEqual(self.helper(["get"], request + "\n\n"), "", request)
        for operation in ("store", "erase"):
            self.assertEqual(
                self.helper([operation], "protocol=https\nhost=github.com\npath=first/r\n\n"), ""
            )


class LinearWorkspace(Fixture):
    def test_exactly_one_declared_workspace(self) -> None:
        for arguments in (
            ["--workspace", "fixture", "api"],
            ["-w", "fixture", "api"],
            ["--workspace=fixture", "api"],
        ):
            self.assertEqual(credentials.linear_workspace(arguments, self.policy), "fixture")
        for arguments in (
            ["api"],
            ["--workspace", "personal", "api"],
            ["--workspace", "other", "api"],
            ["--workspace", "fixture", "-w", "fixture"],
            ["api", "--workspace"],
        ):
            self.rejects(lambda: credentials.linear_workspace(arguments, self.policy))
        os.unlink(self.policy["linearApiKeys"]["personal"]["workspace"])
        self.rejects(
            lambda: credentials.linear_workspace(["--workspace", "fixture"], self.policy), OSError
        )


class LinearEnvironment(Fixture):
    def environment(self):
        return credentials.linear_environment(self.policy)

    def test_accepts_delivered_credentials(self) -> None:
        os.environ["LINEAR_GRAPHQL_ENDPOINT"] = "https://unapproved.invalid/graphql"
        environment = self.environment()
        self.assertEqual(environment["LINEAR_IGNORE_ENV_FILE"], "1")
        self.assertNotIn("LINEAR_GRAPHQL_ENDPOINT", environment)
        private_file(self.work / "linear.toml", 'workspace = "fixture"\n')
        self.environment()

    def test_competing_environment(self) -> None:
        for name in ("LINEAR_API_KEY", "LINEAR_WORKSPACE", "LINEAR_CONFIG"):
            with patch.dict(os.environ, {name: "linear-key-sentinel"}):
                self.rejects(self.environment)

    def test_foreign_homes(self) -> None:
        with patch.dict(os.environ, {"HOME": str(self.root)}):
            self.rejects(self.environment)
        with patch.dict(os.environ, {"XDG_CONFIG_HOME": str(self.root / ".config")}):
            self.rejects(self.environment)

    def test_competing_configuration(self) -> None:
        external = self.root / "external"
        self.git_root = str(external)
        for path in (
            self.home / ".config/linear/linear.toml",
            self.work / "linear.toml",
            self.work / ".linear.toml",
            self.work / ".config/linear.toml",
            self.work.parent / ".linear.toml",
            external / "linear.toml",
            external / ".config/linear.toml",
        ):
            private_file(path, 'api_key = "external-grant"\n')
            self.rejects(self.environment)
            path.unlink()
        self.environment()

    def test_rendered_template_must_match_grants(self) -> None:
        template = self.linear_credentials.read_text()
        for invalid in (
            'default = "fixture"',
            'default = "fixture"\nfixture = ""',
            'default = "fixture"\nfixture = "wrong-grant"',
            template + '\nother = "competing-workspace"',
            template + '\nfixture = "duplicate-workspace"',
            'default = "fixture"\nworkspaces = ["fixture"]',
            'default = "other"\nfixture = "linear-key-sentinel"',
        ):
            private_file(self.linear_credentials, invalid)
            self.rejects(self.environment, credentials.CredentialError, ValueError)
        private_file(self.linear_credentials, template, 0o644)
        self.rejects(self.environment)

    def test_duplicate_workspace_grants(self) -> None:
        grants = self.policy["linearApiKeys"]
        grants["work"] = dict(grants["personal"])
        self.rejects(self.environment)


class ClaudeEnvironment(Fixture):
    def environment(self, arguments=()):
        return credentials.claude_environment(self.policy, list(arguments))

    def test_setup_token_only(self) -> None:
        with patch.object(credentials.sys, "platform", "linux"):
            environment = self.environment(["--settings", "{}"])
        self.assertEqual(environment["CLAUDE_CODE_OAUTH_TOKEN"], "claude-token-sentinel")
        self.assertNotIn("GH_TOKEN", environment)

    def test_competing_sources(self) -> None:
        with patch.object(credentials.sys, "platform", "linux"):
            for name in ("ANTHROPIC_API_KEY", "CLAUDE_CODE_OAUTH_TOKEN", "CLAUDE_CONFIG_DIR"):
                with patch.dict(os.environ, {name: "claude-token-sentinel"}):
                    self.rejects(self.environment)
            self.rejects(lambda: self.environment(["--settings", '{"apiKeyHelper":"false"}']))
            settings = self.root / "inline-settings.json"
            settings.write_text('{"env": {"ANTHROPIC_BASE_URL": "https://other.invalid"}}')
            self.rejects(lambda: self.environment([f"--settings={settings}"]))
            self.rejects(lambda: self.environment(["--settings"]))
            project = self.work / ".claude/settings.local.json"
            private_file(project, '{"apiKeyHelper": "false"}', 0o600)
            self.rejects(self.environment)
            project.unlink()
            oauth = private_file(self.home / ".claude/.credentials.json", "{}", 0o600)
            self.rejects(self.environment)
            oauth.unlink()
            self.environment()

    def test_darwin_keychain_must_be_absent(self) -> None:
        with patch.object(credentials.sys, "platform", "darwin"):
            self.environment()
            self.keychain_status = 0
            self.rejects(self.environment)


class Verify(Fixture):
    def setUp(self) -> None:
        super().setUp()
        private_file(
            self.home / ".omnigent/auth_tokens.json",
            json.dumps({"https://fixture.invalid": {"token": "omnigent-bearer"}}),
            0o600,
        )
        self.identity = "fixture@example.invalid"
        fixture = self

        class Opener:
            def open(self, request, timeout):
                assert request.full_url == "https://fixture.invalid/v1/me"
                assert request.get_header("Authorization") == "Bearer omnigent-bearer"
                return io.BytesIO(json.dumps({"user_id": fixture.identity}).encode())

        opener = patch.object(
            credentials.urllib.request, "build_opener", side_effect=lambda *_: Opener()
        )
        opener.start()
        self.addCleanup(opener.stop)

    def verify(self):
        with contextlib.redirect_stdout(io.StringIO()):
            credentials.verify(self.policy)

    def test_matching_identities(self) -> None:
        self.verify()

    def test_each_identity_mismatch_fails(self) -> None:
        mutations = (
            ("login", {"first": "other-person", "second": "fixture-human"}),
            ("login", {"first": "fixture-human", "second": "other-person"}),
            ("viewer", "other@example.invalid"),
            ("organization", {"id": "other-workspace", "urlKey": "fixture"}),
            ("organization", {"id": "workspace-id", "urlKey": "other"}),
            ("signer", "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOtherOtherOtherOtherOtherOtherOtherOtherOth"),
            ("signer_status", 1),
            ("identity", "other@example.invalid"),
        )
        for field, value in mutations:
            original = getattr(self, field)
            setattr(self, field, value)
            self.rejects(self.verify)
            setattr(self, field, original)
        self.verify()

    def test_linear_metadata_mismatch_fails(self) -> None:
        for field in ("workspaceId", "viewerEmail"):
            path = pathlib.Path(self.policy["linearApiKeys"]["personal"][field])
            original = path.read_text()
            private_file(path, "other-synthetic-identity")
            self.rejects(self.verify)
            private_file(path, original)

    def test_unsafe_omnigent_token_file(self) -> None:
        (self.home / ".omnigent/auth_tokens.json").chmod(0o644)
        self.rejects(self.verify)


class Execute(Fixture):
    def execute(self, mode, arguments):
        with patch.object(credentials.os, "execve") as execve:
            credentials.execute(self.policy, mode, arguments)
        return execve.call_args.args

    def test_gh_receives_only_selected_token(self) -> None:
        os.environ["OMNIGENT_GH_OWNER"] = "second"
        executable, argv, environment = self.execute("gh", ["api", "user"])
        self.assertEqual((executable, argv), ("/synthetic/gh", ["/synthetic/gh", "api", "user"]))
        self.assertEqual(environment["GH_TOKEN"], "second-token-sentinel")

    def test_linear_requires_workspace_and_forbids_auth(self) -> None:
        _, _, environment = self.execute("linear", ["--workspace", "fixture", "api", "q"])
        self.assertEqual(environment["LINEAR_IGNORE_ENV_FILE"], "1")
        self.rejects(lambda: self.execute("linear", ["--workspace", "fixture", "auth"]))
        self.rejects(lambda: self.execute("linear", ["api", "q"]))

    def test_claude_and_unknown_modes(self) -> None:
        with patch.object(credentials.sys, "platform", "linux"):
            _, _, environment = self.execute("claude", [])
        self.assertEqual(environment["CLAUDE_CODE_OAUTH_TOKEN"], "claude-token-sentinel")
        self.rejects(lambda: self.execute("ssh", []))


class Main(Fixture):
    def main(self, *arguments):
        policy = self.root / "policy.json"
        policy.write_text(json.dumps(self.policy))
        stderr, stdout = io.StringIO(), io.StringIO()
        with (
            patch.object(credentials.sys, "argv", ["credentials.py", str(policy), *arguments]),
            contextlib.redirect_stderr(stderr),
            contextlib.redirect_stdout(stdout),
        ):
            try:
                credentials.main()
                status = 0
            except SystemExit as exit:
                status = exit.code
        for value in self.tokens.values():
            self.assertNotIn(value, stderr.getvalue())
        return status, stdout.getvalue(), stderr.getvalue()

    def test_failures_exit_without_disclosure(self) -> None:
        self.assertEqual(self.main("ready")[0], 0)
        os.environ["OMNIGENT_GH_OWNER"] = "unknown"
        self.assertEqual(self.main("gh", "api", "user")[0:3:2], (1, "select a declared OMNIGENT_GH_OWNER\n"))
        os.unlink(self.policy["githubTokens"]["first"]["path"])
        self.assertEqual(self.main("ready")[0:3:2], (1, "worker credential operation failed\n"))

    def test_git_credential_dispatch(self) -> None:
        with patch.object(
            credentials.sys, "stdin", io.StringIO("protocol=https\nhost=github.com\npath=second/r\n\n")
        ):
            status, stdout, _ = self.main("gh", "auth", "git-credential", "get")
        self.assertEqual(status, 0)
        self.assertIn("password=second-token-sentinel\n", stdout)


class DeliveryHelpers(unittest.TestCase):
    def test_delivery_receipts(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            load("delivery_fixtures").exercise(SOURCES["delivery"], pathlib.Path(directory))

    def test_keychain(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            load("keychain_fixtures").exercise(SOURCES["keychain"], pathlib.Path(directory))


if __name__ == "__main__":
    unittest.main(verbosity=2)
