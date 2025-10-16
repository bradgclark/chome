/*
  Set Relay Mode Based on WiFi status and Home Assistant reachability
  Notes:
  - Device must be in "Switch" mode (not Cover).
  - Works on multi-channel devices (set RELAY_IDS accordingly).
*/

//////////////////// USER SETTINGS ////////////////////
const HA_URL     = "http://192.168.0.30:8123/"; // <-- Prefer IP over .local
const RELAY_IDS  = [0];                         // e.g., [0] or [0,1]
const CHECK_MS   = 5000;                        // periodic check interval
const TIMEOUT_MS = 4000;                        // HTTP timeout (ms)
const UP_MODE    = "detached";                  // when HA is reachable
const DOWN_MODE  = "follow";                    // when HA is not reachable
// If HA uses self-signed HTTPS, switch HA_URL to https://... and add ssl_ca:"*"
///////////////////////////////////////////////////////

let lastApplied = null;   // cache of the last global desired mode
let wifiTimer   = null;

function log() { try { print.apply(null, arguments); } catch (e) {} }

// --- RPC helpers: in_mode ---
function getInMode(id, cb) {
  Shelly.call("Switch.GetConfig", { id: id }, function (res, ec, em) {
    if (ec || !res) { log("GetConfig error", id, ec, em); cb(null); return; }
    cb(res.in_mode || null);
  });
}

function setInMode(id, desired, cb) {
  Shelly.call(
    "Switch.SetConfig",
    { id: id, config: { in_mode: desired } }, // correct payload
    function (res, ec, em) {
      if (ec) { log("SetConfig error", id, desired, ec, em); cb && cb(false); return; }
      log("SetConfig OK   ", id, desired);
      cb && cb(true);
    }
  );
}

// --- RPC helpers: output state ---
function getOutput(id, cb) {
  Shelly.call("Switch.GetStatus", { id: id }, function (res, ec, em) {
    if (ec || !res) { log("GetStatus error", id, ec, em); cb(null); return; }
    // Gen2 returns "output": true/false
    cb(!!res.output);
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

// --- HA reachability (with retry & broad success codes) ---
function checkHA(cb, attempt) {
  attempt = attempt || 1;
  Shelly.call(
    "HTTP.GET",
    { url: HA_URL, timeout: TIMEOUT_MS, body: {} /*, ssl_ca:"*"*/ },
    function (res, ec, em) {
      // Any HTTP code < 500 counts as "reachable" (200/302/401/403, etc.)
      const reachable = (!ec && res && typeof res.code === "number" && res.code < 500);
      if (reachable) {
        log("HTTP.GET OK", "code:", res.code, "attempt:", attempt);
        cb(true);
        return;
      }
      if (attempt < 2) {
        log("HTTP.GET retry", "attempt:", attempt, "ec:", ec, "em:", em);
        Timer.set(300, false, function () { checkHA(cb, attempt + 1); });
      } else {
        log("HTTP.GET FAIL", "ec:", ec, "em:", em);
        cb(false);
      }
    }
  );
}

// --- Apply mode to all inputs; if detached, force output ON ---
function applyMode(haUp) {
  const desired = haUp ? UP_MODE : DOWN_MODE;
  if (desired === lastApplied) {
    log("No global change; already", desired);
    // Even if no global change, still enforce ON if detached
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

// --- Initial check (give Wi-Fi/DHCP/ARP/mDNS time to settle) ---
Timer.set(3000, false, function () { checkHA(applyMode); });

// --- Periodic checks ---
Timer.set(CHECK_MS, true, function () { checkHA(applyMode); });

// --- Debounced Wi-Fi reactions ---
Shelly.addEventHandler(function (ev) {
  if (ev === "wifi_connected" || ev === "wifi_disconnected") {
    if (wifiTimer) Timer.clear(wifiTimer);
    wifiTimer = Timer.set(3000, false, function () { checkHA(applyMode); });
  }
});
