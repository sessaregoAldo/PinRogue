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
const NAME_MIN := 2
const NAME_MAX := 5
const TOP_COUNT := 10
const LOCAL_KEEP := 50
const TIMEOUT := 10.0

var url: String = ""
var key: String = ""
var table: String = "scores"
## Story chapters have their own boards in this table (supabase/story_scores.sql),
## one per chapter id. Functions take it as `board`: "" = the Endless board.
const STORY_TABLE := "story_scores"
## The last name used on this device, offered again next time.
var last_name: String = ""

var _name_regex := RegEx.create_from_string("^[A-Z]{%d,%d}$" % [NAME_MIN, NAME_MAX])


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


## Upper-case, letters only, at most NAME_MAX characters.
func clean_name(text: String) -> String:
	var out := ""
	for ch in text.to_upper():
		if ch >= "A" and ch <= "Z":
			out += ch
	return out.left(NAME_MAX)


## Human-readable naming rule, e.g. "Names must be 2-5 letters (A-Z)."
func name_rule() -> String:
	return "Names must be %d-%d letters (A-Z)." % [NAME_MIN, NAME_MAX]


## A score as plain text for the database: whole digits while a float stores
## it exactly (so older integer columns still accept it), scientific notation
## ("1.25e+20") above that.
func _score_text(score: float) -> String:
	if absf(score) < 1.0e15:
		return str(int(roundf(score)))
	return String.num_scientific(score)


## Scores from the database come back as floats; treat tiny differences as equal.
func same_score(a: float, b: float) -> bool:
	return absf(a - b) <= maxf(0.5, absf(b) * 1e-12)


func is_valid_name(player_name: String) -> bool:
	return _name_regex.search(player_name) != null


# --- Public API -----------------------------------------------------------------

## Returns {ok, online, entries: [{name, score, won}], error}.
## `ending` filters by how the run ended: "" = all, "won" = ended after a boss
## (End Run), "lost" = out of balls.
func fetch_top(ending: String = "", board: String = "") -> Dictionary:
	if is_online():
		var res := await _request(HTTPClient.METHOD_GET,
				"%s?select=name,score,won%s%s&order=score.desc,created_at.asc&limit=%d" % [_table(board), _board_query(board), _ending_query(ending), TOP_COUNT])
		if res["ok"]:
			var parsed: Variant = JSON.parse_string(res["body"])
			if parsed is Array:
				return {"ok": true, "online": true, "entries": _normalize(parsed), "error": ""}
			res["error"] = "unexpected reply from the server"
		return {"ok": false, "online": false, "entries": _local_filtered(ending, board).slice(0, TOP_COUNT),
				"error": "Online board unavailable (%s). Showing this device's scores." % res["error"]}
	return {"ok": true, "online": false, "entries": _local_filtered(ending, board).slice(0, TOP_COUNT), "error": ""}


## Position a score would have (1 = best), among all runs or one `ending`.
## Returns -1 if unknown. `after_ties`: also count equal scores as ahead (where a
## score not yet submitted would land, since ties keep the older run first).
func fetch_rank(score: float, ending: String = "", after_ties: bool = false, board: String = "") -> int:
	if is_online():
		var res := await _request(HTTPClient.METHOD_GET,
				"%s?select=id&score=%s.%s%s%s&limit=1" % [_table(board), "gte" if after_ties else "gt",
				_score_text(score).uri_encode(), _board_query(board), _ending_query(ending)], "", ["Prefer: count=exact"])
		if res["ok"]:
			# Content-Range: 0-0/123  (or */0 when nothing is higher)
			for header: String in res["headers"]:
				if header.to_lower().begins_with("content-range:"):
					var total := header.get_slice("/", 1).strip_edges()
					if total.is_valid_int():
						return int(total) + 1
		return -1
	var better := 0
	for e in _local_filtered(ending, board):
		if float(e["score"]) > score or (after_ties and float(e["score"]) >= score):
			better += 1
	return better + 1


## A player's best score and its position, matched by name (optionally only
## among runs with that `ending`).
## Returns {found, name, score, won, rank} (rank -1 if it couldn't be worked out).
func fetch_player_best(player_name: String, ending: String = "", board: String = "") -> Dictionary:
	var none := {"found": false, "name": player_name, "score": 0.0, "won": false, "rank": -1}
	if not is_valid_name(player_name):
		return none
	var best: Dictionary = {}
	if is_online():
		var res := await _request(HTTPClient.METHOD_GET,
				"%s?select=name,score,won&name=eq.%s%s%s&order=score.desc,created_at.asc&limit=1" % [_table(board), player_name, _board_query(board), _ending_query(ending)])
		if res["ok"]:
			var parsed: Variant = JSON.parse_string(res["body"])
			if parsed is Array and not (parsed as Array).is_empty():
				best = _normalize(parsed)[0]
		else:
			return none
	else:
		for e in _local_filtered(ending, board): # already sorted best first
			if e["name"] == player_name:
				best = e
				break
	if best.is_empty():
		return none
	var rank: int = await fetch_rank(float(best["score"]), ending, false, board)
	return {"found": true, "name": player_name, "score": float(best["score"]), "won": bool(best["won"]), "rank": rank}


