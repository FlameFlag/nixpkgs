#!/usr/bin/env nix-shell
#! nix-shell -i python3 -p python3 git
"""
Build shaders.metallib from Warp's shaders.metal using xcrun.

Run this on macOS with Xcode or Command Line Tools installed. Rebuild the
metallib when the pinned Warp rev or shader source changes.

Usage:
  build-metallib.py                  # fetch the rev from package.nix
  build-metallib.py --source PATH    # use a local Warp checkout
  build-metallib.py --output PATH    # choose the output path
"""
import argparse
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
PKG_DIR = SCRIPT_DIR.parent
SHADER_REL = "crates/warpui/src/platform/mac/rendering/metal/shaders/shaders.metal"
DEFAULT_OUTPUT = PKG_DIR / "shaders.metallib"
MIN_MACOS = "10.14"


def read_warp_ref() -> str:
    text = (PKG_DIR / "package.nix").read_text()
    version_match = re.search(r'\bversion\s*=\s*"([^"]+)"', text)
    rev_match = re.search(r'\brepo\s*=\s*"warp"\s*;.*?\brev\s*=\s*"([^"]+)"', text, re.S)

    if not rev_match:
        sys.exit('could not find rev = "..." in package.nix')

    rev = rev_match.group(1)
    if rev == "v${finalAttrs.version}":
        if not version_match:
            sys.exit('could not resolve rev = "v${finalAttrs.version}"')
        return f"v{version_match.group(1)}"

    return rev


def fetch_source(rev: str, dest: pathlib.Path) -> pathlib.Path:
    url = "https://github.com/warpdotdev/warp.git"
    print(f"cloning {url} @ {rev} into {dest}")
    subprocess.run(["git", "init", str(dest)], check=True)
    subprocess.run(
        ["git", "-C", str(dest), "remote", "add", "origin", url], check=True
    )
    subprocess.run(
        ["git", "-C", str(dest), "fetch", "--depth=1", "origin", rev], check=True
    )
    subprocess.run(["git", "-C", str(dest), "checkout", "FETCH_HEAD"], check=True)
    return dest


def run(cmd: list[str]) -> None:
    print("+", " ".join(cmd))
    subprocess.run(cmd, check=True)


def compile_metallib(shader: pathlib.Path, output: pathlib.Path) -> None:
    with tempfile.TemporaryDirectory() as td:
        air = pathlib.Path(td) / "shaders.air"
        run([
            "xcrun", "-sdk", "macosx", "metal",
            "-c", str(shader),
            "-o", str(air),
            f"-mmacos-version-min={MIN_MACOS}",
        ])
        output.parent.mkdir(parents=True, exist_ok=True)
        run([
            "xcrun", "-sdk", "macosx", "metallib",
            str(air), "-o", str(output),
        ])


def main() -> None:
    p = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument("--source", type=pathlib.Path, help="path to a local warp checkout")
    p.add_argument(
        "--output",
        type=pathlib.Path,
        default=DEFAULT_OUTPUT,
        help=f"output metallib path (default: {DEFAULT_OUTPUT})",
    )
    args = p.parse_args()

    if sys.platform != "darwin":
        sys.exit("metal compilation requires macOS with Xcode installed")
    if shutil.which("xcrun") is None:
        sys.exit("xcrun not on PATH; install Xcode Command Line Tools")

    if args.source is not None:
        src_root = args.source.resolve()
    else:
        with tempfile.TemporaryDirectory(prefix="warp-metallib-") as td:
            src_root = fetch_source(read_warp_ref(), pathlib.Path(td) / "warp")
            shader = src_root / SHADER_REL
            if not shader.is_file():
                sys.exit(f"shader source not found at {shader}")

            compile_metallib(shader, args.output.resolve())
            print(f"wrote {args.output}")
            return

    shader = src_root / SHADER_REL
    if not shader.is_file():
        sys.exit(f"shader source not found at {shader}")

    compile_metallib(shader, args.output.resolve())
    print(f"wrote {args.output}")


if __name__ == "__main__":
    main()
