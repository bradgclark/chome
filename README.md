# CHOME

CHOME is a public collection of practical Home Assistant, AppDaemon, and Shelly building blocks from my smart home. The goal is to share useful patterns that can be copied into another Home Assistant installation without requiring my full private configuration.

## What Is Here

| Area | Path | What it is for |
| --- | --- | --- |
| Home Intelligence | [`appdaemon/home-intelligence/`](appdaemon/home-intelligence/) | Portable AppDaemon app, docs, examples, and Home Assistant helper definitions. |
| Home Assistant snippets | [`homeassistant/`](homeassistant/) | Lovelace cards, scripts, and template examples for Home Assistant. |
| Shelly scripts | [`shelly/`](shelly/) | Shelly Gen2 JavaScript and matching Home Assistant automation examples for resilient smart-bulb switch behavior. |

## Start Here

If you want the AppDaemon Home Intelligence app:

1. Open [`appdaemon/home-intelligence/README.md`](appdaemon/home-intelligence/README.md).
2. Copy the files from [`appdaemon/home-intelligence/`](appdaemon/home-intelligence/) into your AppDaemon config.
3. Create the helpers from [`appdaemon/home-intelligence/home-assistant/helpers.yaml`](appdaemon/home-intelligence/home-assistant/helpers.yaml).
4. Configure the entities, people, notification services, and optional Magic Areas settings for your home.

If you want the smaller examples:

1. Browse [`docs/home-assistant.md`](docs/home-assistant.md) for the Home Assistant snippets.
2. Browse [`docs/shelly.md`](docs/shelly.md) for the Shelly script and detached wall switch automation.
3. Copy only the piece you need and replace entity IDs, URLs, and helper names with your own.

## Repository Layout

```text
appdaemon/
  home-intelligence/        AppDaemon app, docs, examples, and helpers
    README.md               Install guide for the portable Home Intelligence app
    apps/                   AppDaemon app and apps.yaml example
    docs/                   Configuration and trigger guidance
    examples/               Example AppDaemon configurations
    home-assistant/         Home Assistant helper definitions

homeassistant/
  automation/               Automation examples
  lovelace/                 Dashboard card examples
  scripts/                  Script examples
  template/                 Template sensor fragments

shelly/
  ha_availability.js        Shelly Gen2 fallback script
```

## Compatibility

These examples are written for modern Home Assistant installs and AppDaemon 4.x. Some snippets also expect optional integrations or frontend cards:

- AppDaemon for Home Intelligence.
- Magic Areas for the best aggregate Home Intelligence trigger behavior. It is optional.
- Shelly integration for the Shelly restart script.
- Shelly Gen2/Plus/Pro scripting support for `shelly/ha_availability.js`.
- Mushroom cards, card-mod, and a Team Tracker-style sensor for the Lovelace team tracker card.

## Before You Use Anything

Review each file before copying it into your own Home Assistant instance. Replace entity IDs, helper names, URLs, notification services, and area names with values from your own system.

Most files are examples, not full private configuration exports. They are intended to show the pattern cleanly and give you a working starting point.

## Documentation

- [`appdaemon/home-intelligence/README.md`](appdaemon/home-intelligence/README.md): Home Intelligence install guide.
- [`appdaemon/home-intelligence/docs/configuration.md`](appdaemon/home-intelligence/docs/configuration.md): Home Intelligence configuration reference.
- [`appdaemon/home-intelligence/docs/triggers.md`](appdaemon/home-intelligence/docs/triggers.md): Trigger strategy and examples.
- [`appdaemon/home-intelligence/docs/notifications.md`](appdaemon/home-intelligence/docs/notifications.md): Home Intelligence severity and notification hierarchy.
- [`appdaemon/home-intelligence/docs/dashboard.md`](appdaemon/home-intelligence/docs/dashboard.md): Dashboard setup for the Home Intelligence summary.
- [`appdaemon/home-intelligence/docs/context-and-ble.md`](appdaemon/home-intelligence/docs/context-and-ble.md): Magic Areas and Bermuda BLE context.
- [`docs/home-assistant.md`](docs/home-assistant.md): Home Assistant snippet guide.
- [`docs/shelly.md`](docs/shelly.md): Shelly script guide.
- [`docs/shelly-wall-switch-sync.md`](docs/shelly-wall-switch-sync.md): Detached wall switch light sync automation.
