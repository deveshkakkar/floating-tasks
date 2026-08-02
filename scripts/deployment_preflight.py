from __future__ import annotations

import argparse
import re
import shutil
import subprocess
from pathlib import Path


ACCOUNT_ID_PATTERN = re.compile(r"^[0-9]{12}$")
DOMAIN_PREFIX_PATTERN = re.compile(r"^[a-z0-9][a-z0-9-]{0,62}$")
REQUIRED_FILES = (
    Path("sam/template.yaml"),
    Path("sam/lambda/app.py"),
    Path("sam/tests/test_app.py"),
)


def validate_parameters(account_id: str, domain_prefix: str) -> list[str]:
    errors = []
    if not ACCOUNT_ID_PATTERN.fullmatch(account_id):
        errors.append("account ID must contain exactly 12 digits")
    if not DOMAIN_PREFIX_PATTERN.fullmatch(domain_prefix):
        errors.append("Cognito domain prefix must be lowercase letters, numbers, and hyphens")
    return errors


def current_aws_account() -> str:
    result = subprocess.run(
        ["aws", "sts", "get-caller-identity", "--query", "Account", "--output", "text"],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate Floating Brain deployment prerequisites.")
    parser.add_argument("--account-id", required=True)
    parser.add_argument("--domain-prefix", required=True)
    args = parser.parse_args()

    errors = validate_parameters(args.account_id, args.domain_prefix)
    errors.extend(f"missing {path}" for path in REQUIRED_FILES if not path.exists())
    for tool in ("aws", "sam"):
        if shutil.which(tool) is None:
            errors.append(f"required tool not found: {tool}")

    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1

    actual_account = current_aws_account()
    if actual_account != args.account_id:
        print(f"ERROR: active AWS account is {actual_account}, expected {args.account_id}")
        return 1

    print(f"AWS account: {actual_account}")
    print("Required files: present")
    print("AWS and SAM CLIs: present")
    print("Preflight passed; deployment was not performed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
