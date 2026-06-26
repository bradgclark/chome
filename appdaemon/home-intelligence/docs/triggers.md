# Defining Triggers

Home Intelligence works best when trigger sources are high signal.

## Preferred: Aggregates and Groups

If you use Magic Areas, let the app discover:

- `binary_sensor.magic_areas_presence_tracking_*_area_state`
- `binary_sensor.magic_areas_aggregates_*_aggregate_motion`
- `binary_sensor.magic_areas_aggregates_*_aggregate_occupancy`
- `light.magic_areas_light_groups_*_all_lights`
- `fan.magic_areas_fan_groups_*_fan_group`
- `media_player.magic_areas_media_player_groups_*_media_player_group`

These entities usually represent what happened in the room better than every individual sensor.

## Always Direct: Critical Entities

Keep these direct:

- leak/flood sensors
- smoke/CO/gas sensors
- water-flow alerts
- exterior doors
- garage doors
- locks
- pumps and appliance fault sensors

## Media Helpers

If you expose media state through helpers, use `input_text` entities with names like:

- `input_text.kitchen_now_playing`
- `input_text.living_room_current_show`
- `input_text.office_media_title`

The app will discover these when `discover_media_helpers` is enabled.

## People and BLE Area Helpers

If you use Bermuda BLE or another room-location system, add those sensors under `people` in `apps.yaml`:

```yaml
people:
  - name: Alex
    person: person.alex
    area: sensor.alex_ble_area
    location: sensor.alex_location
```

The `area` helper tells Home Intelligence where a person appears to be moving. Magic Areas aggregates then describe what is happening in that room.

## Fallback Raw Entities

When no aggregate exists for an area, the app can listen to raw lights, fans, media players, switches, covers, and locks.

## Practical Trigger Recipe

For the best signal:

1. Use Magic Areas aggregate/group entities for routine room state.
2. Add Bermuda BLE area helpers under `people` for movement context.
3. Add media `input_text` helpers for titles, shows, or songs.
4. List safety, security, water, garage, and important appliance alerts directly.
5. Avoid raw diagnostic entities such as RSSI, battery, firmware, uptime, and connectivity.
