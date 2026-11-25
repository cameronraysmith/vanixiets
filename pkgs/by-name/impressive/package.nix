# Impressive - PDF presentation tool with OpenGL transitions
#
# Impressive displays PDF presentations with smooth OpenGL
# transitions, spotlight effects, and overview mode.
#
# Source: https://impressive.sourceforge.net/
#
# pin.json pins the version and the source tarball's hash; Renovate proposes
# releases from SourceForge's RSS listing of /Impressive and `nix run
# .#realize-pin -- impressive <version>` realizes one.
{
  lib,
  stdenv,
  python3Packages,
  fetchurl,
  makeWrapper,
  mupdf,
  poppler-utils,
  ghostscript,
  ffmpeg,
  SDL2,
}:
let
  inherit ((import ../../../lib/pins.nix { inherit lib; }).load ./pin.json { name = "impressive"; })
    pin
    pinPlan
    ;
  planned = pinPlan pin.version;
in
python3Packages.buildPythonApplication rec {
  pname = "impressive";
  inherit (pin) version;
  pyproject = true;

  # SourceForge publishes no checksum file, so pin.json's `src` hash is a
  # prefetch of the tarball.
  src = fetchurl {
    inherit (planned.artifacts.src.file) url;
    inherit (pin.artifacts.src.file) hash;
  };

  build-system = [ python3Packages.setuptools ];

  postPatch = ''
    mkdir -p impressive_pkg
    cat > impressive_pkg/__init__.py << 'EOF'
    import sys
    from pathlib import Path
    _parent = Path(__file__).parent.parent
    if str(_parent) not in sys.path:
        sys.path.insert(0, str(_parent))
    from impressive import ParseOptions, run_main, __version__, __title__
    __all__ = ["main", "__version__", "__title__"]

    def main():
        ParseOptions(sys.argv[1:])
        run_main()
    EOF

    cat > pyproject.toml << EOF
    [project]
    name = "impressive"
    version = "${version}"
    requires-python = ">=3.9"
    [project.scripts]
    impressive = "impressive_pkg:main"
    [build-system]
    requires = ["setuptools"]
    build-backend = "setuptools.build_meta"
    [tool.setuptools]
    packages = ["impressive_pkg"]
    py-modules = ["impressive"]
    EOF
  '';

  dependencies = with python3Packages; [
    pygame
    pillow
  ];

  nativeBuildInputs = [ makeWrapper ];

  postInstall =
    let
      libraryPathVar = if stdenv.hostPlatform.isDarwin then "DYLD_LIBRARY_PATH" else "LD_LIBRARY_PATH";
    in
    ''
      wrapProgram $out/bin/impressive \
        --prefix PATH : ${
          lib.makeBinPath [
            mupdf
            poppler-utils
            ghostscript
            ffmpeg
          ]
        } \
        --prefix ${libraryPathVar} : ${lib.makeLibraryPath [ SDL2 ]}
    '';

  doCheck = false;
  pythonImportsCheck = [ "impressive_pkg" ];

  passthru = {
    inherit pin pinPlan;
  };

  meta = {
    description = "PDF presentation tool with OpenGL transitions and spotlight effects";
    homepage = "https://impressive.sourceforge.net/";
    license = lib.licenses.gpl2Only;
    mainProgram = "impressive";
    platforms = lib.platforms.unix;
  };
}
