#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

root=/tmp/broos-core
work=$(mktemp -d /tmp/broos-local-smoke.XXXXXX)
chmod 0755 "$work"
console=/tmp/broos-console-theme/app
install -d -m 0700 "$work/gnupg"
export GNUPGHOME="$work/gnupg"
gpg --batch --pinentry-mode loopback --passphrase '' \
  --quick-generate-key 'Broos Local Test <local-test@broos.app>' ed25519 sign 1d
fingerprint=$(gpg --batch --with-colons --list-secret-keys |
  awk -F: '$1 == "fpr" { print $10; exit }')
gpg --batch --export "$fingerprint" > "$work/public.gpg"

export BROOS_CONSOLE_ROOT="$console"
export BROOS_CONSOLE_PREBUILT=yes
export BROOS_ARCHIVE_KEY_FILE="$work/public.gpg"
export BROOS_PACKAGE_OUTPUT="$work/packages"
export BROOS_RELEASE_CHANNEL=preview
"$root/distribution/packaging/build-packages.sh" '0.1.0~preview1'
"$root/distribution/packaging/build-packages.sh" '0.1.0~preview2'

export BROOS_APT_SIGNING_KEY="$fingerprint"
export BROOS_ARCHIVE_PUBLIC_KEY_FILE="$work/public.gpg"
"$root/distribution/publisher/publish-apt.sh" "$work/packages" "$work/apt-public"
gpgv --keyring "$work/public.gpg" "$work/apt-public/dists/preview/InRelease"
unset BROOS_CONSOLE_ROOT BROOS_CONSOLE_PREBUILT BROOS_PACKAGE_OUTPUT

install -m 0644 "$work/public.gpg" /usr/share/keyrings/broos-archive-keyring.gpg
if [ -f /etc/apt/sources.list.d/broos.sources ]; then
  sed -i "s#^URIs:.*#URIs: file://$work/apt-public#" /etc/apt/sources.list.d/broos.sources
  rm -f /etc/apt/sources.list.d/broos-local-test.list
else
  printf 'deb [signed-by=/usr/share/keyrings/broos-archive-keyring.gpg] file://%s preview main\n' \
    "$work/apt-public" > /etc/apt/sources.list.d/broos-local-test.list
fi
apt-get update -qq
apt-get install -y --reinstall 'broos-release=0.1.0~preview1' 'broos-console=0.1.0~preview1'
sed -i "s#^URIs:.*#URIs: file://$work/apt-public#" /etc/apt/sources.list.d/broos.sources
rm -f /etc/apt/sources.list.d/broos-local-test.list
broos-release check
broos-release apply
test "$(dpkg-query -W -f='${Version}' broos-release)" = '0.1.0~preview2'
test "$(dpkg-query -W -f='${Version}' broos-console)" = '0.1.0~preview2'
broos-release rollback
test "$(dpkg-query -W -f='${Version}' broos-release)" = '0.1.0~preview1'
test "$(dpkg-query -W -f='${Version}' broos-console)" = '0.1.0~preview1'
printf 'Local Ubuntu signed install, upgrade and rollback passed\n'
