# Fake GitHub for checks.flake-update-rehearsal (./flake-update.nix).
#
# Serves, at http://127.0.0.1:<port>, the GitHub Enterprise-style API that
# nixbot's script and the flake-update program derive from such an origin
# (/api/v3) and git's smart HTTP protocol for the bare repositories under
# <root> (through `git http-backend`). The App endpoints verify the JWT
# against the test key's public half and the test App id; every API request
# is logged as JSONL (method, path, body, auth class), and every
# authenticated git request with its user and token class.
#
# argv: port-file requests-log git-log root public-key app-id mode, where
# mode is "installed" or "uninstalled" (the installation lookup answers 404).
import base64
import http.server
import json
import os
import subprocess
import sys
import time

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding

port_file, log_path, git_log_path, root, public_key_path, app_id, mode = sys.argv[1:8]
with open(public_key_path, "rb") as f:
    public_key = serialization.load_pem_public_key(f.read())

OWNER = "acme"
REPO = "widget"
API = "/api/v3"
INSTALLATION = 777
MINTED = "minted-token"
opened = set()


def unb64(text):
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


def jwt_problem(auth):
    """None if `auth` carries a JWT the test App signed, else why not."""
    if not auth or not auth.startswith("Bearer "):
        return "no bearer token"
    parts = auth.removeprefix("Bearer ").split(".")
    if len(parts) != 3:
        return "not a JWT"
    try:
        header = json.loads(unb64(parts[0]))
        claims = json.loads(unb64(parts[1]))
    except ValueError:
        return "not a JWT"
    if header.get("alg") != "RS256":
        return "alg is not RS256"
    try:
        public_key.verify(
            unb64(parts[2]),
            f"{parts[0]}.{parts[1]}".encode(),
            padding.PKCS1v15(),
            hashes.SHA256(),
        )
    except Exception:
        return "signature does not verify against the test key"
    if str(claims.get("iss")) != app_id:
        return f"iss {claims.get('iss')!r}, expected {app_id!r}"
    if not claims.get("exp", 0) > time.time():
        return "expired"
    if claims["exp"] - claims.get("iat", 0) > 600:
        return "lives longer than ten minutes"
    return None


class Forge(http.server.BaseHTTPRequestHandler):
    def read_body(self):
        if self.headers.get("Transfer-Encoding", "").lower() == "chunked":
            data = b""
            while True:
                size = int(self.rfile.readline().strip(), 16)
                if size == 0:
                    self.rfile.readline()
                    return data
                data += self.rfile.read(size)
                self.rfile.readline()
        return self.rfile.read(int(self.headers.get("Content-Length") or 0))

    def reply(self, status, body=None, headers=()):
        payload = b"" if body is None else json.dumps(body).encode()
        self.send_response(status)
        for key, value in headers:
            self.send_header(key, value)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def record(self, auth, body):
        entry = {"method": self.command, "path": self.path, "auth": auth, "body": body}
        with open(log_path, "a") as log:
            print(json.dumps(entry, sort_keys=True, separators=(",", ":")), file=log)

    def handle_any(self):
        raw = self.read_body()
        path = self.path.split("?", 1)[0]
        if path.startswith(f"/{OWNER}/"):
            return self.git(raw)
        auth = self.headers.get("Authorization")
        body = json.loads(raw) if raw else None
        app_endpoints = {
            ("GET", f"{API}/repos/{OWNER}/{REPO}/installation"),
            ("POST", f"{API}/app/installations/{INSTALLATION}/access_tokens"),
        }
        if (self.command, path) in app_endpoints:
            problem = jwt_problem(auth)
            self.record("jwt" if problem is None else f"jwt-invalid: {problem}", body)
            if problem is not None:
                return self.reply(401, {"message": "A JSON web token could not be decoded"})
            if path.endswith("/installation"):
                if mode == "uninstalled":
                    return self.reply(404, {"message": "Not Found"})
                return self.reply(200, {"id": INSTALLATION, "app_id": int(app_id)})
            return self.reply(201, {"token": MINTED, "permissions": body.get("permissions")})
        self.record("minted" if auth == f"Bearer {MINTED}" else auth, body)
        if (self.command, path) == ("POST", f"{API}/repos/{OWNER}/{REPO}/pulls"):
            if body["head"] in opened:
                return self.reply(422, {
                    "message": "Validation Failed",
                    "errors": [{"message": f"A pull request already exists for {OWNER}:{body['head']}."}],
                })
            opened.add(body["head"])
            return self.reply(201, {"number": len(opened)})
        if (self.command, path) == ("DELETE", f"{API}/installation/token"):
            return self.reply(204)
        return self.reply(404, {"message": "Not Found"})

    def git(self, raw):
        auth = self.headers.get("Authorization")
        if not auth or not auth.startswith("Basic "):
            return self.reply(401, headers=[("WWW-Authenticate", 'Basic realm="forge"')])
        user, _, password = base64.b64decode(auth.removeprefix("Basic ")).decode().partition(":")
        path, _, query = self.path.partition("?")
        with open(git_log_path, "a") as log:
            entry = {
                "request": f"{self.command} {path.rsplit('/', 1)[-1]}?{query}",
                "user": user,
                "token": "minted" if password == MINTED else password,
            }
            print(json.dumps(entry, sort_keys=True, separators=(",", ":")), file=log)
        env = {
            "PATH": os.environ["PATH"],
            "GIT_PROJECT_ROOT": root,
            "GIT_HTTP_EXPORT_ALL": "1",
            "PATH_INFO": path,
            "QUERY_STRING": query,
            "REQUEST_METHOD": self.command,
            "CONTENT_TYPE": self.headers.get("Content-Type", ""),
            "CONTENT_LENGTH": str(len(raw)),
            "REMOTE_USER": user,
            "REMOTE_ADDR": "127.0.0.1",
        }
        if self.headers.get("Content-Encoding"):
            env["HTTP_CONTENT_ENCODING"] = self.headers["Content-Encoding"]
        if self.headers.get("Git-Protocol"):
            env["GIT_PROTOCOL"] = self.headers["Git-Protocol"]
        out = subprocess.run(
            ["git", "http-backend"], input=raw, env=env, capture_output=True, check=True
        ).stdout
        separator = b"\r\n\r\n" if b"\r\n\r\n" in out else b"\n\n"
        head, _, payload = out.partition(separator)
        status, headers = 200, []
        for line in head.decode().splitlines():
            key, _, value = line.partition(":")
            if key.lower() == "status":
                status = int(value.split()[0])
            else:
                headers.append((key, value.strip()))
        self.send_response(status)
        for key, value in headers:
            self.send_header(key, value)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    do_GET = do_POST = do_DELETE = handle_any

    def log_message(self, *args):
        pass


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Forge)
with open(port_file + ".tmp", "w") as f:
    f.write(str(server.server_port))
os.rename(port_file + ".tmp", port_file)
server.serve_forever()
