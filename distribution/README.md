# Broos distribution scaffold

This directory contains the host-side contract for Broos-owned releases. It is not a production package yet.

- `broos-release`: updater command prototype
- `broos-release.conf`: default policy
- `broos-update.service`: one-shot update service
- `broos-update.timer`: randomized update check timer
- `broos.sources`: deb822 APT source template
- `packaging/build-packages.sh`: reproducible Debian package builder
- `publisher/publish-apt.sh`: atomic, signed APT repository publisher
- `lib/broos-snapshot`: package/configuration snapshot and restore helper
- `lib/broos-healthcheck`: post-update health gate

Package installation paths:

```text
/usr/bin/broos-release
/etc/broos/release.conf
/etc/apt/sources.list.d/broos.sources
/usr/share/keyrings/broos-archive-keyring.gpg
/usr/lib/systemd/system/broos-update.service
/usr/lib/systemd/system/broos-update.timer
/var/lib/broos-release/
```

Before shipping, replace `BROOS_ARCHIVE_KEY_FINGERPRINT` and publish a real signed repository. Never add a `trusted=yes` bypass.

## Build packages

Run on Ubuntu with `dpkg-dev`, Node.js and npm installed:

```bash
export BROOS_ARCHIVE_KEY_FILE=/secure/path/to/broos-archive-public.gpg
export BROOS_RELEASE_CHANNEL=preview
./distribution/packaging/build-packages.sh 0.1.0
```

By default, the console repository is expected beside this repository at `../broos-console-theme/app`. Override it with `BROOS_CONSOLE_ROOT`.

## Publish a repository

Use a dedicated, protected signing environment with `apt-utils`, GnuPG and rsync:

```bash
export BROOS_APT_SIGNING_KEY='<full signing-key fingerprint>'
export BROOS_ARCHIVE_PUBLIC_KEY_FILE=/secure/path/to/broos-archive-public.gpg
export BROOS_RELEASE_CHANNEL=preview
./distribution/publisher/publish-apt.sh build/packages build/apt-public
```

Upload `build/apt-public/` to the `/apt` origin for `packages.broos.app` only after signature verification in a separate job. The private key must never be stored in either repository or ordinary CI artifacts.

## Rollback scope

Before installation, the updater caches the exact installed Broos/Webmin/Virtualmin packages and archives configuration under `/var/lib/broos-release/snapshots`. A failed install or health check restores that snapshot automatically. Customer files, mail and databases remain covered by the server backup policy; future schema-changing Broos Core migrations must register their own transactional backup and downgrade handler.
