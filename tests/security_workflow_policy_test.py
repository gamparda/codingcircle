from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VALIDATOR_PATH = ROOT / "tools" / "ci" / "validate_workflow_policy.py"
WORKFLOW_PATH = ROOT / ".github" / "workflows" / "build-and-deploy.yml"


def load_validator():
    spec = importlib.util.spec_from_file_location("workflow_policy", VALIDATOR_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {VALIDATOR_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class WorkflowPolicyTest(unittest.TestCase):
    def test_release_workflow_satisfies_supply_chain_policy(self) -> None:
        validator = load_validator()
        self.assertEqual([], validator.validate(WORKFLOW_PATH.read_text(encoding="utf-8")))

    def test_validator_reports_mutable_action_and_unverified_download(self) -> None:
        validator = load_validator()
        unsafe = """permissions:\n  contents: write\njobs:\n  build:\n    steps:\n      - uses: actions/checkout@v4\n      - run: Invoke-WebRequest https://example.invalid/tool.zip -OutFile tool.zip\n"""
        violations = validator.validate(unsafe)
        self.assertTrue(any("full commit SHA" in item for item in violations), violations)
        self.assertTrue(any("download" in item.lower() for item in violations), violations)

    def test_validator_rejects_extra_build_permission(self) -> None:
        validator = load_validator()
        safe = WORKFLOW_PATH.read_text(encoding="utf-8")
        unsafe = safe.replace(
            "  build:\n    needs: validate-policy\n    runs-on: windows-latest\n    permissions:\n      contents: read\n",
            "  build:\n    needs: validate-policy\n    runs-on: windows-latest\n    permissions:\n      contents: read\n      packages: write\n",
        )
        violations = validator.validate(unsafe)
        self.assertTrue(any("build job" in item for item in violations), violations)

    def test_cli_is_deterministic_and_fails_closed(self) -> None:
        validator = load_validator()
        with tempfile.TemporaryDirectory() as directory:
            unsafe_path = Path(directory) / "unsafe.yml"
            unsafe_path.write_text("jobs: {}\n", encoding="utf-8")
            first = validator.validate(unsafe_path.read_text(encoding="utf-8"))
            second = validator.validate(unsafe_path.read_text(encoding="utf-8"))
        self.assertEqual(first, second)
        self.assertGreater(len(first), 0)


if __name__ == "__main__":
    unittest.main()
