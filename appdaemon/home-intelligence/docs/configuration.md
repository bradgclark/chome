# Configuration

Configuration lives in AppDaemon `apps.yaml`.

## Core Keys

`people`

Known people and optional room/location helpers. This is where Bermuda BLE or similar area sensors fit.

```yaml
people:
  - name: Alex
    person: person.alex
    area: sensor.alex_ble_area
    location: sensor.alex_location
```

`person` should be the Home Assistant person entity. `area` should be a room-level helper such as a Bermuda BLE area sensor. `location` can be a broader location helper if you have one.

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

## Helpers

Home Intelligence writes to `input_text` helpers.

```yaml
helpers:
  feed: input_text.home_intelligence_feed
  status: input_text.home_intelligence_status
  structured_json: input_text.home_intelligence_structured_json
```

`feed` is the dashboard-friendly summary. `status` shows runtime health such as listener count. `structured_json` stores a compact payload with severity, reason, summary, entity, and area.

## Notifications

Notifications are optional. Add Home Assistant notify services when you want `ACTION` or `URGENT` events to push somewhere.

```yaml
notify_services:
  - notify.mobile_app_your_phone
```

Routine `INFO` events stay in the feed and dashboard helpers. Safety-style active events become `ACTION` and call the configured services.

See [`notifications.md`](notifications.md).
