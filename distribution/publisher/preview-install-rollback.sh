#!/bin/bash
set -euo pipefail

repo=https://packages.broos.app/apt
key=/usr/share/keyrings/broos-archive-keyring.gpg
source_file=/etc/apt/sources.list.d/broos-preview-test.list

curl --fail --silent --show-error --location "$repo/keys/archive.gpg" -o "$key"
curl --fail --silent --show-error --location "$repo/dists/preview/InRelease" \
  -o /tmp/broos-preview-InRelease
gpgv --keyring "$key" /tmp/broos-preview-InRelease
printf 'deb [signed-by=%s] %s preview main\n' "$key" "$repo" > "$source_file"
apt-get update -o Dir::Etc::sourcelist="$source_file" \
  -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0

apt-get install -y 'broos-release=0.1.0~preview1' 'broos-console=0.1.0~preview1'
test -s /usr/share/broos-console/index.html
test "$(dpkg-query -W -f='${Version}' broos-release)" = '0.1.0~preview1'
broos-release check
broos-release apply
test "$(dpkg-query -W -f='${Version}' broos-release)" = '0.1.0~preview2'
test "$(dpkg-query -W -f='${Version}' broos-console)" = '0.1.0~preview2'
broos-release rollback
test "$(dpkg-query -W -f='${Version}' broos-release)" = '0.1.0~preview1'
test "$(dpkg-query -W -f='${Version}' broos-console)" = '0.1.0~preview1'
printf 'Signed HTTPS installation, update, health gate and rollback all passed\n'
