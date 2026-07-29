# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repository Is

CHOME is a **public** collection of sanitized, portable building blocks from a private smart home: an AppDaemon app, Home Assistant YAML snippets, Shelly device scripts, and Proxmox/infrastructure operations tooling. It is not a deployable application with a single build/test pipeline — it is organized by runtime target, and each piece is meant to be copied into someone else's Home Assistant / AppDaemon / Shelly / Proxmox setup.

Because the repo is public, everything committed here must be a **sanitized example**, not a real household export:
- No real entity IDs tied to a private install beyond illustrative placeholders (`person.alex`, `binary_sensor.front_door`, etc.).
- No private household configuration — that lives in separate, non-public repos (`haos-config`, `esphome-config`).
- No credentials, API keys, or admin secrets (see `infrastructure/uptime-kuma/README.md` for the pattern: secrets are documented as living outside the repo, e.g. `~/.config/uptime-kuma/admin.env`).

## Repository Layout (by runtime target)

```text
appdaemon/home-intelligence/   Portable AppDaemon app + docs/examples/helpers (Python)
homeassistant/                 Home Assistant automation/script/template/lovelace YAML snippets
shelly/                        JavaScript that runs on Shelly Gen2/Plus/Pro devices, not in HA
scripts/                       Standalone ops scripts (currently: Proxmox datacenter updater)
infrastructure/                Deployment notes for self-hosted services (compose + README per service)
docs/                          Cross-cutting guides that tie the above pieces together
```

`docs/repository-map.md` is the maintained index of what lives where — check it (and the top-level `README.md`) before adding a new top-level area, and update both if you add one.

## Key Architecture: Home Intelligence (AppDaemon app)

`appdaemon/home-intelligence/apps/home_intelligence.py` is the one nontrivial piece of code in the repo. Understanding it requires reading the whole file plus `docs/triggers.md` and `docs/notifications.md`, since the design intent is spread across both. The core ideas:

1. **Trigger discovery hierarchy** (`configured_triggers` + `discovered_triggers`, preferred order): Magic Areas aggregate/group entities first (`discover_magic_area_entities`) → curated helper entities the user configured → raw per-device entities only as a fallback or for safety-critical classes (`discover_safety_entities`). `discover_area_action_entities` deliberately drops a raw light/fan/media/presence entity when a Magic Areas aggregate already covers that area+category (`is_redundant_raw_area_entity`), to avoid duplicate noise from both the aggregate and the raw entity.
2. **Severity hierarchy**: every event is triaged (`triage_event`) into `NORMAL` (dropped), `INFO` (written to the feed, often buffered), or `ACTION`/`URGENT` (written to the feed **and** pushed through `notify_services`). Safety events (leak/smoke/CO/gas device classes) always trigger regardless of area buffering.
3. **Area buffering**: routine `INFO` events for a given area are batched (`buffer_area_event`) and flushed as one summary after `area_debounce_seconds` (`flush_area_buffer` → `summarize_area_bucket`), so one busy room produces one feed line instead of a burst.
4. **Output**: results are written to `input_text` helpers (`feed`, `status`, `structured_json`), truncated to 255 chars (the HA `input_text` max). There is no database — state lives only in the configured helpers and in-memory buffers.

When editing this app, keep it dependency-free beyond `appdaemon.plugins.hass.hassapi` (no external Magic Areas/Bermuda Python packages) — portability to a plain AppDaemon + optional-Magic-Areas install is the point.

## Home Assistant / Shelly Naming Conventions

Several automations and scripts rely on **entity-ID naming patterns** instead of explicit config, so preserve these patterns when adding related snippets:

