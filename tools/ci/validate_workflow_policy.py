#!/usr/bin/env python3
"""Deterministically enforce the release workflow's supply-chain policy."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

FULL_SHA = re.compile(r"^[0-9a-f]{40}$")
ACTION_REF = re.compile(r"^\s*-?\s*uses:\s*([^\s@]+)@([^\s#]+)", re.MULTILINE)


def _job_block(text: str, job: str) -> str:
    match = re.search(rf"(?ms)^  {re.escape(job)}:\s*\n(.*?)(?=^  [a-zA-Z0-9_-]+:\s*$|\Z)", text)
    return match.group(1) if match else ""


def _job_permissions(text: str, job: str) -> tuple[str, ...]:
    block = _job_block(text, job)
    match = re.search(r"(?ms)^    permissions:\s*\n((?:^      [a-zA-Z-]+:\s*\S+\s*$\n?)+)", block)
    if not match:
        return ()
    return tuple(sorted(line.strip() for line in match.group(1).splitlines()))


def validate(text: str) -> list[str]:
    violations: list[str] = []

    if not re.search(r"(?m)^permissions:\s*\{\}\s*$", text):
        violations.append("workflow-wide permissions must be empty")

    for action, ref in ACTION_REF.findall(text):
        if not FULL_SHA.fullmatch(ref):
            violations.append(f"action {action}@{ref} is not pinned to a full commit SHA")

    checkout_blocks = re.findall(
        r"(?ms)^\s*- name:.*?\n\s+uses:\s*actions/checkout@[0-9a-f]+.*?(?=^\s*- name:|^\s{2}[a-zA-Z_-]+:|\Z)",
        text,
    )
    if not checkout_blocks:
        violations.append("workflow must check out source")
    elif any(not re.search(r"(?m)^\s+persist-credentials:\s*false\s*$", block) for block in checkout_blocks):
        violations.append("every checkout must set persist-credentials: false")

    required_jobs = ("validate-policy", "build", "sign", "release", "deploy")
    for job in required_jobs:
        if not re.search(rf"(?m)^  {re.escape(job)}:\s*$", text):
            violations.append(f"missing least-privilege job: {job}")

    expected_permissions = {
        "validate-policy": ("contents: read",),
        "build": ("contents: read",),
        "sign": ("contents: read",),
        "release": ("contents: write",),
        "deploy": ("id-token: write", "pages: write"),
    }
    for job, expected in expected_permissions.items():
        actual = _job_permissions(text, job)
        if actual != expected:
            violations.append(
                f"{job} job permissions must be exactly {', '.join(expected)} (got {', '.join(actual) or 'none'})"
            )

    if "needs: validate-policy" not in text:
        violations.append("build must depend on policy validation")
    if text.count("needs: build") != 1 or text.count("needs: sign") < 2:
        violations.append("sign must consume build output; release and deploy must consume signed output")

    if re.search(r"(?i)choco(?:latey)?\s+install|@(?:v|main|master|latest)\b", text):
        violations.append("mutable package/action reference is forbidden")

    downloads = re.findall(r"(?i)(?:Invoke-WebRequest|curl\b|wget\b).*https?://", text)
    if downloads and "Assert-Sha256" not in text and "Get-FileHash" not in text:
        violations.append("download is not followed by deterministic checksum verification")

    required_hashes = {
        "Godot archive": "731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953",
        "Godot templates": "f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011",
        "Inno Setup": "9c73c3bae7ed48d44112a0f48e66742c00090bdb5bef71d9d3c056c66e97b732",
    }
    for label, digest in required_hashes.items():
        if digest not in text:
            violations.append(f"missing pinned {label} SHA-256")

    secret_expression = "${{ secrets.UPDATE_MANIFEST_SIGNING_KEY_B64 }}"
    if text.count(secret_expression) != 1:
        violations.append("signing secret must be injected exactly once")
    if not re.search(r"(?m)^\s+UPDATE_MANIFEST_SIGNING_KEY_B64:\s*\$\{\{ secrets\.UPDATE_MANIFEST_SIGNING_KEY_B64 \}\}\s*$", text):
        violations.append("signing key must only be passed through step environment")
    sign_block = _job_block(text, "sign")
    if "actions/checkout@" in sign_block or "run: python" in sign_block or "run: ./" in sign_block:
        violations.append("sign job must not check out or execute repository-controlled code")
    for token in ("update.json.sig", "SignData", "ImportFromPem"):
        if token not in text:
            violations.append(f"signed update manifest is missing {token}")

    if not re.search(r"(?ms)^  sign:.*?^    environment:\s*\n      name:\s*release\s*$", text):
        violations.append("sign job must use the protected release environment")
    if not re.search(r"(?ms)^  deploy:.*?^    environment:\s*\n      name:\s*github-pages\s*$", text):
        violations.append("deploy job must use the github-pages environment")
    if not re.search(r"(?ms)^  push:\s*\n    branches:\s*\[main\]", text):
        violations.append("tested main pushes must remain the publication trigger")

    return sorted(set(violations))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "workflow",
        nargs="?",
        type=Path,
        default=Path(".github/workflows/build-and-deploy.yml"),
    )
    args = parser.parse_args()
    violations = validate(args.workflow.read_text(encoding="utf-8"))
    if violations:
        print("release workflow policy violations:")
        for violation in violations:
            print(f"- {violation}")
        return 1
    print(f"release workflow policy passed: {args.workflow}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
