# Notification Hierarchy

Home Intelligence separates "something changed" from "someone needs to know right now."

The app always listens to configured and discovered entities, but it does not notify for every state change. Each event is triaged into a severity level, and the severity decides where it goes.

## Severity Levels

| Severity | What it means | Where it goes |
| --- | --- | --- |
| `NORMAL` | The change was not useful enough to publish. | Ignored. |
| `INFO` | Useful context, but no action is needed. | Feed helper and structured JSON helper. Routine area events may be buffered first. |
| `ACTION` | Something should be checked. | Feed helper, structured JSON helper, AppDaemon log, and configured notification services. |
| `URGENT` | Reserved for higher-priority extensions or local customizations. | Same route as `ACTION`. |

## What Becomes `INFO`

Most household context is informational:

- doors, windows, mailbox, gates, and garage doors opening or closing
- room presence and occupancy changes
- Magic Areas aggregate activity
- lights, fans, media players, covers, locks, and selected switches changing
- media helper changes such as "now playing" or "current show"

`INFO` events are useful for dashboards and history, but they do not push to phones by default.

## What Becomes `ACTION`

The portable app treats active safety-style events as actionable:

- leak or flood sensors
- smoke, carbon monoxide, gas, safety, tamper, or problem sensors
- critical entities you explicitly list in `critical_entities`

When an active safety event is detected, Home Intelligence writes the feed and calls every service listed under `notify_services`.

Example:

```yaml
notify_services:
  - notify.mobile_app_your_phone
  - notify.persistent_notification
```

Use service names without the `notify.` prefix only if your AppDaemon setup expects that style. The example app uses AppDaemon's `call_service`, so `notify.mobile_app_your_phone` is the clearest form.

## Area Buffering

Routine room activity can be noisy. For `INFO` events with an area, Home Intelligence buffers related changes for a short period and publishes one area summary.

Example summaries:

- `Kitchen activity: presence and devices changed.`
- `Basement Utility devices changed: Utility Light, Dehumidifier.`
- `Office opening activity changed.`

The debounce is controlled in `apps.yaml`:

```yaml
controls:
  area_debounce_seconds: 90
  area_max_items: 20
```

## Notification Flow

```text
state change
  -> startup/cooldown/noise filters
  -> event triage
  -> NORMAL: ignore
  -> INFO: feed/dashboard, optionally buffered by area
  -> ACTION/URGENT: feed/dashboard + notify_services
```

## Tuning the Hierarchy

Use these lists to control the signal level:

- `critical_entities`: entities that should always be watched directly and can generate actionable events.
- `opening_entities`: doors, windows, gates, mailbox, and garage entities that should show in context.
- `helper_entities`: interpreted helpers such as activity category or media summary helpers.
- `trigger_entities`: explicit override list for unusual entities.

The best pattern is to let Magic Areas and helpers summarize routine room activity, while listing safety and security entities directly.