func _ending_query(ending: String) -> String:
	match ending:
		"won":
			return "&won=eq.true"
		"lost":
			return "&won=eq.false"
	return ""


## Table and filter for a board ("" = Endless, otherwise a story chapter id).
func _table(board: String) -> String:
	return table if board == "" else STORY_TABLE


func _board_query(board: String) -> String:
	return "" if board == "" else "&chapter=eq.%s" % board.uri_encode()


func _local_filtered(ending: String, board: String = "") -> Array:
	var entries := _local_entries(board)
	if ending == "":
		return entries
	return entries.filter(func(e: Dictionary) -> bool: return bool(e["won"]) == (ending == "won"))


## Returns {ok, online, error}. Falls back to saving on this device.
func submit(player_name: String, score: float, won: bool, board: String = "") -> Dictionary:
	if not is_valid_name(player_name):
		return {"ok": false, "online": false, "error": name_rule()}
	_remember_name(player_name)
	if is_online():
		var body := '{"name": %s, "score": %s, "won": %s}' % [JSON.stringify(player_name), _score_text(score), "true" if won else "false"]
		if board != "":
			body = body.trim_suffix("}") + ', "chapter": %s}' % JSON.stringify(board)
		var res := await _request(HTTPClient.METHOD_POST, _table(board), body, ["Prefer: return=minimal"])
		if res["ok"]:
			return {"ok": true, "online": true, "error": ""}
		_save_local(player_name, score, won, board)
		return {"ok": false, "online": false,
				"error": "Couldn't reach the online board (%s). Saved on this device." % res["error"]}
	_save_local(player_name, score, won, board)
	return {"ok": true, "online": false, "error": ""}


## Send a bug report or suggestion to the "feedback" table. `data` holds
## kind, message, name, version, machine, boss_round, score, platform.
## Returns {ok, error}. Nothing is kept on the device if it fails.
func submit_feedback(data: Dictionary) -> Dictionary:
	if not is_online():
		return {"ok": false, "error": "online features aren't set up"}
	var res := await _request(HTTPClient.METHOD_POST, "feedback", JSON.stringify(data), ["Prefer: return=minimal"])
	return {"ok": res["ok"], "error": res["error"]}


## Developer report viewer. The PIN is checked by the server (feedback_list in
## supabase/feedback_admin.sql); nothing about it is stored in the game.
## Returns {ok, error, entries: [{id, created_unix, kind, status, message, name,
## version, machine, boss_round, score, platform}]}, newest first.
func fetch_feedback(pin: String) -> Dictionary:
	var res := await _rpc("feedback_list", {"pin": pin})
	if res["ok"]:
		var entries: Variant = res["data"].get("entries", [])
		res["entries"] = entries if entries is Array else []
	return res


## Removes one report for good. Returns {ok, error}.
func delete_feedback(pin: String, id: int) -> Dictionary:
	return await _rpc("feedback_delete", {"pin": pin, "feedback_id": id})


## Calls a database function that answers {ok, error, ...}.
## Returns {ok, error, data}.
func _rpc(function_name: String, args: Dictionary) -> Dictionary:
	if not is_online():
		return {"ok": false, "error": "online features aren't set up", "data": {}}
	var res := await _request(HTTPClient.METHOD_POST, "rpc/" + function_name, JSON.stringify(args))
	if not res["ok"]:
		if res["body"].contains("Could not find the function"):
			return {"ok": false, "error": "the report viewer isn't set up in the database yet", "data": {}}
		return {"ok": false, "error": res["error"], "data": {}}
	var parsed: Variant = JSON.parse_string(res["body"])
	if not parsed is Dictionary:
		return {"ok": false, "error": "unexpected reply from the server", "data": {}}
	return {"ok": bool(parsed.get("ok", false)), "error": str(parsed.get("error", "")), "data": parsed}


# --- HTTP -------------------------------------------------------------------------

func _request(method: HTTPClient.Method, path: String, body: String = "",
		extra_headers: Array = []) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	# In a browser the response is already unpacked by the browser itself; letting
	# Godot unpack it again fails with "network error 8" (BODY_DECOMPRESS_FAILED).
	http.accept_gzip = not OS.has_feature("web")
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
			out.append({"name": str(row.get("name", "?????")), "score": float(row.get("score", 0)), "won": bool(row.get("won", false))})
	return out


# --- Local fallback -----------------------------------------------------------------

## Section of the local scores file that holds a board.
func _local_section(board: String) -> String:
	return "scores" if board == "" else "story_" + board


func _local_entries(board: String = "") -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(LOCAL_PATH) != OK:
		return []
	var entries: Array = cfg.get_value(_local_section(board), "entries", [])
	return _normalize(entries)


func _save_local(player_name: String, score: float, won: bool, board: String = "") -> void:
	var entries := _local_entries(board)
	entries.append({"name": player_name, "score": score, "won": won})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	var cfg := ConfigFile.new()
	cfg.load(LOCAL_PATH) # keep the other boards
	cfg.set_value(_local_section(board), "entries", entries.slice(0, LOCAL_KEEP))
	cfg.save(LOCAL_PATH)


func _remember_name(player_name: String) -> void:
	last_name = player_name
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH) # keep audio/gameplay sections
	settings.set_value("player", "name", player_name)
	settings.save(SETTINGS_PATH)
