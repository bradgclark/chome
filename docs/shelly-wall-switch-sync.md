# Shelly Detached Wall Switch Light Sync

This Home Assistant automation pairs with [`shelly/ha_availability.js`](../shelly/ha_availability.js).

Use it when a Shelly relay is normally in detached mode so Home Assistant controls smart bulbs, but the relay can fall back to direct physical control when Home Assistant is unavailable.

## What It Does

The automation listens for wall switch entities whose entity ID contains `_wall_switch`.

When the wall switch changes between `on` and `off`, it:

1. Derives the matching light entity from the wall switch entity ID.
2. Confirms that light exists.
3. Finds the Shelly device's `switch.*_ha_availability` entity.
4. Runs only when that availability switch is `on`.
5. Turns the matching light on or off.

## Naming Convention

The automation expects this pattern:

```text
binary_sensor.<base>_wall_switch*  ->  light.<base>
switch.<base>_wall_switch*         ->  light.<base>
```

Examples:

| Wall switch entity | Controlled light |
| --- | --- |
| `binary_sensor.kitchen_ceiling_wall_switch` | `light.kitchen_ceiling` |
| `switch.office_lamp_wall_switch` | `light.office_lamp` |
| `binary_sensor.family_room_wall_switch_input_0` | `light.family_room` |

The automation splits the entity ID at `_wall_switch`, so suffixes like `_wall_switch_input_0` are fine.

## Requirements

- Home Assistant with the Shelly integration.
- Shelly Gen2/Plus/Pro relay running `shelly/ha_availability.js`.
- A Shelly switch entity ending with `_ha_availability`.
- Wall switch entities named with `_wall_switch`.
- Matching light entities named from the same base entity ID.

## Install

1. Copy [`homeassistant/automation/shelly_detached_wall_switch_light_sync.yaml`](../homeassistant/automation/shelly_detached_wall_switch_light_sync.yaml).
2. Paste it into `automations.yaml`, or import it through the Home Assistant automation editor.
3. Rename your wall switch entities to match the naming convention.
4. Confirm the Shelly script exposes a `switch.*_ha_availability` entity for the same Shelly device.
5. Reload automations.

## Why It Checks `ha_availability`

When Home Assistant is online, `ha_availability.js` keeps the relay in detached mode and the wall switch acts as an input. In that state, this automation mirrors the wall switch to the smart light.

When Home Assistant is offline, the Shelly script changes the relay back to local physical control. The automation should not try to mirror the switch then, so it requires `switch.*_ha_availability` to be `on`.

## Troubleshooting

If nothing happens:

- Confirm the wall switch entity changes between `on` and `off`.
- Confirm the wall switch entity ID contains `_wall_switch`.
- Confirm the derived `light.<base>` entity exists.
- Confirm the Shelly device has a `switch.*_ha_availability` entity.
- Confirm that availability switch is `on`.
- Check Home Assistant traces for the automation.
