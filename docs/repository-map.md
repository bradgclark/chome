# Repository Map

This repository is organized by runtime target.

## AppDaemon

Path: [`appdaemon/`](../appdaemon/)

Contains files that belong in an AppDaemon configuration directory.

Current package:

- [`appdaemon/home-intelligence/`](../appdaemon/home-intelligence/): portable Home Intelligence AppDaemon app and example configuration.

## Home Intelligence

Path: [`appdaemon/home-intelligence/`](../appdaemon/home-intelligence/)

Contains the public documentation, examples, and Home Assistant helper definitions for the Home Intelligence app.

Read this first if you want to install the AppDaemon app in another Home Assistant instance:

- [`appdaemon/home-intelligence/README.md`](../appdaemon/home-intelligence/README.md)

## Home Assistant

Path: [`homeassistant/`](../homeassistant/)

Contains Home Assistant examples that can be copied into dashboards, scripts, packages, or template sensors.
Automation examples live under `homeassistant/automation/`.

Guide:

- [`docs/home-assistant.md`](home-assistant.md)

## Shelly

Path: [`shelly/`](../shelly/)

Contains JavaScript intended to run on Shelly devices.

Guide:

- [`docs/shelly.md`](shelly.md)

## Scripts

Path: [`scripts/`](../scripts/)

Standalone operations scripts.

- [`scripts/datacenter-upgrade.sh`](../scripts/datacenter-upgrade.sh): guarded Proxmox cluster and guest updater (read-only unless `--apply`).
- [`scripts/check-public.sh`](../scripts/check-public.sh): fails if a tracked file carries a private IP, an email address or, when `PRIVATE_PATTERNS` is set, a household's own names. CI runs it on every pull request.

## Infrastructure

Path: [`infrastructure/`](../infrastructure/)

Deployment notes for self-hosted services, one folder per service with a compose file and README.

- [`infrastructure/uptime-kuma/`](../infrastructure/uptime-kuma/)
