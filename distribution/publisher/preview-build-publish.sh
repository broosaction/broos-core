#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq apt-utils ca-certificates curl git gnupg python3 rsync

work=$(mktemp -d /tmp/broos-preview.XXXXXX)
chmod 700 "$work"
git clone --quiet --depth 1 --branch broos/preview-packaging \
  https://github.com/broosaction/broos-core.git "$work/broos-core"
git clone --quiet --depth 1 --branch broos/preview-console \
  https://github.com/broosaction/broos-console-theme.git "$work/broos-console-theme"

publisher="$work/broos-core/distribution/publisher"
python3 "$publisher/azure-identity-publish.py" key "$work/secret.asc"
export GNUPGHOME="$work/gnupg"
install -d -m 0700 "$GNUPGHOME"
gpg --batch --import "$work/secret.asc" >/dev/null 2>&1
fingerprint=$(gpg --batch --with-colons --list-secret-keys |
  awk -F: '$1 == "fpr" { print $10; exit }')
test -n "$fingerprint"
gpg --batch --export "$fingerprint" > "$work/public.gpg"

export BROOS_CONSOLE_ROOT="$work/broos-console-theme/app"
export BROOS_CONSOLE_PREBUILT=yes
export BROOS_ARCHIVE_KEY_FILE="$work/public.gpg"
export BROOS_PACKAGE_OUTPUT="$work/packages"
export BROOS_RELEASE_CHANNEL=preview
"$work/broos-core/distribution/packaging/build-packages.sh" '0.1.0~preview1'
"$work/broos-core/distribution/packaging/build-packages.sh" '0.1.0~preview2'

export BROOS_APT_SIGNING_KEY="$fingerprint"
export BROOS_ARCHIVE_PUBLIC_KEY_FILE="$work/public.gpg"
"$publisher/publish-apt.sh" "$work/packages" "$work/apt-public"
gpgv --keyring "$work/public.gpg" "$work/apt-public/dists/preview/InRelease"
python3 "$publisher/azure-identity-publish.py" upload "$work/apt-public"
printf 'Published Broos preview versions 1 and 2 with key %s\n' "$fingerprint"
