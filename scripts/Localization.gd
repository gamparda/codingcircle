extends RefCounted

# Korean-only service. Keep this facade compatible with existing PCK callers.
const SUPPORTED_LOCALES := ["ko"]
const LANGUAGE_NAMES := {"ko": "한국어"}

static func normalize_locale(_locale: String) -> String:
	return "ko"

static func install(_locale: String = "ko") -> String:
	TranslationServer.set_locale("ko")
	return "ko"

static func catalog_is_complete() -> bool:
	return true

static func text(key: String) -> String:
	return key
