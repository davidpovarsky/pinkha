#!/usr/bin/env python3
"""Focused source-of-truth checks for the ChavrusaNotes Apple identity."""

from pathlib import Path
import plistlib


root = Path(__file__).resolve().parents[2]
project = (root / "app/project.yml").read_text(encoding="utf-8")
required = {
    "com.itorah.chavrusanotes",
    "com.itorah.chavrusanotes.share",
    "com.itorah.chavrusanotes.widgets",
    "NA6HPWARQ2",
}
missing = sorted(value for value in required if value not in project)
assert not missing, f"project.yml is missing identity values: {missing}"

main = plistlib.loads((root / "app/Sources/Pinkha.entitlements").read_bytes())
assert set(main["com.apple.security.application-groups"]) == {
    "group.com.itorah.chavrusanotes",
    "group.com.itorah.shared",
}
assert main["com.apple.developer.icloud-container-identifiers"] == [
    "iCloud.com.itorah.chavrusanotes"
]
assert set(main["com.apple.developer.icloud-services"]) == {
    "CloudDocuments",
    "CloudKit",
}
assert main["aps-environment"] == "development"
assert main["com.apple.developer.siri"] is True

for path in [
    root / "app/Extensions/Share/ChavrusaNotesShare.entitlements",
    root / "app/Extensions/Widgets/ChavrusaNotesWidgets.entitlements",
]:
    entitlements = plistlib.loads(path.read_bytes())
    assert set(entitlements["com.apple.security.application-groups"]) == {
        "group.com.itorah.chavrusanotes",
        "group.com.itorah.shared",
    }

stale = (
    ".".join(("com", "gloiiire", "pinkha")),
    "".join(("N49", "VNC2", "G57")),
    ".".join(("iCloud", "com", "gloiiire", "pinkha")),
)
checked = [root / "app", root / ".github", root / "fastlane", root / "utilities/scripts"]
violations = []
for base in checked:
    for path in base.rglob("*"):
        if path.is_file() and path != Path(__file__).resolve():
            try:
                text = path.read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError):
                continue
            for value in stale:
                if value in text:
                    violations.append(f"{path.relative_to(root)}: {value}")
assert not violations, "stale Apple production identity references:\n" + "\n".join(violations)
print("ChavrusaNotes Apple identity source checks passed")
