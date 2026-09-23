#!/usr/bin/env python3
"""Fetch a preview signing secret or publish static APT files with VM identity."""

import email.utils
import json
import mimetypes
import os
import pathlib
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


VAULT = "broospackagespreviewkv"
ACCOUNT = "broospackagesapp"
SECRET = "apt-preview-secret-key"
API_VERSION = "2023-11-03"


def token(resource):
    query = urllib.parse.urlencode({"api-version": "2018-02-01", "resource": resource})
    request = urllib.request.Request(
        "http://169.254.169.254/metadata/identity/oauth2/token?" + query,
        headers={"Metadata": "true"},
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        return json.load(response)["access_token"]


def get_preview_key(destination):
    url = f"https://{VAULT}.vault.azure.net/secrets/{SECRET}?api-version=7.4"
    request = urllib.request.Request(
        url, headers={"Authorization": "Bearer " + token("https://vault.azure.net")}
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        armored = json.load(response)["value"].encode("utf-8")
    fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as output:
        output.write(armored)
    print("Preview signing key retrieved to a private temporary file")


def put_blob(relative_path, payload, bearer):
    encoded = urllib.parse.quote("apt/" + relative_path.as_posix(), safe="/")
    url = f"https://{ACCOUNT}.blob.core.windows.net/%24web/{encoded}"
    media_type = mimetypes.guess_type(relative_path.name)[0] or "application/octet-stream"
    request = urllib.request.Request(
        url,
        data=payload,
        method="PUT",
        headers={
            "Authorization": "Bearer " + bearer,
            "Content-Type": media_type,
            "x-ms-blob-type": "BlockBlob",
            "x-ms-version": API_VERSION,
            "x-ms-date": email.utils.formatdate(usegmt=True),
        },
    )
    for attempt in range(6):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                if response.status != 201:
                    raise RuntimeError(f"Unexpected blob status: {response.status}")
            print("Uploaded", relative_path)
            return
        except urllib.error.HTTPError as error:
            if error.code not in (403, 429, 500, 503) or attempt == 5:
                raise RuntimeError(f"Blob upload failed for {relative_path}: HTTP {error.code}") from error
            time.sleep(10 * (attempt + 1))


def upload_repository(directory):
    root = pathlib.Path(directory).resolve()
    if not (root / "dists/preview/InRelease").is_file():
        raise SystemExit("Signed preview InRelease is missing")
    paths = sorted(path for path in root.rglob("*") if path.is_file())
    if any(path.is_symlink() for path in paths):
        raise SystemExit("Refusing to upload symlinked repository files")
    # Make package objects and detached indexes visible before the signed
    # InRelease switches APT clients to the new repository state.
    paths.sort(key=lambda path: path.relative_to(root).as_posix().endswith("/InRelease"))
    bearer = token("https://storage.azure.com/")
    for path in paths:
        put_blob(path.relative_to(root), path.read_bytes(), bearer)


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("key", "upload"):
        raise SystemExit("usage: azure-identity-publish.py key OUTPUT | upload REPOSITORY")
    if sys.argv[1] == "key":
        get_preview_key(sys.argv[2])
    else:
        upload_repository(sys.argv[2])
