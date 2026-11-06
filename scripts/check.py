"""Run the credential-free checks used by CI from any working directory."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]


def run(command: list[str], *, directory: Path = ROOT, python_path: str | None = None) -> None:
    environment = os.environ.copy()
    if python_path:
        environment["PYTHONPATH"] = str(ROOT / python_path)
    print(f"\n> {' '.join(command)}", flush=True)
    subprocess.run(command, cwd=directory, env=environment, check=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--python-only", action="store_true", help="Run Python suites and file-format checks only.")
    args = parser.parse_args()
    try:
        run([sys.executable, "-m", "unittest", "discover", "-s", "sam/tests", "-v"])
        run([sys.executable, "-m", "unittest", "discover", "-s", "pi/tests", "-v"], python_path="pi")
        run([sys.executable, "-m", "unittest", "discover", "-s", "scripts", "-p", "test_*.py", "-v"], python_path="scripts")
        for directory in ("FloatingBrain", "FloatingBrainWidget", "ShareExtension"):
            for path in (ROOT / directory).iterdir():
                if path.suffix in {".plist", ".entitlements"}:
                    plistlib.loads(path.read_bytes())
        for name in ("package.json", "package-lock.json"):
            json.loads((ROOT / "floating" / name).read_text())
        print("\nApple plist/entitlement and npm JSON files: valid", flush=True)
        if not args.python_only:
            run(["npm", "run", "typecheck"], directory=ROOT / "floating")
            run(["npm", "test"], directory=ROOT / "floating")
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"\nChecks failed: {error}", file=sys.stderr)
        return 1
    print("\nLocal checks passed. Xcode simulator tests and SAM lint run separately.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
