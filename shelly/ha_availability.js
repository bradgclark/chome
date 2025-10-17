/*
  Set Relay Mode Based on Home Assistant Availability

  Summary:
  - This script runs on a Shelly relay and monitors connectivity with a Home Assistant server.
  - When Home Assistant is reachable, the relay operates in Detached mode, separating the physical switch
    from the relay—ideal for use with smart bulbs controlled by HA.
  - When Home Assistant is not reachable, the relay automatically switches to the mode defined by DOWN_MODE
    (typically Flip/Edge or Follow/Toggle), restoring direct local control.
  - Scaled for many devices: 30s steady heartbeat, small randomized jitter to de-sync checks,
    and exponential backoff (up to 3 minutes) while HA appears down to avoid thundering herds.
  - Uses a lightweight probe to /api/ and treats any HTTP status code < 500 as “reachable”
    (e.g., 200/302/401/403), which avoids loading HA’s front-end.
  - If Detached mode is applied, the script optionally ensures the output is ON so smart bulbs stay powered.

  Purpose:
  - Maintain smart-bulb behavior (Detached) when HA is online.
  - Provide automatic fallback to physical switch control if HA goes offline.
  - Reduce network/server load when you have dozens of Shellys checking HA status.

  Notes:
  - The device must be configured in "Switch" mode (not Cover).
  - Compatible with multi-channel devices (set RELAY_IDS accordingly).
  - Works with IP, DNS, and mDNS (.local) targets; adjust TIMEOUT_MS for slow links.
  - Safe defaults for fleets (~50 devices). Tune CHECK_MS/MIN_MS/MAX_MS if needed.
  - Logging is minimal to avoid clutter; expand `log()` calls if you need deeper diagnostics.
*/

//////////////////// USER SETTINGS ////////////////////
const HA_URL     = "http://homeassistant.local:8123/"; // IP or DNS fine
const RELAY_IDS  = [0];                         // e.g., [0] or [0,1]
const CHECK_MS   = 30000;                       // baseline heartbeat when HA is healthy
const TIMEOUT_MS = 4000;                        // HTTP timeout (ms)
const UP_MODE    = "detached";                  // when HA is reachable
const DOWN_MODE  = "follow";                    // when HA is not reachable ("flip" or "follow")
///////////////////////////////////////////////////////

let lastApplied = null;   // cache the last global desired mode
let wifiTimer   = null;   // debounce Wi-Fi events
let nextTimer   = null;   // scheduler timer handle

// Backoff configuration (healthy sticks to MIN_MS; unhealthy backs off up to MAX_MS)
const MIN_MS = CHECK_MS;          // 30s steady when healthy
const MAX_MS = 180000;            // cap at 3 minutes when unhealthy
let backoffMs = MIN_MS;

function log() { try { print.apply(null, arguments); } catch (e) {} }

// --- RPC helpers: input mode (in_mode) ---
function getInMode(id, cb) {
  Shelly.call("Switch.GetConfig", { id: id }, function (res, ec, em) {
    if (ec || !res) { log("GetConfig error", id, ec, em); cb(null); return; }
    cb(res.in_mode || null);
  });
}

function setInMode(id, desired, cb) {
  Shelly.call(
    "Switch.SetConfig",
    { id: id, config: { in_mode: desired } },
    function (res, ec, em) {
      if (ec) { log("SetConfig error", id, desired, ec, em); cb && cb(false); return; }
      log("SetConfig OK   ", id, desired);
      cb && cb(true);
    }
  );
}

// --- RPC helpers: output state (ensure power for smart bulbs in Detached) ---
function getOutput(id, cb) {
  Shelly.call("Switch.GetStatus", { id: id }, function (res, ec, em) {
    if (ec || !res) { log("GetStatus error", id, ec, em); cb(null); return; }
    cb(!!res.output); // Gen2 has boolean "output"
  });
}

function setOutput(id, on) {
  Shelly.call("Switch.Set", { id: id, on: !!on }, function (res, ec, em) {
    if (ec) log("Switch.Set error", id, on, ec, em);
    else    log("Switch.Set OK   ", id, on);
  });
}

function ensureOnIfDetached(id, desiredMode) {
  if (desiredMode !== "detached") return;
  getOutput(id, function (out) {
    if (out === null) return; // read error already logged
    if (!out) setOutput(id, true);
    else log("Output already ON", id);
  });
}

// --- Home Assistant reachability (retry once; count any <500 code as reachable) ---
function checkHA(cb, attempt) {
  attempt = attempt || 1;
  Shelly.call(
    "HTTP.GET",
    { url: HA_URL, timeout: TIMEOUT_MS },
    function (res, ec, em) {
      const code = res && typeof res.code === "number" ? res.code : null;
      const reachable = (!ec && code !== null && code < 500);

      if (reachable) {
        log("HTTP.GET OK  code:", code, "attempt:", attempt);
        cb(true);
        return;
      }

      if (attempt < 2) {
        log("HTTP.GET retry attempt:", attempt, "ec:", ec, "em:", em, "code:", code);
        Timer.set(300, false, function () { checkHA(cb, attempt + 1); });
      } else {
        log("HTTP.GET FAIL ec:", ec, "em:", em, "code:", code);
        cb(false);
      }
    }
  );
}

// --- Apply mode to all inputs; if Detached, force output ON ---
function applyMode(haUp) {
  const desired = haUp ? UP_MODE : DOWN_MODE;

  if (desired === lastApplied) {
    log("No global change; already", desired);
    RELAY_IDS.forEach(function (id) { ensureOnIfDetached(id, desired); });
    return;
  }

  RELAY_IDS.forEach(function (id) {
    getInMode(id, function (curr) {
      if (curr === null) return; // read error already logged

      if (curr !== desired) {
        setInMode(id, desired, function () {
          ensureOnIfDetached(id, desired);
        });
      } else {
        log("Already set    ", id, desired);
        ensureOnIfDetached(id, desired);
      }
    });
  });

  lastApplied = desired;
  log("Applied global mode:", desired, "(HA up:", haUp, ")");
}

// --- Scheduler with exponential backoff + small jitter ---
function scheduleNext(haUp) {
  backoffMs = haUp ? MIN_MS : Math.min(backoffMs * 2, MAX_MS);
  const jitter = Math.floor(Math.random() * 3000); // 0–3s jitter to spread load

  if (nextTimer) { Timer.clear(nextTimer); nextTimer = null; }
  nextTimer = Timer.set(backoffMs + jitter, false, function () {
    checkHA(applyModeAndSchedule);
  });

  log("Next check in ~", backoffMs + jitter, "ms");
}

function applyModeAndSchedule(haUp) {
  applyMode(haUp);
  scheduleNext(haUp);
}

// --- Initial warm-up: give Wi-Fi/DHCP/mDNS a moment ---
Timer.set(3000, false, function () { checkHA(applyModeAndSchedule); });

// --- Debounced Wi-Fi reactions: quick recheck & reset backoff ---
Shelly.addEventHandler(function (ev) {
  if (ev === "wifi_connected" || ev === "wifi_disconnected") {
    if (wifiTimer) { Timer.clear(wifiTimer); wifiTimer = null; }
    wifiTimer = Timer.set(3000, false, function () {
      backoffMs = MIN_MS;
      if (nextTimer) { Timer.clear(nextTimer); nextTimer = null; }
      checkHA(applyModeAndSchedule);
    });
  }
});
