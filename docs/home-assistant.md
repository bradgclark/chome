# Home Assistant Snippets

The `homeassistant/` folder contains reusable Home Assistant examples. Some are drop-in YAML files, and others are fragments meant to be pasted into a helper, template sensor, dashboard card, or package.

## Files

| File | Type | Purpose |
| --- | --- | --- |
| [`homeassistant/automation/shelly_detached_wall_switch_light_sync.yaml`](../homeassistant/automation/shelly_detached_wall_switch_light_sync.yaml) | Automation | Mirrors Shelly detached-mode wall switch entities to matching smart lights when `ha_availability` is on. |
| [`homeassistant/scripts/shelly_restart.yaml`](../homeassistant/scripts/shelly_restart.yaml) | Script | Finds Shelly restart button entities and presses each available one with a short delay. |
| [`homeassistant/template/home_activity_index.yaml`](../homeassistant/template/home_activity_index.yaml) | Template body | Calculates a 0-100 whole-home activity score from motion, openings, people, area presence, recent movement, and media playback. |
| [`homeassistant/template/home_activity_category.yaml`](../homeassistant/template/home_activity_category.yaml) | Template body | Converts `sensor.all_home_activity_index` into a friendly category such as Calm, Active, Busy, or Chaos. |
| [`homeassistant/lovelace/team_tracker.yaml`](../homeassistant/lovelace/team_tracker.yaml) | Lovelace card | Mushroom template card for a team tracker sensor with game state, score, TV network, and team-color styling. |

## Shelly Restart Script

Use this when you have the Shelly integration installed and want one Home Assistant script that restarts all Shelly devices exposing a restart button.

Install options:

1. If you use `scripts.yaml`, copy the script body into that file under a script key.
2. If you use a `scripts/` include directory, copy the file into that directory and reload scripts.
3. Run it from Developer Tools, an automation, or a dashboard button.

What to check:

- The script discovers entities from `integration_entities('shelly')`.
- It only presses `button.*_restart` entities that are not `unknown` or `unavailable`.
- It writes a warning-level system log entry listing the buttons it will press.

## Shelly Detached Wall Switch Sync

Use this with [`shelly/ha_availability.js`](../shelly/ha_availability.js) when Shelly relays run in detached mode while Home Assistant is online.

The automation maps wall switch entities to matching lights by entity ID:

```text
binary_sensor.<base>_wall_switch*  ->  light.<base>
switch.<base>_wall_switch*         ->  light.<base>
```

It only runs when the matching Shelly device exposes `switch.*_ha_availability` and that switch is `on`.

Full guide: [`docs/shelly-wall-switch-sync.md`](shelly-wall-switch-sync.md)

## Activity Index Templates

The activity templates are meant to become template sensors.

The index template:

- Counts motion and occupancy sensors.
- Counts open or recently changed doors, windows, and openings.
- Counts people currently home.
- Counts area presence sensors matching `binary_sensor.<area>_presence`.
- Adds recent movement and active media playback.
- Produces a normalized score from `0` to `100`.

The category template expects the index sensor to be named:

```yaml
sensor.all_home_activity_index
```

If your index sensor has a different entity ID, update this line in `home_activity_category.yaml`:

```jinja
{% set idx = states('sensor.all_home_activity_index') | int(0) %}
```

Example package shape:

```yaml
template:
  - sensor:
      - name: All Home Activity Index
        unique_id: all_home_activity_index
        state: >-
          # Paste the contents of home_activity_index.yaml here.

      - name: Home Activity Category
        unique_id: home_activity_category
        state: >-
          # Paste the contents of home_activity_category.yaml here.
```

After adding template sensors, reload template entities or restart Home Assistant.

## Team Tracker Lovelace Card

The team tracker card is a dashboard card example, not an automation.

It expects:

- A Team Tracker-style sensor with attributes like `team_name`, `opponent_name`, `team_score`, `opponent_score`, `team_logo`, and `opponent_logo`.
- Mushroom cards installed.
- card-mod installed if you want the included team-color background styling.

Before use:

1. Replace the `entity:` value with your team tracker sensor.
2. Adjust icons, colors, and fallback colors as needed.
3. Paste the YAML into a manual Lovelace card.

## General Import Notes

- Keep entity IDs local to your home.
- Reload the relevant Home Assistant domain after adding snippets.
- Watch Home Assistant logs after the first reload.
- If a template returns `unknown`, test it in Developer Tools > Template before putting it on a dashboard.
