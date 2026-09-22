# Broos-owned distribution and updates

## Decision

Broos Cloud ships as Broos packages from Broos infrastructure. A customer host does not subscribe to Virtualmin release channels and the console never invokes Virtualmin's repository configurator. Virtualmin and Webmin become vendored, tested runtime dependencies within the Broos release train.

This changes ownership of delivery, not the licenses of included software. GPL source offers, notices and corresponding source remain part of every applicable release.

## Public endpoints

| Endpoint | Purpose |
| --- | --- |
| `https://packages.broos.app/apt` | Signed Debian/Ubuntu package repository |
| `https://packages.broos.app/keys/archive.gpg` | Broos archive public key |
| `https://packages.broos.app/v1/channels/{channel}.json` | Signed release metadata |
| `https://packages.broos.app/v1/releases/{version}/` | Changelog, SBOM, provenance and source offer |
| `https://broos.app/status` | Delivery and platform status |

The production key is kept in an offline or hardware-backed signing environment. CI creates artifacts and provenance but cannot publish a stable release without a protected approval and signing job.

## Package model

- `broos-release`: repository key, source configuration, updater command and systemd timer
- `broos-core`: gateway, Webmin module, adapters, migrations and job runner
- `broos-console`: built static console assets
- `broos-agent`: optional multi-host agent introduced later
- `broos-virtualmin-compat`: pinned compatible Virtualmin/Webmin packages and Broos patches
- `broos-source-offer`: machine-readable links to corresponding GPL source

Packages use standard APT dependency resolution. Repository metadata is published as a signed `InRelease`; each source entry is restricted with `Signed-By=/usr/share/keyrings/broos-archive-keyring.gpg`. APT's global trusted keyring is not modified.

## Channels

| Channel | Audience | Promotion rule |
| --- | --- | --- |
| `edge` | Broos developers | Every passing main build |
| `preview` | Internal and opted-in pilots | Integration, upgrade and rollback suites pass |
| `stable` | Customer production | Staged rollout approved after preview soak |

A release is promoted by moving signed metadata to the next channel. Artifacts are immutable and are never rebuilt between channels.

## Update lifecycle

1. The timer checks metadata without making changes.
2. The updater verifies APT signatures, release compatibility, disk space and service health.
3. It creates configuration/database backups and records the installed package set.
4. It downloads all packages before entering the maintenance window.
5. It installs packages, runs idempotent migrations and restarts only affected services.
6. Health gates test the Broos API, web, DNS, mail, database and configured customer probes.
7. On failure, packages and configuration are rolled back and the release is quarantined for that host.
8. The audit log records the actor, channel, versions, checks and outcome.

No unattended major-version upgrade is allowed. Security patches may use an accelerated rollout but still require signature verification, backup and health gates.

## Upstream intake

An automated job watches Webmin, Virtualmin GPL and Authentic releases. A bot opens an intake pull request containing upstream commits, license changes, CVE notes and compatibility results. Broos maintainers decide whether to accept and promote it. Production hosts never run upstream self-update functions.

## First supported platform

- Ubuntu 24.04 LTS, amd64 and arm64
- Debian 12 support after the Ubuntu release train is stable
- Ubuntu 22.04 receives migration support, not indefinite new-feature support

## Migration from current installs

1. Inventory installed packages, repositories, versions and local modifications.
2. Back up `/etc/webmin`, `/etc/virtualmin`, service configuration, databases and domain metadata.
3. Install `broos-release` and the pinned Broos compatibility package.
4. Disable upstream theme self-update and Virtualmin direct repository switching.
5. Run a no-change compatibility scan.
6. Enrol the host into `preview`, complete one successful update and rollback exercise.
7. Promote the host to `stable`.

This migration must be tested on a clone before production. The current production VM is not changed by this repository scaffold.

## Release gates

- Reproducible package build and dependency lock
- Unit, API contract and upgrade-path tests
- Clean installation test on every supported OS/architecture
- Upgrade from the two previous stable releases
- Backup restoration and forced rollback test
- SBOM, vulnerability scan and malware scan
- License manifest and corresponding-source verification
- Signed provenance and repository metadata
- Console accessibility and browser smoke tests

## Deprecating legacy update paths

Legacy Virtualmin/Authentic update code remains untouched during the bootstrap phase. Once `broos-release` is proven, packaging applies policy files that hide or block direct upstream update actions and explains that updates are managed by Broos. Removing upstream code directly would make future merges unnecessarily difficult.
