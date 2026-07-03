# Tool-integration sharp edges

These are the friction points the safeadt worked example surfaced by actually running the single-contract stack under a current toolchain.
Each is grounded in the safeadt source tree at `/Users/crs58/projects/functional-programming-workspace/safeadt/`, read at the revision whose README reports CPython 3.14.2, Hypothesis 6.139.3, basedpyright 1.39.9, crosshair-tool 0.0.107, and icontract-hypothesis 1.1.7.

## beartype's claw hook crashes CrossHair's native importer

`beartype_this_package()` installs a claw import hook whose loader crashes CrossHair's native CLI importer, so `crosshair check` on a package that calls the claw hook fails.
The Hypothesis crosshair *backend* (`@settings(backend="crosshair")`) is unaffected — only the native `crosshair check` CLI checker is.
The resolution safeadt takes is to use explicit `@beartype` decorators on boundary functions, which compose with both the CLI checker and the backend, rather than the package-wide claw hook; if the claw hook is wanted for its coverage, rely on the crosshair backend instead of the native CLI for symbolic checking.
This is why the geometry functions carry an explicit `@beartype` (see `scaled_rectangle_area` in `src/safeadt/geometry.py`) rather than depending on `beartype_this_package()`.

Source: safeadt `README.md`, sharp edge 4 ("beartype's claw import hook conflicts with `crosshair check`").

## The Hypothesis compatibility shim (renamed private symbol)

icontract-hypothesis reads a private Hypothesis symbol at import time and a recent Hypothesis rename breaks the import outright, poisoning `import hypothesis` itself.
icontract-hypothesis 1.1.7 saves `hypothesis.internal.reflection.extract_lambda_source` before monkeypatching it (Hypothesis issue #2713).
Hypothesis renamed that helper to `lambda_description` and moved it to `hypothesis.internal.lambda_sources` as of 6.137.3 (rename commit 996d7bd1a, 2025-08-10), so the true break boundary is 6.137.3, not the later 6.140 an older bare pin implied.
Because icontract-hypothesis registers a Hypothesis entry-point hook, the failure fires inside the plugin autoloader: a bare `python -c "import hypothesis"` under 6.139.3 raises `AttributeError` before any user code runs.

safeadt's fix is `src/safeadt/_hypothesis_compat.py`, which reinstalls the old name as an alias for the moved one.
Two details in the shim are load-bearing.
First, it must run before anything imports icontract-hypothesis; `src/safeadt/tests/conftest.py` imports the shim first.
Second, importing the Hypothesis internals to install the alias would itself fire the plugin autoloader (which imports icontract-hypothesis and reads the missing symbol), so the shim sets `HYPOTHESIS_NO_PLUGINS=1` for the duration of its internal import, installs the alias, restores the previous env value, and only then re-runs `hypothesis.entry_points.run()` so the plugins — icontract-hypothesis, now satisfied, and the CrossHair backend provider — load normally.
The alias install is guarded to no-op when the symbol still exists, and reads `lambda_sources.lambda_description` unguarded so that a future Hypothesis dropping *that* name fails loudly rather than aliasing to nothing.

`pyproject.toml` pins `hypothesis[crosshair]>=6.122,<6.140` as a tested ceiling (verified at 6.139.3 with the shim), to be raised as newer versions are checked.
This supersedes the earlier advice to drop icontract-hypothesis or switch to deal: the shim keeps the single-contract thesis intact under a current Hypothesis.

Source: safeadt `README.md`, sharp edge 2; `src/safeadt/_hypothesis_compat.py:1-47`; `src/safeadt/tests/conftest.py`; `pyproject.toml` (the `hypothesis[crosshair]>=6.122,<6.140` pin).

## The two basedpyright strict relaxations for icontract lambdas

icontract conditions are untyped lambdas, and each `@require(lambda x: ...)` raises exactly two basedpyright strict diagnostics: `reportUnknownLambdaType` and `reportUnknownArgumentType`.
safeadt disables just those two in `pyproject.toml` and leaves the rest of strict mode on:

```toml
reportUnknownLambdaType = false
reportUnknownArgumentType = false
```

Disabling only these two is the minimal relaxation that admits the contract lambdas while keeping strict-mode coverage everywhere else; do not reach for a broader `typeCheckingMode` downgrade.

Source: safeadt `README.md`, sharp edge 3; `pyproject.toml:94-96`.
