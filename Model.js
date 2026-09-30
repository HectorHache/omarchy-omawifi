// Pure helpers for the Wi-Fi Anchor widget: parsing, formatting, colour
// classification. No state, no processes — everything here is a function of its
// arguments, which is what makes the panel and the bar agree on what a snapshot
// means.

// One snapshot document from `omawifi ui`. Returns null when the text is not a
// snapshot at all (a truncated read, a shell error), so callers can keep the
// previous one instead of blanking the panel.
function parse(raw) {
  var text = String(raw || "").trim()
  if (text === "") return null
  var last = text.lastIndexOf("\n")
  if (last >= 0) text = text.slice(last + 1).trim()
  if (text.charAt(0) !== "{") return null
  var doc = null
  try { doc = JSON.parse(text) } catch (e) { return null }
  if (!doc || typeof doc !== "object") return null
  if (!doc.aps || !(doc.aps instanceof Array)) doc.aps = []
  return doc
}

// The words the panel and the tooltip use for a state, never the raw token.
function stateTitle(state) {
  if (state === "locked") return "Anchored"
  if (state === "drifted") return "Drifted"
  if (state === "roaming") return "Roaming"
  return "Offline"
}

function stateLine(doc) {
  if (!doc) return "Waiting for the first scan"
  if (doc.ok === false) return String(doc.error || "Wi-Fi is not available")
  if (doc.state === "locked") return "Holding the access point you anchored to"
  if (doc.state === "drifted") return "The radio moved off the anchored access point"
  if (doc.state === "roaming") return "No anchor set, NetworkManager is choosing"
  return "Not associated"
}

// Which colour role a state wants. The bar widget maps these onto bar tokens;
// keeping the mapping here means bar and panel can never disagree.
function stateTone(state) {
  if (state === "locked") return "ok"
  if (state === "drifted") return "warn"
  if (state === "roaming") return "calm"
  return "off"
}

function bandName(band) {
  if (band === "5G") return "5 GHz"
  if (band === "2G") return "2.4 GHz"
  return ""
}

// nmcli reports a percentage, iw reports dBm. Show both when both are known.
function signalText(doc) {
  if (!doc || doc.signal === null || doc.signal === undefined) return ""
  var text = Math.round(doc.signal) + "%"
  if (doc.dbm !== null && doc.dbm !== undefined) text += "  " + Math.round(doc.dbm) + " dBm"
  return text
}

// Bars are drawn from this rather than from a Nerd Font signal glyph: the bar
// beside this panel already owns that glyph set.
function strength(signal) {
  var n = Number(signal)
  if (!isFinite(n) || n <= 0) return 0
  return Math.max(0, Math.min(1, n / 100))
}

// Last two octets. Enough to tell the access points of one network apart in a
// narrow column, and what you would read off a label on the device.
function shortBssid(bssid) {
  var parts = String(bssid || "").split(":")
  if (parts.length !== 6) return String(bssid || "")
  return parts[4] + ":" + parts[5]
}

function channelText(ap) {
  if (!ap || ap.chan === null || ap.chan === undefined || ap.chan === "") return ""
  return "ch " + ap.chan
}

function rateText(ap) {
  var rate = Number(ap && ap.rate)
  if (!isFinite(rate) || rate <= 0) return ""
  if (rate >= 1000) return (rate / 1000).toFixed(1) + " Gbit/s"
  return Math.round(rate) + " Mbit/s"
}

function countText(n) {
  return n === 1 ? "1 access point" : n + " access points"
}

// The hover tooltip on the bar glyph. Plain text, one fact per line, and the
// state word first so the answer is readable before the details.
function tooltip(doc, ssidOverride) {
  if (!doc) return "Wi-Fi Anchor: waiting for the first scan"
  if (doc.ok === false) return "Wi-Fi Anchor: " + String(doc.error || "unavailable")
  var lines = []
  lines.push("Wi-Fi Anchor — " + stateTitle(doc.state))
  lines.push(String(ssidOverride || doc.ssid || "") + (doc.iface ? "  (" + doc.iface + ")" : ""))
  var on = firstWhere(doc.aps, "current")
  if (on) {
    var detail = [bandName(on.band), channelText(on), signalText(doc)]
    lines.push("on " + on.bssid + "  " + joinNonEmpty(detail, " · "))
  } else {
    lines.push("not associated")
  }
  var pin = firstWhere(doc.aps, "pinned")
  if (pin) lines.push("anchored to " + pin.bssid)
  else if (doc.pinned) lines.push("anchored to " + doc.pinned)
  else lines.push("no anchor, NetworkManager roams")
  lines.push(countText(doc.aps.length) + " visible" + (doc.cached ? " (cached scan)" : ""))
  return lines.join("\n")
}

function firstWhere(list, key) {
  for (var i = 0; i < (list || []).length; i++) if (list[i] && list[i][key]) return list[i]
  return null
}

function joinNonEmpty(parts, sep) {
  var out = []
  for (var i = 0; i < parts.length; i++) if (parts[i]) out.push(parts[i])
  return out.join(sep)
}

// The row the cursor should start on when a panel opens: what you are on now,
// else the anchor, else the strongest.
function initialBssid(doc) {
  if (!doc || !doc.aps || doc.aps.length === 0) return ""
  for (var i = 0; i < doc.aps.length; i++) if (doc.aps[i].current) return String(doc.aps[i].bssid)
  for (var j = 0; j < doc.aps.length; j++) if (doc.aps[j].pinned) return String(doc.aps[j].bssid)
  return String(doc.aps[0].bssid)
}

// The cursor follows an access point, not a row number. The list is re-sorted
// every few seconds as signal moves, and a cursor held by position would quietly
// end up on a different access point than the one the user highlighted.
function indexOfBssid(list, bssid) {
  for (var i = 0; i < (list || []).length; i++) {
    if (list[i] && String(list[i].bssid) === String(bssid)) return i
  }
  return -1
}

// The one-line result of an action, shown in the panel footer.
function actionMessage(op, code, stdout, stderr) {
  var text = String(stdout || "").trim()
  var lines = text ? text.split("\n") : []
  var tail = lines.length > 0 ? lines[lines.length - 1] : ""
  if (code === 0) return tail || "done"
  var err = String(stderr || "").trim()
  var errLines = err ? err.split("\n") : []
  return errLines.length > 0 ? errLines[errLines.length - 1] : (tail || "failed")
}
