# Configuration

Configuration lives in AppDaemon `apps.yaml`.

## Core Keys

`people`

Known people and optional location helpers.

```yaml
people:
  - name: Alex
    person: person.alex
    area: sensor.alex_ble_area
    location: sensor.alex_location
```

`critical_entities`

Entities that should be watched directly even when aggregates exist.

Good candidates:

- leak and flood sensors
- smoke and carbon monoxide sensors
- water-flow alerts
- garage doors
- exterior doors
- critical appliance or pump alerts

`opening_entities`

Door, window, mailbox, gate, and garage entities.

`helper_entities`

Curated status helpers such as `sensor.activity_category` or media `input_text` helpers.

`trigger_entities`

Manual override list. Use this sparingly.

## Controls

```yaml
controls:
  discover_magic_areas: true
  discover_area_devices: true
  discover_safety: true
  discover_media_helpers: true
  startup_settle_seconds: 90
  area_debounce_seconds: 90
  area_max_items: 20
  event_cooldown_seconds: 3
```

Disable discovery features if your installation has unusual entities or you want a fully explicit trigger list.