- Magic Areas: `binary_sensor.magic_areas_presence_tracking_<area>_area_state`, `binary_sensor.magic_areas_aggregates_<area>_aggregate_{motion,occupancy}`, `light.magic_areas_light_groups_<area>_all_lights`, `fan.magic_areas_fan_groups_<area>_fan_group`, `media_player.magic_areas_media_player_groups_<area>_media_player_group`.
- Detached wall switch sync (`homeassistant/automation/shelly_detached_wall_switch_light_sync.yaml` + `shelly/ha_availability.js`): `(binary_sensor|switch).<base>_wall_switch*` mirrors to `light.<base>`, gated on a same-device `switch.*_ha_availability` entity being `on`.

If you add a new snippet that depends on a naming convention, document the pattern explicitly in its docs file the way `docs/shelly-wall-switch-sync.md` and `docs/home-assistant.md` do — these files are the install guide for someone with a different entity naming scheme.

## Proxmox Datacenter Updater (`scripts/datacenter-upgrade.sh`)

A single guarded Bash script that updates the 3-node `chome` Proxmox cluster (`pve1`, `pve2`, `pve3`) and its guests. Conventions to preserve when touching it:

- `set -Eeuo pipefail` + `shopt -s inherit_errexit`; every remote action goes through `node_run`/`node_capture`, which SSHes to other nodes but runs locally when `$CURRENT_NODE` matches, so new logic should be written host-agnostically through those wrappers.
- **Read-only unless `--apply`** — every mutating code path is written to also have a safe/reporting branch when `$APPLY` is false. Preserve this dual-path style for any new phase.
- Mutating phases are gated on cluster quorum, per-node preflight (disk space, failed systemd units, storage), and a recent-backup check per non-template guest (`assert_recent_backups`) — don't bypass these gates silently.
- Per-application update functions (`omada_update`, `nextcloud_update`, `ollama_update`, `frigate_update`, `haos_update`) are dispatched by hardcoded Proxmox `vmid` in `upgrade_apps`/`upgrade_guests`. `generic_app_update` is the fallback for any LXC exposing `/usr/bin/update`. `APP_MIN_MEMORY_MB` gates memory-sensitive app containers before upgrading.
- Inline `# shellcheck disable=SC...` comments with a one-line justification are the established pattern for intentional shellcheck exceptions (e.g. deferred remote-shell expansion) — keep using that pattern rather than disabling checks file-wide.

## Verification (there is no CI or test suite)

This repo has no package manager, build step, or automated test suite. Verify changes with the tooling that matches the file type instead:

- **Bash** (`scripts/*.sh`): `bash -n <file>` for a syntax check at minimum; run `shellcheck <file>` if it's available locally — the script is written to be shellcheck-clean, with explicit disable comments where an exception is intentional.
- **Python** (`appdaemon/home-intelligence/apps/home_intelligence.py`): `python3 -m py_compile <file>` for a syntax check. There's no AppDaemon test harness in this repo, so logic changes to the trigger/triage flow should be reasoned through by hand against `docs/triggers.md` and `docs/notifications.md`.
- **Home Assistant YAML** (`homeassistant/**`, `appdaemon/home-intelligence/home-assistant/helpers.yaml`, `apps.yaml`): these are meant to be pasted into a real HA config and validated there (Developer Tools → YAML/Template, then reload the relevant domain). There's no local HA instance in this repo to validate against.
- **Shelly JS** (`shelly/*.js`): validated on-device via the Shelly script editor/logs, not locally.

## Documentation Conventions

Every functional area has a paired guide, and the docs consistently link back to the exact files they describe (see `docs/repository-map.md`, `docs/home-assistant.md`, `docs/shelly.md`). When adding a new snippet or script:
- Add or update the matching doc under `docs/` (or `appdaemon/home-intelligence/docs/` for Home Intelligence–specific docs) with what it does, required entities/naming pattern, and install steps.
- Update the file table in the nearest parent README (`README.md`, `appdaemon/home-intelligence/README.md`, or `docs/home-assistant.md`) so the index stays accurate.
- Treat entity IDs and URLs in examples as placeholders to be replaced by the person installing them — don't hardcode this household's real values.
