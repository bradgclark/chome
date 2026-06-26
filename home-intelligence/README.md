# Home Intelligence for AppDaemon

Portable Home Intelligence is an AppDaemon app for Home Assistant. It watches high-signal entities, groups routine activity by area, and writes a concise feed helper. It prefers Magic Areas aggregates/groups when present, while keeping raw critical sensors such as leak, smoke, garage, door, and water-flow entities as direct triggers.

## What It Does

- Discovers Magic Areas presence, occupancy, light, fan, and media groups.
- Falls back to real lights, fans, media players, switches, covers, and locks when no group exists.
- Keeps critical raw sensors direct.
- Supports `input_text` media helpers such as "now playing" or "current show".
- Buffers routine room activity briefly so one area produces one useful message instead of a burst of entity logs.
- Writes a human-readable feed to `input_text.home_intelligence_feed`.

## Install

1. Install AppDaemon in Home Assistant.
2. Copy `appdaemon/home-intelligence/apps/home_intelligence.py` into your AppDaemon `apps/` folder.
3. Copy or merge `appdaemon/home-intelligence/apps/apps.yaml` into your AppDaemon `apps.yaml`.
4. Create the Home Assistant helpers from `home-intelligence/home-assistant/helpers.yaml`.
5. Restart AppDaemon.

If you run the official AppDaemon add-on, the runtime app folder is usually:

```text
/addon_configs/a0d7b954_appdaemon/apps
```

In the AppDaemon container it is usually:

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

Add known people, critical sensors, and important openings:

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

Raw critical entities should include safety, security, water, garage, and important appliance states. Routine light/media/motion chatter is better represented by aggregate entities.

## Required Helpers

See `home-intelligence/home-assistant/helpers.yaml`.

At minimum:

- `input_text.home_intelligence_feed`
- `input_text.home_intelligence_status`
- `input_text.home_intelligence_structured_json`

## Notes

- Magic Areas is optional. If it is not installed, the app falls back to direct entity discovery.
- The app does not require cloud AI.
- Notifications are optional and only used for `ACTION` or `URGENT` events.
