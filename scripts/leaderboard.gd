extends Node
## All-time high scores (autoload "Leaderboard").
##
## Online: a Supabase table read/written through its REST API, configured in
## res://leaderboard_config.cfg (see LEADERBOARD.md). Works in the web build.
## Offline fallback: if no backend is configured or a request fails, scores are
## kept on this device (user://local_scores.cfg, which is IndexedDB in browsers).
##
## All calls are coroutines:  var res := await Leaderboard.fetch_top()

const CONFIG_PATH := "res://leaderboard_config.cfg"
const LOCAL_PATH := "user://local_scores.cfg"
const SETTINGS_PATH := "user://settings.cfg"
const NAME_LENGTH := 5
const TOP_COUNT := 10
const LOCAL_KEEP := 50
const TIMEOUT := 10.0

var url: String = ""
var key: String = ""
var table: String = "scores"
## The last name used on this device, offered again next time.
var last_name: String = ""

var _name_regex := RegEx.create_from_string("^[A-Z]{%d}$" % NAME_LENGTH)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # works from the pause menu too
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		url = str(cfg.get_value("supabase", "url", "")).strip_edges().trim_suffix("/")
		key = str(cfg.get_value("supabase", "key", "")).strip_edges()
		table = str(cfg.get_value("supabase", "table", "scores")).strip_edges()
	var settings := ConfigFile.new()
	if settings.load(SETTINGS_PATH) == OK:
		last_name = str(settings.get_value("player", "name", ""))


func is_online() -> bool:
	return url != "" and key != ""


## Upper-case, letters only, at most 5 characters.
func clean_name(text: String) -> String:
	var out := ""
	for ch in text.to_upper():
		if ch >= "A" and ch <= "Z":
			out += ch
	return out.left(NAME_LENGTH)


func is_valid_name(player_name: String) -> bool:
	return _name_regex.search(player_name) != null


# --- Public API -----------------------------------------------------------------

## Returns {ok, online, entries: [{name, score, won}], error}.
func fetch_top() -> Dictionary:
	if is_online():
		var res := await _request(HTTPClient.METHOD_GET,
				"%s?select=name,score,won&order=score.desc,created_at.asc&limit=%d" % [table, TOP_COUNT])
		if res["ok"]:
			var parsed: Variant = JSON.parse_string(res["body"])
			if parsed is Array:
				return {"ok": true, "online": true, "entries": _normalize(parsed), "error": ""}
			res["error"] = "unexpected reply from the server"
		return {"ok": false, "online": false, "entries": _local_entries().slice(0, TOP_COUNT),
				"error": "Online board unavailable (%s). Showing this device's scores." % res["error"]}
	return {"ok": true, "online": false, "entries": _local_entries().slice(0, TOP_COUNT), "error": ""}


## All-time position a score would have (1 = best). Returns -1 if unknown.
func fetch_rank(score: int) -> int:
	if is_online():
		var res := await _request(HTTPClient.METHOD_GET,
				"%s?select=id&score=gt.%d&limit=1" % [table, score], "", ["Prefer: count=exact"])
		if res["ok"]:
			# Content-Range: 0-0/123  (or */0 when nothing is higher)
			for header: String in res["headers"]:
				if header.to_lower().begins_with("content-range:"):
					var total := header.get_slice("/", 1).strip_edges()
					if total.is_valid_int():
						return int(total) + 1
		return -1
	var better := 0
	for e in _local_entries():
		if int(e["score"]) > score:
			better += 1
	return better + 1


## Returns {ok, online, error}. Falls back to saving on this device.
func submit(player_name: String, score: int, won: bool) -> Dictionary:
	if not is_valid_name(player_name):
		return {"ok": false, "online": false, "error": "Names must be exactly %d letters (A-Z)." % NAME_LENGTH}
	_remember_name(player_name)
	if is_online():
		var body := JSON.stringify({"name": player_name, "score": score, "won": won})
		var res := await _request(HTTPClient.METHOD_POST, table, body, ["Prefer: return=minimal"])
		if res["ok"]:
			return {"ok": true, "online": true, "error": ""}
		_save_local(player_name, score, won)
		return {"ok": false, "online": false,
				"error": "Couldn't reach the online board (%s). Saved on this device." % res["error"]}
	_save_local(player_name, score, won)
	return {"ok": true, "online": false, "error": ""}


# --- HTTP -------------------------------------------------------------------------

func _request(method: HTTPClient.Method, path: String, body: String = "",
		extra_headers: Array = []) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	add_child(http)
	var headers := PackedStringArray(["apikey: " + key, "Content-Type: application/json", "Accept: application/json"])
	if key.begins_with("eyJ"): # legacy JWT "anon" keys also go in Authorization
		headers.append("Authorization: Bearer " + key)
	for h in extra_headers:
		headers.append(h)
	var err := http.request("%s/rest/v1/%s" % [url, path], headers, method, body)
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": "request error %d" % err, "body": "", "headers": PackedStringArray()}
	var result: Array = await http.request_completed
	http.queue_free()
	var status: int = result[0]
	var code: int = result[1]
	var text := (result[3] as PackedByteArray).get_string_from_utf8()
	if status != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "network error %d" % status, "body": text, "headers": result[2]}
	if code < 200 or code >= 300:
		return {"ok": false, "error": "HTTP %d" % code, "body": text, "headers": result[2]}
	return {"ok": true, "error": "", "body": text, "headers": result[2]}


func _normalize(rows: Array) -> Array:
	var out := []
	for row in rows:
		if row is Dictionary:
			out.append({"name": str(row.get("name", "?????")), "score": int(row.get("score", 0)), "won": bool(row.get("won", false))})
	return out


# --- Local fallback -----------------------------------------------------------------

func _local_entries() -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(LOCAL_PATH) != OK:
		return []
	var entries: Array = cfg.get_value("scores", "entries", [])
	return _normalize(entries)


func _save_local(player_name: String, score: int, won: bool) -> void:
	var entries := _local_entries()
	entries.append({"name": player_name, "score": score, "won": won})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	var cfg := ConfigFile.new()
	cfg.set_value("scores", "entries", entries.slice(0, LOCAL_KEEP))
	cfg.save(LOCAL_PATH)


func _remember_name(player_name: String) -> void:
	last_name = player_name
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH) # keep audio/gameplay sections
	settings.set_value("player", "name", player_name)
	settings.save(SETTINGS_PATH)
