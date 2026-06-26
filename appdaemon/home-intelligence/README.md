# Home Intelligence for AppDaemon

Home Intelligence is a portable AppDaemon app for Home Assistant. It watches high-signal entities, groups routine activity by area, and writes a concise household activity feed.

It is designed for homes where raw Home Assistant state changes are too noisy to follow directly. The app prefers Magic Areas aggregate/group entities when they exist, uses helper entities when you have already summarized something useful, and keeps critical safety or security entities as direct triggers.

## What It Does

- Discovers Magic Areas presence, occupancy, light, fan, and media groups.
- Falls back to direct lights, fans, media players, switches, covers, and locks when no group exists.
- Keeps critical raw sensors direct for leak, smoke, carbon monoxide, garage, door, water, and security events.
- Supports `input_text` media helpers such as "now playing" or "current show".
- Buffers routine room activity briefly so one area produces one useful message instead of a burst of entity logs.
- Writes a human-readable feed to `input_text.home_intelligence_feed`.
- Optionally writes status and structured JSON helpers.
- Sends notifications only for `ACTION` or `URGENT` events when notification services are configured.
- Uses person, area, and location helpers so Bermuda BLE or similar room-tracking sensors can add movement context.

## Folder Layout

```text
appdaemon/home-intelligence/
  README.md                      This guide
  appdaemon.yaml                 Example AppDaemon daemon config
  apps/apps.yaml                 Example AppDaemon app config
  apps/home_intelligence.py      Portable AppDaemon app
  docs/configuration.md          Configuration reference
  docs/triggers.md               Trigger strategy
  examples/explicit-triggers.apps.yaml
  home-assistant/helpers.yaml    Helper definitions
```

## Quick Install

1. Install AppDaemon for Home Assistant.
2. Copy [`apps/home_intelligence.py`](apps/home_intelligence.py) into your AppDaemon `apps/` folder.
3. Copy or merge [`apps/apps.yaml`](apps/apps.yaml) into your AppDaemon `apps.yaml`.
4. Create the Home Assistant helpers from [`home-assistant/helpers.yaml`](home-assistant/helpers.yaml).
5. Edit `apps.yaml` for your people, critical entities, openings, helpers, and notification services.
6. Restart AppDaemon.
7. Check the AppDaemon logs for `Home Intelligence initialized`.

If you run the official AppDaemon add-on, the runtime app folder is usually:

```text
/addon_configs/a0d7b954_appdaemon/apps
```

Inside the AppDaemon container it is usually:

```text
/config/apps
```

## Minimal Configuration

```yaml
home_intelligence:
  module: home_intelligence
  class: HomeIntelligence
  helpers:
    feed: input_text.home_intelligence_feed
    status: input_text.home_intelligence_status
    structured_json: input_text.home_intelligence_structured_json
```

## Recommended Configuration

```yaml
home_intelligence:
  module: home_intelligence
  class: HomeIntelligence

  people:
    - name: Alex
      person: person.alex
      area: sensor.alex_ble_area
      location: sensor.alex_location

  critical_entities:
    - binary_sensor.water_meter_high_flow
    - binary_sensor.laundry_room_leak
    - binary_sensor.garage_smoke_alarm

  opening_entities:
    - binary_sensor.front_door
    - cover.garage_door

  helper_entities:
    - sensor.activity_category
    - input_text.kitchen_now_playing

  helpers:
    feed: input_text.home_intelligence_feed
    status: input_text.home_intelligence_status
    structured_json: input_text.home_intelligence_structured_json

  notify_services:
    - notify.mobile_app_your_phone
```

## Trigger Strategy

Use this order:

1. Magic Areas groups and aggregates for routine area activity.
2. Curated helper entities for interpreted state.
3. Raw entities only for critical signals or when no aggregate exists.

That keeps routine light, media, and motion chatter from flooding the app while preserving important events that should never be hidden behind an aggregate.

See [`docs/triggers.md`](docs/triggers.md) for detailed examples.

## Notification Strategy

Home Intelligence has a simple hierarchy:

- `NORMAL`: ignored.
- `INFO`: written to dashboard helpers, often buffered into an area summary.
- `ACTION`: written to helpers and sent through `notify_services`.
- `URGENT`: reserved for higher-priority extensions and handled like `ACTION`.

See [`docs/notifications.md`](docs/notifications.md) for the full flow.

## Dashboard Summary

The quickest dashboard setup is a Markdown card:

```yaml
type: markdown
title: Home Intelligence
content: >
  **Latest:** {{ states('input_text.home_intelligence_feed') }}

  **Status:** {{ states('input_text.home_intelligence_status') }}
```

See [`docs/dashboard.md`](docs/dashboard.md) and [`../../homeassistant/lovelace/home_intelligence_summary.yaml`](../../homeassistant/lovelace/home_intelligence_summary.yaml).

## Context and Room Movement

If you use Bermuda BLE, add each person's room/area sensor under `people`. If you use Magic Areas, let Home Intelligence discover the aggregate area entities. Together they provide "who moved where" and "what changed in the room" without listening to every raw device.

See [`docs/context-and-ble.md`](docs/context-and-ble.md).

## Required Helpers

At minimum:

- `input_text.home_intelligence_feed`
- `input_text.home_intelligence_status`
- `input_text.home_intelligence_structured_json`

Use [`home-assistant/helpers.yaml`](home-assistant/helpers.yaml) as a starting point.

## More Documentation

- [`docs/configuration.md`](docs/configuration.md): configuration reference.
- [`docs/triggers.md`](docs/triggers.md): trigger design and examples.
- [`docs/notifications.md`](docs/notifications.md): severity hierarchy and notification routing.
- [`docs/dashboard.md`](docs/dashboard.md): Lovelace dashboard setup.
- [`docs/context-and-ble.md`](docs/context-and-ble.md): Magic Areas and Bermuda BLE context.
- [`examples/explicit-triggers.apps.yaml`](examples/explicit-triggers.apps.yaml): explicit trigger configuration.

## Notes

- Magic Areas is optional. If it is not installed, the app falls back to direct entity discovery.
- The app does not require cloud AI.
- Notifications are optional.
- Entity IDs in the examples are placeholders. Replace them with entities from your own Home Assistant instance.
