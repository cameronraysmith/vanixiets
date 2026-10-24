{
  lib,
  fetchFromGitHub,
  fetchPypi,
  python3Packages,
  runCommand,
}:
let
  version = "0.19.1";
  # omnigent 0.19.1 caps mcp<2 and imports
  # mcp.client.streamable_http.streamablehttp_client and
  # mcp.shared.exceptions.McpError, both absent from nixpkgs' mcp 2.2.0. Pin
  # mcp 1.29.0, nixpkgs' previous release, in omnigent's package set only, so
  # openai-agents and claude-agent-sdk resolve the same mcp. Remove once an
  # omnigent release accepts mcp 2.
  python = python3Packages.python.override {
    self = python;
    packageOverrides = pyFinal: pyPrev: {
      mcp = pyPrev.mcp.overridePythonAttrs (_: {
        version = "1.29.0";
        src = fetchFromGitHub {
          owner = "modelcontextprotocol";
          repo = "python-sdk";
          tag = "v1.29.0";
          hash = "sha256-lRlj5RT/R5zrYL5XpdQR2l9t99G94WTsubN0gSQekMc=";
        };
        pythonRelaxDeps = [ "pydantic-settings" ];
        dependencies = [
          pyFinal.anyio
          pyFinal.httpx
          pyFinal.httpx-sse
          pyFinal.jsonschema
          pyFinal.pydantic
          pyFinal.pydantic-settings
          pyFinal.pyjwt
          pyFinal.python-multipart
          pyFinal.sse-starlette
          pyFinal.starlette
          pyFinal.uvicorn
        ];
        # The inherited check inputs, preCheck and disabledTests describe the
        # 2.2.0 suite; nixpkgs ran the 1.29.0 suite before the bump.
        doCheck = false;
      });
    };
  };
  py = python.pkgs;
  omnigent-client = py.callPackage ./omnigent-client.nix { inherit version; };
  omnigent-ui-sdk = py.callPackage ./omnigent-ui-sdk.nix {
    inherit version omnigent-client;
  };

  # nixpkgs master carries openai-agents 0.22.0, which needs openai>=3, while
  # master still ships openai 2.53; 0.20.0 is the newest release that accepts
  # openai<3. Every 0.18+ release caps websockets<17 below nixpkgs' 17.0.1 and
  # the nixpkgs recipe omits the websockets dependency. Remove this pin once
  # master carries nixpkgs b745875580cb and the openai 3.x bump
  # (NixOS/nixpkgs#564353).
  # https://pypi.org/pypi/openai-agents/0.20.0/json
  openai-agents = py.openai-agents.overridePythonAttrs (old: {
    version = "0.20.0";
    src = fetchPypi {
      pname = "openai_agents";
      version = "0.20.0";
      hash = "sha256-prN5VId4aKwjOHaifaseKkYcU+y9X89uGeLSdtPoSM0=";
    };
    dependencies = old.dependencies ++ [ py.websockets ];
    pythonRelaxDeps = [ "websockets" ];
  });
  omnigent = py.buildPythonPackage {
    pname = "omnigent";
    inherit version;
    format = "wheel";

    src = fetchPypi {
      pname = "omnigent";
      inherit version;
      format = "wheel";
      python = "py3";
      dist = "py3";
      platform = "any";
      hash = "sha256-5i1X9B3TS8e+9qdnkZcIbnDTmadMGmE2p/J8NEQT5w0=";
    };

    # openai<2.45 is upstream's transitive cap on openai-agents, not on omnigent's
    # own openai surface; upstream holds it only because its websockets<15 macOS
    # pin blocks openai-agents 0.18.2. We already relax websockets, so the cap
    # does not bind, and the pinned openai-agents 0.20.0 (openai>=2.45) keeps
    # prompt_cache_options.
    #
    # certifi>=2026.10.19 (0.19.1) exists to drop the emSign ECC Root CA - G3
    # root (compromised eMudhra intermediates, upstream #11203). The version floor
    # has no effect here: nixpkgs certifi serves nixpkgs cacert's bundle, and
    # omnigent prefers the OpenSSL default bundle over certifi in any case.
    pythonRelaxDeps = [
      "certifi"
      "openai"
      "websockets"
    ];

    dependencies = [
      omnigent-client
      omnigent-ui-sdk
      openai-agents
      py.alembic
      py.anyio
      py.argon2-cffi
      py.cachetools
      py.cel-python
      py.certifi
      py.claude-agent-sdk
      py.click
      py.fastapi
      py.filelock
      py.ftfy
      py.httpx
      py.json5
      py.keyring
      py.mcp
      py.openai
      py.opentelemetry-api
      py.packaging
      py.pexpect
      py.pillow
      py.prompt-toolkit
      py.protobuf
      py.psutil
      py.psycopg
      py.pydantic
      py.pyjwt
      py.pyte
      py.python-dateutil
      py.pyyaml
      py.rich
      py.sqlalchemy
      py.starlette
      py.tiktoken
      py.tomlkit
      py.uvicorn
      py.websockets
      py.zstandard
    ]
    ++ py.pyjwt.optional-dependencies.crypto
    ++ py.uvicorn.optional-dependencies.standard;

    dontWrapPythonPrograms = true;

    postInstall = ''
      (cd "$out/${py.python.sitePackages}" && patch -p1 < ${./acp-readiness.patch})
    '';

    pythonImportsCheck = [
      "omnigent"
      "omnigent.cli"
      "omnigent.harnesses.claude_native.hook"
      "omnigent_client"
      "omnigent_ui_sdk"
      "psycopg"
    ];

    meta = {
      description = "Common orchestration layer for AI coding agents";
      homepage = "https://omnigent.ai";
      license = lib.licenses.asl20;
      mainProgram = "omnigent";
      platforms = lib.platforms.unix;
    };
  };
  pythonEnv = py.python.withPackages (_: [ omnigent ]);
in
runCommand "omnigent-${version}"
  {
    pname = "omnigent";
    inherit version;
    inherit (omnigent) meta;
    passthru = {
      python = pythonEnv;
      inherit omnigent;
    };
  }
  ''
    mkdir -p "$out/bin"
    for program in omni omnigent; do
      cp "${omnigent}/bin/$program" "$out/bin/$program"
      chmod u+w "$out/bin/$program"
      substituteInPlace "$out/bin/$program" \
        --replace-fail '#!${py.python.interpreter}' '#!${pythonEnv.interpreter}'
    done
    env -i HOME="$TMPDIR" ${pythonEnv.interpreter} -I ${./test_acp_readiness.py}
    env -i ${pythonEnv.interpreter} -I -c '
    import omnigent, omnigent.harnesses.claude_native.hook, subprocess, sys
    subprocess.run([sys.executable, "-I", "-m", "omnigent.harnesses.claude_native.hook", "--help"], env={}, check=True)
    '
    env -i HOME="$TMPDIR" "$out/bin/omnigent" --version | grep -F "omnigent ${version} ("
    env -i HOME="$TMPDIR" "$out/bin/omnigent" --help > omnigent-help.txt
    cat omnigent-help.txt
    grep -w server omnigent-help.txt
    grep -w host omnigent-help.txt
    echo "omnigent-help-ok"
  ''
