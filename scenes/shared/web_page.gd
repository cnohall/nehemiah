class_name WebPage

# The browser page around a web export: URL parts for invite links. Everything
# returns "" (or does nothing) outside the web build.

static func active() -> bool:
	return OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge")

## "https://example.com" — scheme + host of the page
static func origin() -> String:
	return _eval("location.origin")

## The page is served by the game's own Worker (or a local test server), not
## embedded on another site such as itch.io, where the signaling server, play stats
## and invite links of the page's origin don't exist
static func home() -> bool:
	var host := _eval("location.hostname")
	return host in ["localhost", "127.0.0.1", "nehemiahgame.com"] or host.ends_with(".nehemiahgame.com")

## A ?key=value query parameter of the page URL
static func query(key: String) -> String:
	return _eval("new URLSearchParams(location.search).get(%s) || ''" % JSON.stringify(key))

## The page URL with ?key=value set (other parameters kept)
static func url_with(key: String, value: String) -> String:
	return _eval("(() => { const u = new URL(location.href); u.searchParams.set(%s, %s); return u.href })()"
		% [JSON.stringify(key), JSON.stringify(value)])

## Drop ?key from the address bar without reloading (so a refresh doesn't rejoin)
static func clear_query(key: String) -> void:
	_eval("(() => { const u = new URL(location.href); u.searchParams.delete(%s); history.replaceState(null, '', u.href); return '' })()"
		% JSON.stringify(key))

static func _eval(js: String) -> String:
	if not active():
		return ""
	var v = JavaScriptBridge.eval(js, true)
	return "" if v == null else str(v)
