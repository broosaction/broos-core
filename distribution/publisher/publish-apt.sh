#!/bin/sh
set -eu

PACKAGES_DIR=${1:-}
REPOSITORY_DIR=${2:-}
SUITE=${BROOS_RELEASE_CHANNEL:-stable}
COMPONENT=main
ORIGIN=Broos
LABEL='Broos Cloud'
SIGNING_KEY=${BROOS_APT_SIGNING_KEY:-}
PUBLIC_KEY=${BROOS_ARCHIVE_PUBLIC_KEY_FILE:-}

fail() { printf 'publish-apt: error: %s\n' "$*" >&2; exit 1; }
[ -d "$PACKAGES_DIR" ] || fail 'usage: publish-apt.sh PACKAGE_DIRECTORY REPOSITORY_DIRECTORY'
[ -n "$REPOSITORY_DIR" ] || fail 'repository directory is required'
[ -n "$SIGNING_KEY" ] || fail 'BROOS_APT_SIGNING_KEY must contain the signing key fingerprint'
[ -n "$PUBLIC_KEY" ] && [ -s "$PUBLIC_KEY" ] ||
  fail 'BROOS_ARCHIVE_PUBLIC_KEY_FILE must point to the exported public key'
case "$SUITE" in stable|preview|edge) ;; *) fail "invalid channel: $SUITE" ;; esac
for command in apt-ftparchive dpkg-deb gpg rsync; do command -v "$command" >/dev/null 2>&1 || fail "$command is required"; done
set -- "$PACKAGES_DIR"/*.deb
[ -f "$1" ] || fail 'no .deb packages found'
for package in "$@"; do
  [ "$(dpkg-deb -f "$package" Architecture)" = all ] ||
    fail "only Architecture: all packages are supported in this preview publisher: $package"
done
actual_fingerprint=$(gpg --batch --show-keys --with-colons "$PUBLIC_KEY" |
  awk -F: '$1 == "fpr" { print $10; exit }')
[ "$actual_fingerprint" = "$SIGNING_KEY" ] ||
  fail 'public key fingerprint does not match BROOS_APT_SIGNING_KEY'

stage=$(mktemp -d "${TMPDIR:-/tmp}/broos-apt.XXXXXX")
trap 'rm -rf "$stage"' EXIT HUP INT TERM
pool=$stage/pool/$SUITE/$COMPONENT
install -d "$pool"
cp "$PACKAGES_DIR"/*.deb "$pool/"

for arch in amd64 arm64; do
  binary=$stage/dists/$SUITE/$COMPONENT/binary-$arch
  install -d "$binary"
  (cd "$stage" && apt-ftparchive packages "pool/$SUITE/$COMPONENT" > "dists/$SUITE/$COMPONENT/binary-$arch/Packages")
  gzip -9 -k "$binary/Packages"
done
cat > "$stage/release.conf" <<EOF
APT::FTPArchive::Release::Origin "$ORIGIN";
APT::FTPArchive::Release::Label "$LABEL";
APT::FTPArchive::Release::Suite "$SUITE";
APT::FTPArchive::Release::Codename "$SUITE";
APT::FTPArchive::Release::Architectures "amd64 arm64";
APT::FTPArchive::Release::Components "$COMPONENT";
APT::FTPArchive::Release::Description "Broos Cloud $SUITE packages";
EOF
(cd "$stage" && apt-ftparchive -c release.conf release "dists/$SUITE" > "dists/$SUITE/Release")
gpg --batch --yes --local-user "$SIGNING_KEY" --clearsign \
  --output "$stage/dists/$SUITE/InRelease" "$stage/dists/$SUITE/Release"
gpg --batch --yes --local-user "$SIGNING_KEY" --armor --detach-sign \
  --output "$stage/dists/$SUITE/Release.gpg" "$stage/dists/$SUITE/Release"

install -d "$REPOSITORY_DIR/pool/$SUITE/$COMPONENT" "$REPOSITORY_DIR/dists/$SUITE" "$REPOSITORY_DIR/keys"
# Publish immutable package payloads before switching the signed index. Never
# delete another release channel or the public key while updating one suite.
rsync -a "$pool/" "$REPOSITORY_DIR/pool/$SUITE/$COMPONENT/"
rsync -a --delete "$stage/dists/$SUITE/" "$REPOSITORY_DIR/dists/$SUITE/"
install -m 0644 "$PUBLIC_KEY" "$REPOSITORY_DIR/keys/archive.gpg.new"
mv "$REPOSITORY_DIR/keys/archive.gpg.new" "$REPOSITORY_DIR/keys/archive.gpg"
printf 'Published signed %s repository to %s\n' "$SUITE" "$REPOSITORY_DIR"
