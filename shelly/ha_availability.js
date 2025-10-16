/*
  Shelly 2PM:
  - If Home Assistant is reachable -> in_mode = "detached"
  - If not reachable                -> in_mode = "flip"
*/

//////////////////// USER SETTINGS ////////////////////
const HA_URL     = "http://homeassistant.local:8123/"; // set to your HA URL/IP
const RELAY_IDS  = [0,1];                                 // [0] or [0,1] for both inputs
const CHECK_MS   = 5000;                                // reachability check interval (ms)
const TIMEOUT_MS = 2000;                                // HTTP timeout (ms)
///////////////////////////////////////////////////////

// --- helpers ---
function getInMode(relayId, cb) {
  Shelly.call("Switch.GetConfig", { id: relayId }, function(res, ec, em) {
    if (ec) { cb(null); return; }
    cb(res && res.in_mode ? res.in_mode : null);
  });
}

function setInModeIfNeeded(relayId, desired) {
  getInMode(relayId, function(curr) {
    if (curr === desired) return;
    Shelly.call("Switch.SetConfig", { id: relayId, in_mode: desired }, function(res, ec, em) {});
  });
}

function checkHA(cb) {
  Shelly.call("HTTP.GET", { url: HA_URL, timeout: TIMEOUT_MS }, function(res, ec, em) {
    if (ec) { cb(false); return; }
    var ok = res && typeof res.code === "number" && res.code >= 200 && res.code < 400;
    cb(!!ok);
  });
}

function applyMode(haUp) {
  var desired = haUp ? "detached" : "flip";
  for (var i = 0; i < RELAY_IDS.length; i++) {
    setInModeIfNeeded(RELAY_IDS[i], desired);
  }
}

// --- initial check on boot (after 1s to let Wi-Fi settle) ---
Timer.set(1000, false, function () {
  checkHA(function (haUp) { applyMode(haUp); });
});

// --- periodic checks ---
Timer.set(CHECK_MS, true, function () {
  checkHA(function (haUp) { applyMode(haUp); });
});

// --- react quickly to Wi-Fi changes ---
Shelly.addEventHandler(function (ev, src, data) {
  if (ev === "wifi_connected" || ev === "wifi_disconnected") {
    Timer.set(1000, false, function () {
      checkHA(function (haUp) { applyMode(haUp); });
    });
  }
});
