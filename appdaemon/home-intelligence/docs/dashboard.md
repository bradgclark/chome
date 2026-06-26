# Dashboard Setup

Home Intelligence writes its output to Home Assistant helpers so you can show the current household summary anywhere in Lovelace.

## Helper Outputs

The portable package uses these helpers:

| Helper | Purpose |
| --- | --- |
| `input_text.home_intelligence_feed` | Human-readable latest summary. Best for dashboard text. |
| `input_text.home_intelligence_status` | Runtime status such as listener count. Useful for diagnostics. |
| `input_text.home_intelligence_structured_json` | Compact machine-readable event payload. Useful for advanced cards, templates, or debugging. |

Create them from:

```text
appdaemon/home-intelligence/home-assistant/helpers.yaml
```

## Simple Dashboard Card

Add a Markdown card:

```yaml
type: markdown
title: Home Intelligence
content: >
  **Latest:** {{ states('input_text.home_intelligence_feed') }}

  **Status:** {{ states('input_text.home_intelligence_status') }}
```

This is the fastest way to show the live summary.

## Entity Card

Add an Entities card if you want to inspect the raw helper values:

```yaml
type: entities
title: Home Intelligence
entities:
  - entity: input_text.home_intelligence_feed
    name: Latest summary
  - entity: input_text.home_intelligence_status
    name: Status
  - entity: input_text.home_intelligence_structured_json
    name: Structured event
```

## Template Sensor for a Cleaner Dashboard

If you prefer sensors over `input_text` helpers on dashboards, create template sensors:

```yaml
template:
  - sensor:
      - name: Home Intelligence Summary
        unique_id: home_intelligence_summary
        state: "{{ states('input_text.home_intelligence_feed') }}"

      - name: Home Intelligence Severity
        unique_id: home_intelligence_severity
        state: >-
          {% set raw = states('input_text.home_intelligence_structured_json') %}
          {% if raw in ['unknown', 'unavailable', ''] %}
            Unknown
          {% else %}
            {{ (raw | from_json).severity | default('INFO') }}
          {% endif %}
```

Then show `sensor.home_intelligence_summary` anywhere in Lovelace.

## Example Card File

This repository includes a ready-to-copy card:

```text
homeassistant/lovelace/home_intelligence_summary.yaml
```

Paste it into a manual card or adapt it for your dashboard structure.

## What to Put on the Dashboard

Recommended first dashboard:

- latest Home Intelligence feed
- Home Intelligence status
- activity category helper, if you use one
- presence/area helpers for people, if you use Bermuda BLE or similar
- critical safety sensors

That gives you one panel that answers: what just happened, whether the app is healthy, and where people/activity are currently concentrated.
