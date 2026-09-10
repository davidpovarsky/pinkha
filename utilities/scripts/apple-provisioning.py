#!/usr/bin/env python3
"""Configure ChavrusaNotes Apple resources and mint App Store profiles."""

from __future__ import annotations

import argparse
import base64
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import jwt
from cryptography import x509


API_ROOT = "https://api.appstoreconnect.apple.com"
TEAM_ID = "NA6HPWARQ2"
APP_ID = "com.itorah.chavrusanotes"
TARGETS = {
    APP_ID: "ChavrusaNotes",
    f"{APP_ID}.share": "ChavrusaNotes Share",
    f"{APP_ID}.widgets": "ChavrusaNotes Widgets",
}
CAPABILITIES = {
    APP_ID: {
        "APP_GROUPS": None,
        "ICLOUD": [
            {"key": "ICLOUD_VERSION", "options": [{"key": "XCODE_6"}]}
        ],
        "PUSH_NOTIFICATIONS": None,
        "SIRIKIT": None,
    },
    f"{APP_ID}.share": {"APP_GROUPS": None},
    f"{APP_ID}.widgets": {"APP_GROUPS": None},
}


class Client:
    def __init__(self) -> None:
        key_path = Path(os.environ["ASC_KEY_PATH"])
        now = int(time.time())
        token = jwt.encode(
            {
                "iss": os.environ["ASC_ISSUER_ID"],
                "iat": now,
                "exp": now + 600,
                "aud": "appstoreconnect-v1",
            },
            key_path.read_bytes(),
            algorithm="ES256",
            headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
        )
        self.headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        }

    def request(self, method: str, path: str, body: dict | None = None) -> dict:
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(
            f"{API_ROOT}{path}", data=data, headers=self.headers, method=method
        )
        try:
            with urllib.request.urlopen(request, timeout=45) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            raw = error.read().decode("utf-8", errors="replace")
            try:
                errors = json.loads(raw).get("errors", [])
                detail = "; ".join(
                    f"{item.get('code', 'unknown')}: {item.get('detail', item.get('title', ''))}"
                    for item in errors
                )
            except json.JSONDecodeError:
                detail = raw[:500]
            raise RuntimeError(
                f"App Store Connect API {method} {path} failed ({error.code}): {detail}"
            ) from error

    def list_all(self, path: str) -> list[dict]:
        values: list[dict] = []
        while path:
            response = self.request("GET", path)
            values.extend(response.get("data", []))
            next_url = response.get("links", {}).get("next")
            path = next_url.removeprefix(API_ROOT) if next_url else ""
        return values


def bundle(client: Client, identifier: str, name: str) -> dict:
    query = urllib.parse.urlencode({"filter[identifier]": identifier, "limit": 10})
    matches = [
        item
        for item in client.list_all(f"/v1/bundleIds?{query}")
        if item.get("attributes", {}).get("identifier") == identifier
    ]
    if matches:
        return matches[0]
    response = client.request(
        "POST",
        "/v1/bundleIds",
        {
            "data": {
                "type": "bundleIds",
                "attributes": {
                    "identifier": identifier,
                    "name": name,
                    "platform": "IOS",
                    "seedId": TEAM_ID,
                },
            }
        },
    )
    print(f"Registered Bundle ID {identifier}")
    return response["data"]


def configure(client: Client) -> dict[str, dict]:
    bundles = {
        identifier: bundle(client, identifier, name)
        for identifier, name in TARGETS.items()
    }
    for identifier, resource in bundles.items():
        enabled = {
            item["attributes"]["capabilityType"]
            for item in client.list_all(
                f"/v1/bundleIds/{resource['id']}/bundleIdCapabilities"
            )
        }
        for capability_type, settings in CAPABILITIES[identifier].items():
            if capability_type in enabled:
                continue
            attributes: dict[str, object] = {"capabilityType": capability_type}
            if settings is not None:
                attributes["settings"] = settings
            client.request(
                "POST",
                "/v1/bundleIdCapabilities",
                {
                    "data": {
                        "type": "bundleIdCapabilities",
                        "attributes": attributes,
                        "relationships": {
                            "bundleId": {
                                "data": {"type": "bundleIds", "id": resource["id"]}
                            }
                        },
                    }
                },
            )
            print(f"Enabled {capability_type} for {identifier}")

    apps = client.list_all(
        f"/v1/apps?{urllib.parse.urlencode({'filter[bundleId]': APP_ID})}"
    )
    if not apps:
        print(
            "App Store Connect app record is not present; Apple does not allow "
            "app creation through this API key endpoint"
        )
    else:
        print("Verified App Store Connect app record for ChavrusaNotes")
    return bundles


def certificate_id(client: Client, certificate_path: Path) -> str:
    certificate = x509.load_pem_x509_certificate(certificate_path.read_bytes())
    serial = format(certificate.serial_number, "X").lstrip("0") or "0"
    candidates = client.list_all("/v1/certificates?limit=200")
    for candidate in candidates:
        attributes = candidate.get("attributes", {})
        api_serial = "".join(
            char for char in attributes.get("serialNumber", "").upper() if char in "0123456789ABCDEF"
        ).lstrip("0") or "0"
        if api_serial == serial and "DISTRIBUTION" in attributes.get("certificateType", ""):
            return candidate["id"]
    raise RuntimeError("The local Apple Distribution certificate is not active on this team")


def create_profiles(client: Client, bundles: dict[str, dict], output: Path, certificate_path: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    signing_certificate_id = certificate_id(client, certificate_path)
    stamp = int(time.time())
    for identifier, resource in bundles.items():
        safe_name = TARGETS[identifier].replace(" ", "_")
        response = client.request(
            "POST",
            "/v1/profiles",
            {
                "data": {
                    "type": "profiles",
                    "attributes": {
                        "name": f"{safe_name}_App_Store_{stamp}",
                        "profileType": "IOS_APP_STORE",
                    },
                    "relationships": {
                        "bundleId": {"data": {"type": "bundleIds", "id": resource["id"]}},
                        "certificates": {
                            "data": [{"type": "certificates", "id": signing_certificate_id}]
                        },
                    },
                }
            },
        )["data"]
        destination = output / f"{safe_name}_App_Store.mobileprovision"
        destination.write_bytes(base64.b64decode(response["attributes"]["profileContent"]))
        print(f"Created {destination.name} for {identifier}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("operation", choices=("configure", "create-profiles"))
    parser.add_argument("--output", type=Path)
    parser.add_argument("--certificate", type=Path)
    args = parser.parse_args()
    client = Client()
    bundles = configure(client)
    if args.operation == "create-profiles":
        if not args.output or not args.certificate:
            parser.error("create-profiles requires --output and --certificate")
        create_profiles(client, bundles, args.output, args.certificate)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
