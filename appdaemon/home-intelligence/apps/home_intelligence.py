"""Portable Home Intelligence for AppDaemon.

This app listens to high-signal Home Assistant entities, groups activity by
area, and writes a concise household feed. It is intentionally portable:
configure known people, critical entities, and optional notification services in
apps.yaml. Discovery fills in common Magic Areas aggregates/groups and safety
fallbacks when they exist.
"""

from __future__ import annotations

from collections import defaultdict
from datetime import datetime
import json
import re

import appdaemon.plugins.hass.hassapi as hass


class HomeIntelligence(hass.Hass):
    DEFAULT_CONTROLS = {
        "startup_settle_seconds": 90,
        "area_debounce_seconds": 90,
        "area_max_items": 20,
        "event_cooldown_seconds": 3,
        "feed_max_chars": 255,
        "discover_magic_areas": True,
        "discover_area_devices": True,
        "discover_safety": True,
        "discover_media_helpers": True,
    }

    CRITICAL_BINARY_DEVICE_CLASSES = {
        "carbon_monoxide",
        "gas",
        "moisture",
        "problem",
        "safety",
        "smoke",
        "tamper",
    }
    OPENING_DEVICE_CLASSES = {"door", "garage_door", "opening", "window"}
    PRESENCE_DEVICE_CLASSES = {"motion", "occupancy", "presence"}
    ACTION_DOMAINS = {"light", "fan", "media_player", "switch", "cover", "lock"}
    NOISY_WORDS = {
        "battery",
        "ble",
        "connectivity",
        "diagnostic",
        "firmware",
        "identify",
        "linkquality",
        "rssi",
        "signal",
        "update",
        "uptime",
        "wifi",
    }

    def initialize(self):
        self.controls = {**self.DEFAULT_CONTROLS, **(self.args.get("controls") or {})}
        self.helpers = self.args.get("helpers") or {}
        self.people = self.args.get("people") or []
        self.notify_services = self.args.get("notify_services") or []
        if isinstance(self.notify_services, str):
            self.notify_services = [self.notify_services]
        self.area_buffers = {}
        self.area_timers = set()
        self.last_event_by_entity = {}
        self.startup_at = datetime.now()

        self.trigger_entities = self.unique_entities(self.configured_triggers() + self.discovered_triggers())
        self.registered_entities = self.register_listeners(self.trigger_entities)
        self.log(f"Home Intelligence loaded with {len(self.registered_entities)} listeners.")
        self.write_helper("status", f"Online - {len(self.registered_entities)} listeners")

    def configured_triggers(self):
        entities = []
        for key in ("trigger_entities", "critical_entities", "opening_entities", "helper_entities"):
            entities.extend(self.args.get(key) or [])
        for person in self.people:
            entities.extend([person.get("person"), person.get("area"), person.get("location")])
        return [entity for entity in entities if entity]

    def discovered_triggers(self):
        entities = []
        states = self.get_state() or {}
        if self.controls.get("discover_magic_areas"):
            entities.extend(self.discover_magic_area_entities(states))
        if self.controls.get("discover_safety"):
            entities.extend(self.discover_safety_entities(states))
        if self.controls.get("discover_area_devices"):
            entities.extend(self.discover_area_action_entities(states))
        if self.controls.get("discover_media_helpers"):
            entities.extend(self.discover_media_helpers(states))
        return entities

    def discover_magic_area_entities(self, states):
        out = []
        for entity_id, state_obj in states.items():
            entity = str(entity_id)
            if self.is_unusable_state(state_obj):
                continue
            if self.is_preferred_magic_area_entity(entity):
                out.append(entity)
        return out

    def is_preferred_magic_area_entity(self, entity_id):
        entity = str(entity_id).lower()
        domain = self.domain(entity)
        if domain == "binary_sensor":
            if entity.startswith("binary_sensor.magic_areas_presence_tracking_") and entity.endswith("_area_state"):
                return True
            if entity.startswith("binary_sensor.magic_areas_aggregates_") and (
                entity.endswith("_aggregate_motion") or entity.endswith("_aggregate_occupancy")
            ):
                return True
        if domain == "light":
            return entity.startswith("light.magic_areas_light_groups_") and entity.endswith("_all_lights")
        if domain == "fan":
            return entity.startswith("fan.magic_areas_fan_groups_") and entity.endswith("_fan_group")
        if domain == "media_player":
            return entity.startswith("media_player.magic_areas_media_player_groups_") and entity.endswith("_media_player_group")
        return False

    def discover_safety_entities(self, states):
        out = []
        for entity_id, state_obj in states.items():
            entity = str(entity_id)
            domain = self.domain(entity)
            if domain not in {"binary_sensor", "sensor"} or self.is_unusable_state(state_obj):
                continue
            attrs = self.attributes_from_state_obj(state_obj)
            device_class = str(attrs.get("device_class") or self.get_state(entity, attribute="device_class") or "").lower()
            text = f"{entity} {attrs.get('friendly_name') or self.friendly_name(entity)} {device_class}".lower()
            if device_class in self.CRITICAL_BINARY_DEVICE_CLASSES or any(
                word in text for word in ["leak", "flood", "smoke", "carbon", "gas"]
            ):
                out.append(entity)
        return out[:100]

    def discover_area_action_entities(self, states):
        out = []
        coverage = self.magic_area_coverage(states)
        for entity_id, state_obj in states.items():
            entity = str(entity_id)
            domain = self.domain(entity)
            if domain not in self.ACTION_DOMAINS or self.is_unusable_state(state_obj):
                continue
            if self.is_noisy_entity(entity):
                continue
            if self.is_redundant_raw_area_entity(entity, coverage):
                continue
            if domain == "switch" and not self.has_any_token(entity, {"light", "lamp", "fan", "heater", "dehumidifier"}):
                continue
            out.append(entity)
        return out[:250]

    def magic_area_coverage(self, states):
        coverage = defaultdict(set)
        for entity_id in states:
            entity = str(entity_id)
            if not self.is_preferred_magic_area_entity(entity):
                continue
            area = self.area_for_entity(entity)
            if not area:
                continue
            category = self.preferred_category(entity)
            if category:
                coverage[category].add(self.norm(area))
        return coverage

    def preferred_category(self, entity_id):
        domain = self.domain(entity_id)
        if domain == "light":
            return "light"
        if domain == "fan":
            return "fan"
        if domain == "media_player":
            return "media"
        if domain == "binary_sensor":
            return "presence"
        return ""

    def is_redundant_raw_area_entity(self, entity_id, coverage):
        if self.is_preferred_magic_area_entity(entity_id):
            return False
        domain = self.domain(entity_id)
        area = self.norm(self.area_for_entity(entity_id))
        if not area:
            return False
        if domain == "light" or (domain == "switch" and self.has_any_token(entity_id, {"light", "lamp"})):
            return area in coverage.get("light", set())
        if domain == "fan" or (domain == "switch" and self.has_any_token(entity_id, {"fan"})):
            return area in coverage.get("fan", set())
        if domain == "media_player":
            return area in coverage.get("media", set())
        if domain == "binary_sensor" and self.is_presence_like(entity_id):
            return area in coverage.get("presence", set())
        return False

    def discover_media_helpers(self, states):
        out = []
        for entity_id, state_obj in states.items():
            entity = str(entity_id)
            if self.domain(entity) != "input_text" or self.is_unusable_state(state_obj):
                continue
            state = state_obj.get("state") if isinstance(state_obj, dict) else self.get_state(entity)
            if self.is_media_helper(entity, state):
                out.append(entity)
        return out[:80]

    def register_listeners(self, entities):
        states = self.get_state() or {}
        registered = []
        missing = []
        for entity in entities:
            if entity in states:
                self.listen_state(self.state_changed, entity)
                registered.append(entity)
            else:
                missing.append(entity)
        if missing:
            self.log(f"Skipped {len(missing)} missing Home Intelligence entities.", level="WARNING")
        return registered

    def state_changed(self, entity, attribute, old, new, kwargs):
        if old == new:
            return
        if self.startup_settle_active(old, new):
            return
        if self.is_uninteresting_transition(old, new):
            return
        if self.in_cooldown(entity):
            return

        event = self.build_event(entity, old, new)
        result = self.triage_event(event)
        self.last_event_by_entity[entity] = datetime.now()
        if result["severity"] == "NORMAL":
            return
        if result["severity"] == "INFO" and self.should_buffer_area(result, event):
            self.buffer_area_event(result, event)
            return
        self.publish_result(result, event)

    def startup_settle_active(self, old, new):
        seconds = int(self.controls.get("startup_settle_seconds", 90))
        if (datetime.now() - self.startup_at).total_seconds() > seconds:
            return False
        return str(old).lower() in {"unknown", "unavailable", "none", ""} or str(new).lower() in {
            "unknown",
            "unavailable",
            "none",
            "",
        }

    def is_uninteresting_transition(self, old, new):
        old_text = str(old or "").lower()
        new_text = str(new or "").lower()
        return old_text == new_text or new_text in {"unknown", "unavailable", "none", ""}

    def in_cooldown(self, entity):
        seconds = int(self.controls.get("event_cooldown_seconds", 3))
        last = self.last_event_by_entity.get(entity)
        return bool(last and (datetime.now() - last).total_seconds() < seconds)

    def build_event(self, entity, old, new):
        attrs = self.get_state(entity, attribute="all") or {}
        attrs = attrs.get("attributes", {}) if isinstance(attrs, dict) else {}
        return {
            "entity": entity,
            "domain": self.domain(entity),
            "name": attrs.get("friendly_name") or self.friendly_name(entity),
            "area": self.area_for_entity(entity),
            "old_raw": old,
            "new_raw": new,
            "old": self.format_state(entity, old),
            "new": self.format_state(entity, new),
            "device_class": attrs.get("device_class") or "",
        }

    def triage_event(self, event):
        entity = event["entity"]
        domain = event["domain"]
        new_raw = str(event["new_raw"] or "").lower()
        area = event["area"]
        name = self.clean_name(event["name"], area)

        if self.is_safety_event(event):
            active = new_raw in {"on", "detected", "wet", "problem", "unsafe"}
            severity = "ACTION" if active else "INFO"
            summary = f"{name} is {event['new']}." if active else f"{name} returned to {event['new']}."
            return self.result(severity, "Safety", summary, "Check this now." if active else "No action needed.")

        if self.is_opening_event(event):
            verb = "opened" if new_raw in {"on", "open", "opening"} else "closed"
            summary = f"{name} {verb}"
            if area:
                summary += f" in {area}"
            return self.result("INFO", "Opening", summary + ".", "No action needed.")

        if self.is_presence_event(event):
            state = "active" if new_raw in {"on", "home", "detected"} else "clear"
            summary = f"{name} is {state}"
            if area:
                summary += f" in {area}"
            return self.result("INFO", "Presence", summary + ".", "No action needed.")

        if self.is_media_helper(entity, event["new_raw"]):
            summary = f"{name} is now {event['new']}."
            if area:
                summary = f"{name} in {area} is now {event['new']}."
            return self.result("INFO", "Room activity", summary, "No action needed.")

        if domain in self.ACTION_DOMAINS:
            summary = self.action_summary(event, name, area)
            return self.result("INFO", "Room activity", summary, "No action needed.")

        return self.result("NORMAL", "Ignored", "No notable change.", "No action needed.")

    def is_safety_event(self, event):
        entity = event["entity"]
        device_class = str(event.get("device_class") or "").lower()
        text = f"{entity} {event.get('name')} {device_class}".lower()
        return device_class in self.CRITICAL_BINARY_DEVICE_CLASSES or any(
            word in text for word in ["leak", "flood", "smoke", "carbon", "gas"]
        )

    def is_opening_event(self, event):
        if event["domain"] not in {"binary_sensor", "cover"}:
            return False
        device_class = str(event.get("device_class") or "").lower()
        tokens = self.tokens(event["entity"], event.get("name"), device_class)
        return device_class in self.OPENING_DEVICE_CLASSES or bool(
            tokens & {"door", "window", "contact", "garage", "mailbox", "gate"}
        )

    def is_presence_event(self, event):
        return event["domain"] in {"person", "device_tracker"} or self.is_presence_like(event["entity"], event)

    def is_presence_like(self, entity_id, event=None):
        if self.domain(entity_id) != "binary_sensor":
            return False
        device_class = str((event or {}).get("device_class") or self.get_state(entity_id, attribute="device_class") or "").lower()
        tokens = self.tokens(entity_id, (event or {}).get("name") or self.friendly_name(entity_id), device_class)
        if device_class in self.PRESENCE_DEVICE_CLASSES:
            return True
        return bool(tokens & {"motion", "occupancy", "presence", "person"}) and not bool(
            tokens & {"camera", "vehicle", "animal", "pet", "package"}
        )

    def action_summary(self, event, name, area):
        domain = event["domain"]
        new = str(event["new_raw"]).lower()
        place = f" in {area}" if area else ""
        if domain == "media_player":
            return f"{name}{place} is {event['new']}."
        if new in {"on", "off", "open", "closed", "locked", "unlocked"}:
            return f"{name}{place} changed to {event['new']}."
        return f"{name}{place} changed."

    def should_buffer_area(self, result, event):
        if result["severity"] != "INFO":
            return False
        return bool(event.get("area")) and result["reason"] in {"Room activity", "Presence", "Opening"}

    def buffer_area_event(self, result, event):
        area = event["area"]
        key = self.norm(area)
        bucket = self.area_buffers.setdefault(key, {"area": area, "items": []})
        bucket["items"].append({"event": event, "result": result, "time": datetime.now()})
        bucket["items"] = bucket["items"][-int(self.controls.get("area_max_items", 20)) :]
        if key not in self.area_timers:
            self.area_timers.add(key)
            self.run_in(self.flush_area_buffer, int(self.controls.get("area_debounce_seconds", 90)), area_key=key)

    def flush_area_buffer(self, kwargs):
        key = kwargs.get("area_key")
        self.area_timers.discard(key)
        bucket = self.area_buffers.pop(key, None)
        if not bucket:
            return
        result = self.summarize_area_bucket(bucket["area"], bucket["items"])
        if result["severity"] != "NORMAL":
            self.publish_result(result, {"entity": "area_activity_summary", "area": bucket["area"]})

    def summarize_area_bucket(self, area, items):
        presence = [item for item in items if item["result"]["reason"] == "Presence"]
        openings = [item for item in items if item["result"]["reason"] == "Opening"]
        devices = [item for item in items if item["result"]["reason"] == "Room activity"]
        if presence and devices:
            return self.result("INFO", "Area activity", f"{area} activity: presence and devices changed.", "No action needed.")
        if presence and openings:
            return self.result("INFO", "Area activity", f"{area} activity: presence and openings changed.", "No action needed.")
        if devices:
            names = self.unique_text([item["event"].get("name") for item in devices])[:3]
            return self.result("INFO", "Area activity", f"{area} devices changed: {', '.join(names)}.", "No action needed.")
        if openings:
            return self.result("INFO", "Area activity", f"{area} opening activity changed.", "No action needed.")
        if presence:
            return self.result("INFO", "Area activity", f"{area} presence changed.", "No action needed.")
        return self.result("NORMAL", "Area activity", "No notable grouped activity.", "No action needed.")

    def publish_result(self, result, event):
        message = result["summary"]
        self.write_feed(result, event)
        severity = result["severity"]
        self.log(f"{severity}: {message} ({event.get('entity')})")
        if severity in {"ACTION", "URGENT"}:
            for service in self.notify_services:
                self.call_service(service, title=result["title"], message=message)

    def write_feed(self, result, event):
        helper = self.helpers.get("feed")
        if not helper:
            return
        payload = f"{result['summary']} - {datetime.now().strftime('%-I:%M:%S %p')}"
        self.write_helper_entity(helper, payload[: int(self.controls.get("feed_max_chars", 255))])
        json_helper = self.helpers.get("structured_json")
        if json_helper:
            data = {
                "time": datetime.now().isoformat(timespec="seconds"),
                "severity": result["severity"],
                "reason": result["reason"],
                "summary": result["summary"],
                "entity": event.get("entity"),
                "area": event.get("area"),
            }
            self.write_helper_entity(json_helper, json.dumps(data)[:255])

    def write_helper(self, key, value):
        entity = self.helpers.get(key)
        if entity:
            self.write_helper_entity(entity, value)

    def write_helper_entity(self, entity_id, value):
        try:
            self.call_service("input_text/set_value", entity_id=entity_id, value=str(value)[:255])
        except Exception as err:
            self.log(f"Failed writing helper {entity_id}: {err}", level="WARNING")

    def result(self, severity, reason, summary, next_action):
        return {
            "severity": severity,
            "reason": reason,
            "summary": summary,
            "title": f"Home Intelligence - {reason}",
            "next_action": next_action,
        }

    def area_for_entity(self, entity_id):
        area = self.safe_area(entity_id) or self.registry_area_name(entity_id) or self.area_from_magic_entity(entity_id)
        return area or ""

    def domain(self, entity_id):
        text = str(entity_id or "")
        return text.split(".", 1)[0] if "." in text else ""

    def friendly_name(self, entity_id):
        try:
            attrs = self.get_state(entity_id, attribute="all") or {}
            attrs = attrs.get("attributes", {}) if isinstance(attrs, dict) else {}
            return attrs.get("friendly_name") or str(entity_id or "")
        except Exception:
            return str(entity_id or "")

    def safe_area(self, entity_id):
        try:
            attrs = self.get_state(entity_id, attribute="all") or {}
            attrs = attrs.get("attributes", {}) if isinstance(attrs, dict) else {}
            return attrs.get("area") or attrs.get("area_name") or ""
        except Exception:
            return ""

    def registry_area_name(self, entity_id):
        return ""

    def area_from_magic_entity(self, entity_id):
        entity = str(entity_id).lower()
        patterns = [
            ("binary_sensor.magic_areas_presence_tracking_", "_area_state"),
            ("binary_sensor.magic_areas_aggregates_", "_aggregate_motion"),
            ("binary_sensor.magic_areas_aggregates_", "_aggregate_occupancy"),
            ("light.magic_areas_light_groups_", "_all_lights"),
            ("fan.magic_areas_fan_groups_", "_fan_group"),
            ("media_player.magic_areas_media_player_groups_", "_media_player_group"),
        ]
        for prefix, suffix in patterns:
            if entity.startswith(prefix) and entity.endswith(suffix):
                return entity[len(prefix) : -len(suffix)].replace("_", " ").title()
        return ""

    def format_state(self, entity_id, state):
        text = str(state)
        lowered = text.lower()
        if self.domain(entity_id) == "binary_sensor":
            device_class = str(self.get_state(entity_id, attribute="device_class") or "").lower()
            labels = {
                "door": {"on": "Opened", "off": "Closed"},
                "garage_door": {"on": "Opened", "off": "Closed"},
                "moisture": {"on": "Wet", "off": "Dry"},
                "motion": {"on": "Detected", "off": "Clear"},
                "occupancy": {"on": "Detected", "off": "Clear"},
                "opening": {"on": "Opened", "off": "Closed"},
                "presence": {"on": "Detected", "off": "Clear"},
                "smoke": {"on": "Detected", "off": "Clear"},
                "window": {"on": "Opened", "off": "Closed"},
            }.get(device_class)
            if labels and lowered in labels:
                return labels[lowered]
        return text.replace("_", " ").title() if "_" in text else text.title()

    def is_media_helper(self, entity_id, state=None):
        if self.domain(entity_id) != "input_text":
            return False
        text = f"{entity_id} {self.friendly_name(entity_id)}".lower().replace("_", " ")
        if not any(word in text for word in ["media", "now playing", "song", "show", "title", "episode", "sonos"]):
            return False
        if state is None:
            state = self.get_state(entity_id)
        return str(state or "").strip().lower() not in {"", "unknown", "unavailable", "none", "idle", "off", "not playing"}

    def is_unusable_state(self, state_obj):
        state = state_obj.get("state") if isinstance(state_obj, dict) else state_obj
        return str(state or "").lower() in {"unknown", "unavailable", "none", ""}

    def attributes_from_state_obj(self, state_obj):
        return state_obj.get("attributes", {}) if isinstance(state_obj, dict) else {}

    def is_noisy_entity(self, entity_id):
        text = f"{entity_id} {self.friendly_name(entity_id)}".lower().replace("_", " ")
        return any(word in text for word in self.NOISY_WORDS)

    def has_any_token(self, entity_id, wanted):
        return bool(self.tokens(entity_id, self.friendly_name(entity_id)) & set(wanted))

    def tokens(self, *values):
        return {token for token in re.split(r"[^a-z0-9]+", " ".join(str(value or "").lower() for value in values)) if token}

    def clean_name(self, name, area=""):
        text = str(name or "").strip()
        if area:
            text = re.sub(re.escape(area), "", text, flags=re.IGNORECASE).strip()
        return " ".join(text.split()) or str(name or "Device")

    def norm(self, value):
        return re.sub(r"[^a-z0-9]+", "", str(value or "").lower())

    def unique_entities(self, values):
        return list(dict.fromkeys([value for value in values if isinstance(value, str) and value]))

    def unique_text(self, values):
        return list(dict.fromkeys([str(value) for value in values if value]))
