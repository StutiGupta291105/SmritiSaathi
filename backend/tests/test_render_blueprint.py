"""render.yaml is re-applied on every deploy. A setting that the owner changes in the Render
dashboard must not have a value here, or the deploy puts the old value back (this once
switched real push off again)."""
from pathlib import Path

BLUEPRINT = (Path(__file__).resolve().parents[2] / "render.yaml").read_text()


def _block(key: str) -> str:
    lines = BLUEPRINT.splitlines()
    for i, ln in enumerate(lines):
        if ln.strip() == f"- key: {key}":
            out = []
            for nxt in lines[i + 1:]:
                if nxt.strip().startswith("- key:"):
                    break
                out.append(nxt)
            return "\n".join(out)
    raise AssertionError(f"{key} is not in render.yaml")


def test_settings_the_owner_changes_in_the_dashboard_are_not_overwritten_by_deploys():
    for key in ("SMRITI_PUSH_PROVIDER", "SMRITI_FCM_PROJECT_ID", "SMRITI_FCM_CREDENTIALS_JSON",
                "SMRITI_COMPANION_API_KEY", "SMRITI_ADMIN_PASSWORD"):
        assert "sync: false" in _block(key), f"{key} would be reset by a deploy"
        assert "value:" not in _block(key)
