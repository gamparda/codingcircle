extends RefCounted

const SUPPORTED_LOCALES := ["ko", "en", "fr", "zh_CN", "ru", "es"]
const LANGUAGE_NAMES := {
	"ko": "한국어",
	"en": "English",
	"fr": "Français",
	"zh_CN": "简体中文",
	"ru": "Русский",
	"es": "Español",
}
const CATALOG_PATH := "res://localization/translations.json"

static var _catalog: Dictionary = {}
static var _installed := false

static func normalize_locale(locale: String) -> String:
	var normalized := locale.replace("-", "_")
	if normalized.begins_with("zh"):
		return "zh_CN"
	var language := normalized.get_slice("_", 0).to_lower()
	return language if SUPPORTED_LOCALES.has(language) else "ko"

static func load_catalog() -> Dictionary:
	if not _catalog.is_empty():
		return _catalog
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_catalog = parsed
	return _catalog

static func catalog_is_complete() -> bool:
	var catalog := load_catalog()
	if catalog.keys().size() != SUPPORTED_LOCALES.size():
		return false
	var expected: Array = []
	for locale in SUPPORTED_LOCALES:
		if not catalog.get(locale) is Dictionary:
			return false
		var keys: Array = catalog[locale].keys()
		keys.sort()
		if expected.is_empty():
			expected = keys
		elif keys != expected:
			return false
	return not expected.is_empty()

static func install(locale: String) -> String:
	var selected := normalize_locale(locale)
	var catalog := load_catalog()
	if not _installed and catalog_is_complete():
		for code in SUPPORTED_LOCALES:
			var translation := Translation.new()
			translation.locale = code
			for key in catalog[code]:
				translation.add_message(StringName(key), String(catalog[code][key]))
			TranslationServer.add_translation(translation)
		_installed = true
	TranslationServer.set_locale(selected)
	return selected

static func text(key: String) -> String:
	return TranslationServer.translate(key)
