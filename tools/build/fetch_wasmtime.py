"""Fetch the pinned wasmtime C API (MSVC x64 headers, import library, DLL and license).

FLAG PC divergence: the runtime of the WebAssembly mod host (b5-decomp/src/pc/mods/). Why
wasmtime: the PC build is x64 only, wasmtime ships an official prebuilt C API for it, compiles
mods with Cranelift (an egui/ImGui mod stays at native-ish speed), and has the two limits a
sandboxed mod host needs built in -- epoch interruption (a stuck mod traps instead of freezing
the frame) and per-store memory limits -- plus traps that unwind cleanly back to the host.
"""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import shutil
import tempfile
import urllib.request
import zipfile

VERSION = "49.0.2"
SHA256 = "928dad67acbf4a4f97be8d528b271ac72f8e329da21e327b0724d3af86fe3f44"
NAME = f"wasmtime-v{VERSION}-x86_64-windows-c-api"
URL = f"https://github.com/bytecodealliance/wasmtime/releases/download/v{VERSION}/{NAME}.zip"
DEST = Path(__file__).resolve().parents[2] / "b5-decomp/vendor/wasmtime"
REQUIRED = ("include/wasmtime.h", "include/wasm.h", "lib/wasmtime.dll", "lib/wasmtime.dll.lib",
            "LICENSE")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    stamp = DEST / "VERSION.txt"
    if (not args.force and stamp.exists() and stamp.read_text().strip() == VERSION
            and all((DEST / name).is_file() for name in REQUIRED)):
        print(f"wasmtime {VERSION} already present in {DEST}")
        return 0
    with tempfile.TemporaryDirectory(prefix="brn_wasmtime_") as directory:
        stage = Path(directory)
        archive = stage / "wasmtime.zip"
        print(f"Downloading wasmtime {VERSION} C API from bytecodealliance/wasmtime ...", flush=True)
        with urllib.request.urlopen(URL, timeout=300) as response, archive.open("wb") as output:
            shutil.copyfileobj(response, output)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
            raise RuntimeError("wasmtime archive SHA-256 does not match the pinned release")
        unpack = stage / "unpacked"
        with zipfile.ZipFile(archive) as package:
            for name in package.namelist():
                if not (unpack / name).resolve().is_relative_to(unpack.resolve()):
                    raise RuntimeError("wasmtime archive contains an unsafe path")
            package.extractall(unpack)
        source = unpack / NAME
        if not all((source / name).is_file() for name in REQUIRED):
            raise RuntimeError("wasmtime package is missing required build/runtime files")
        if DEST.exists():
            shutil.rmtree(DEST)
        # The static wasmtime.lib (~100 MB) is not used: the exe links the DLL's import library.
        shutil.copytree(source, DEST, ignore=shutil.ignore_patterns("wasmtime.lib"))
        stamp.write_text(VERSION + "\n", encoding="ascii")
    print(f"wasmtime {VERSION} installed to {DEST}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
