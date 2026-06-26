# Shelly Scripts

The `shelly/` folder contains scripts intended to run on Shelly devices, not inside Home Assistant.

## Home Assistant Availability Fallback

File: [`shelly/ha_availability.js`](../shelly/ha_availability.js)

This script runs on a Shelly Gen2/Plus/Pro relay and checks whether Home Assistant is reachable. It is useful when a physical switch controls smart bulbs.

When Home Assistant is reachable:

- The Shelly input is set to detached mode.
- The relay output can be forced on so smart bulbs stay powered.
- Home Assistant keeps control of the bulb or light group.

When Home Assistant is not reachable:

- The Shelly input is set to the configured fallback mode.
- The physical switch regains local control.
- The device continues working even during Home Assistant outages.

## Requirements

- Shelly Gen2, Plus, or Pro device with scripting support.
- Device configured as a switch, not cover mode.
- Network access from the Shelly device to your Home Assistant URL.

## Configure

Edit these values near the top of the file:

```javascript
const HA_URL     = "http://homeassistant.local:8123/";
const RELAY_IDS  = [0];
const CHECK_MS   = 30000;
const TIMEOUT_MS = 4000;
const UP_MODE    = "detached";
const DOWN_MODE  = "follow";
```

Common changes:

- Set `HA_URL` to your Home Assistant IP, DNS name, or local hostname.
- Set `RELAY_IDS` to `[0, 1]` for a two-channel relay if both channels should follow this behavior.
- Set `DOWN_MODE` to the input mode you want during an outage, usually `follow` or `flip`.
- Increase `TIMEOUT_MS` if the device is on a slow or distant network.

## Install

1. Open the Shelly device web UI.
2. Go to Scripts.
3. Create a new script.
4. Paste the contents of `ha_availability.js`.
5. Save, enable, and start the script.
6. Watch the script logs while Home Assistant is online.
7. Temporarily block or stop Home Assistant to confirm the fallback mode works as expected.

## How It Avoids Load

The script uses:

- A steady 30-second health check when Home Assistant is reachable.
- A small random jitter so many Shelly devices do not check at the same instant.
- Exponential backoff up to 3 minutes while Home Assistant appears down.
- A lightweight request to `/api/` instead of loading the frontend.

Any HTTP status below `500` is considered reachable. That means `401` or `403` is acceptable because the Shelly only needs to know that Home Assistant is responding.

## Safety Notes

Test on one device before deploying to a whole fleet.

Confirm the fallback input mode is right for your wiring. Incorrect input mode settings can make a wall switch feel inverted or behave differently than expected.
