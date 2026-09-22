#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
CONSOLE_ROOT=${BROOS_CONSOLE_ROOT:-$(dirname "$ROOT")/broos-console-theme/app}
VERSION=${1:-0.1.0}
ARCH=${BROOS_PACKAGE_ARCH:-all}
CHANNEL=${BROOS_RELEASE_CHANNEL:-preview}
ARCHIVE_KEY=${BROOS_ARCHIVE_KEY_FILE:-}
OUT=${BROOS_PACKAGE_OUTPUT:-$ROOT/build/packages}
WORK=$ROOT/build/package-work

command -v dpkg-deb >/dev/null 2>&1 || { echo 'dpkg-deb is required' >&2; exit 1; }
case "$VERSION" in *[!0-9A-Za-z.+:~-]*|'') echo 'invalid Debian version' >&2; exit 1 ;; esac
case "$CHANNEL" in stable|preview|edge) ;; *) echo 'invalid release channel' >&2; exit 1 ;; esac
[ -n "$ARCHIVE_KEY" ] && [ -s "$ARCHIVE_KEY" ] || {
  echo 'BROOS_ARCHIVE_KEY_FILE must point to the exported public archive key' >&2; exit 1;
}
rm -rf "$WORK"
install -d "$WORK" "$OUT"

control_file() {
  package=$1 description=$2 destination=$3 dependencies=${4:-}
  install -d "$destination/DEBIAN"
  cat > "$destination/DEBIAN/control" <<EOF
Package: $package
Version: $VERSION
Section: admin
Priority: optional
Architecture: $ARCH
Maintainer: Broos Action <opensource@broos.app>
Homepage: https://broos.app
Description: $description
EOF
  [ -z "$dependencies" ] || printf 'Depends: %s\n' "$dependencies" >> "$destination/DEBIAN/control"
}

release=$WORK/broos-release
control_file broos-release 'Broos Cloud signed repository and safe update controller' "$release" \
  'apt, ca-certificates, curl, systemd, tar, util-linux'
install -d "$release/usr/bin" "$release/usr/lib/broos-release" "$release/etc/broos" \
  "$release/etc/apt/sources.list.d" "$release/usr/lib/systemd/system" \
  "$release/usr/share/keyrings"
install -m 0755 "$ROOT/distribution/broos-release" "$release/usr/bin/broos-release"
install -m 0755 "$ROOT/distribution/lib/broos-snapshot" "$release/usr/lib/broos-release/broos-snapshot"
install -m 0755 "$ROOT/distribution/lib/broos-healthcheck" "$release/usr/lib/broos-release/broos-healthcheck"
install -m 0644 "$ROOT/distribution/broos-release.conf" "$release/etc/broos/release.conf"
install -m 0644 "$ROOT/distribution/broos.sources" "$release/etc/apt/sources.list.d/broos.sources"
install -m 0644 "$ARCHIVE_KEY" "$release/usr/share/keyrings/broos-archive-keyring.gpg"
sed -i "s/^CHANNEL=.*/CHANNEL=$CHANNEL/" "$release/etc/broos/release.conf"
sed -i "s/^Suites:.*/Suites: $CHANNEL/" "$release/etc/apt/sources.list.d/broos.sources"
install -m 0644 "$ROOT/distribution/broos-update.service" "$release/usr/lib/systemd/system/broos-update.service"
install -m 0644 "$ROOT/distribution/broos-update.timer" "$release/usr/lib/systemd/system/broos-update.timer"
cat > "$release/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
systemctl daemon-reload 2>/dev/null || true
systemctl enable broos-update.timer 2>/dev/null || true
exit 0
EOF
chmod 0755 "$release/DEBIAN/postinst"
dpkg-deb --root-owner-group --build "$release" "$OUT/broos-release_${VERSION}_${ARCH}.deb"

[ -f "$CONSOLE_ROOT/package-lock.json" ] || { echo "console not found: $CONSOLE_ROOT" >&2; exit 1; }
if [ "${BROOS_CONSOLE_PREBUILT:-no}" != yes ]; then
  (cd "$CONSOLE_ROOT" && npm ci && npm run build)
fi
[ -s "$CONSOLE_ROOT/dist/index.html" ] || { echo 'console build is missing dist/index.html' >&2; exit 1; }
console=$WORK/broos-console
control_file broos-console 'Broos Cloud responsive management console' "$console"
install -d "$console/usr/share/broos-console"
cp -R "$CONSOLE_ROOT/dist/." "$console/usr/share/broos-console/"
printf 'ok\n' > "$console/usr/share/broos-console/healthz"
dpkg-deb --root-owner-group --build "$console" "$OUT/broos-console_${VERSION}_${ARCH}.deb"

sha256sum "$OUT"/*.deb > "$OUT/SHA256SUMS"
echo "Packages written to $OUT"
