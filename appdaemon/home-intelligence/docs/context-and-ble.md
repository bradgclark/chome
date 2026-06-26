# Context and Bermuda BLE

Home Intelligence becomes more useful when entity changes include area context. Magic Areas and Bermuda BLE are a strong combination for this.

## How Context Works

Every event is reduced to a small context object:

```json
{
  "severity": "INFO",
  "reason": "Presence",
  "summary": "Alex is active in Kitchen.",
  "entity": "binary_sensor.magic_areas_presence_tracking_kitchen_area_state",
  "area": "Kitchen"
}
```

The app uses that context to:

- remove noisy raw entity chatter
- group related events by area
- make summaries human-readable
- write structured JSON for dashboards or later automations
- decide whether a change should stay in the dashboard feed or notify people

## Magic Areas Context

If Magic Areas is installed, Home Intelligence prefers aggregate and group entities:

- area presence
- aggregate motion
- aggregate occupancy
- grouped lights
- grouped fans
- grouped media players

These are better context sources than every individual motion sensor, light, or media player because they represent "what happened in this room."

## Bermuda BLE Context

Bermuda BLE can provide room-level location context for people and devices. In Home Intelligence, add those room/area helpers to each person entry.

Example:

```yaml
people:
  - name: Alex
    person: person.alex
    area: sensor.alex_ble_area
    location: sensor.alex_location
```

Recommended helper pattern:

- `person`: Home Assistant person entity.
- `area`: Bermuda BLE room or area sensor.
- `location`: broader location sensor, if you have one.

When the BLE area sensor changes, Home Intelligence can include that person/location movement in the feed and structured JSON. When Magic Areas also reports room presence, the app can correlate movement with room activity.

## Example Movement Story

With BLE area helpers and Magic Areas aggregates, a normal sequence might look like:

```text
Alex BLE area changed to Kitchen.
Kitchen presence changed.
Kitchen lights changed.
Kitchen media title changed.
```

Instead of four separate noisy lines, Home Intelligence can publish a grouped dashboard summary like:

```text
Kitchen activity: presence and devices changed.
```

For a dashboard or later AI layer, the structured JSON still keeps the area, reason, entity, and severity available.

## Recommended Setup

1. Install and tune Bermuda BLE until each person has a reliable room/area sensor.
2. Install Magic Areas or create equivalent aggregate presence/occupancy helpers.
3. Add each person's `person`, `area`, and optional `location` entity in `apps.yaml`.
4. Prefer aggregate area entities for routine triggers.
5. Keep critical entities direct.

## Tips

- Use BLE area sensors for "who moved where."
- Use Magic Areas aggregates for "what happened in the room."
- Use media `input_text` helpers for "what is playing."
- Use direct safety sensors for "what needs attention."

That combination is the core idea: the app watches a house-level context layer instead of every raw device.
