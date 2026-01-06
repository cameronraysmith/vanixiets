# Impressive - PDF presentation tool with OpenGL transitions
#
# Impressive displays PDF presentations with smooth OpenGL
# transitions, spotlight effects, and overview mode.
#
# Source: https://impressive.sourceforge.net/
{
  lib,
  python3Packages,
  fetchurl,
  makeWrapper,
  mupdf,
  poppler-utils,
  ghostscript,
  ffmpeg,
}:

python3Packages.buildPythonApplication rec {
  pname = "impressive";
  version = "0.13.2";
  pyproject = true;

  src = fetchurl {
    url = "mirror://sourceforge/impressive/Impressive-${version}.tar.gz";
    hash = "sha256-AzEjsl9CywhPb9CpWd31MQDTICxn5mblzFek5I7BJTw=";
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
    from impressive import main, __version__, __title__
    __all__ = ["main", "__version__", "__title__"]
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

  postInstall = ''
    wrapProgram $out/bin/impressive \
      --prefix PATH : ${
        lib.makeBinPath [
          mupdf
          poppler-utils
          ghostscript
          ffmpeg
        ]
      }
  '';

  doCheck = false;
  pythonImportsCheck = [ "impressive_pkg" ];

  meta = {
    description = "PDF presentation tool with OpenGL transitions and spotlight effects";
    homepage = "https://impressive.sourceforge.net/";
    license = lib.licenses.gpl2Only;
    mainProgram = "impressive";
    platforms = lib.platforms.unix;
  };
}
