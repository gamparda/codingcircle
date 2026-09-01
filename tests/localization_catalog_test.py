import collections
import json
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
CATALOG = json.loads((ROOT / "localization" / "translations.json").read_text(encoding="utf-8"))
LOCALES = ["ko", "en", "fr", "zh_CN", "ru", "es"]
KOREAN_LITERAL = re.compile(r'"([^"\n]*[가-힣][^"\n]*)"')
PLACEHOLDER = re.compile(r"%(?:\.[0-9]+)?[sdf]")
HANGUL = re.compile(r"[가-힣]")


def runtime_string(source_literal: str) -> str:
    return (
        source_literal.replace(r"\n", "\n")
        .replace(r"\t", "\t")
        .replace(r'\"', '"')
        .replace("\\\\", "\\")
    )


class LocalizationCatalogTest(unittest.TestCase):
    def test_requested_locales_have_identical_complete_key_sets(self):
        self.assertEqual(list(CATALOG), LOCALES)
        korean_keys = set(CATALOG["ko"])
        self.assertTrue(korean_keys)
        for locale in LOCALES:
            self.assertEqual(set(CATALOG[locale]), korean_keys, locale)
            self.assertTrue(all(str(value).strip() for value in CATALOG[locale].values()), locale)

    def test_every_korean_script_literal_is_in_catalog(self):
        source_keys = set()
        for script in (ROOT / "scripts").glob("*.gd"):
            for literal in KOREAN_LITERAL.findall(script.read_text(encoding="utf-8")):
                source_keys.add(runtime_string(literal))
        self.assertEqual(source_keys - set(CATALOG["ko"]), set())

    def test_translations_preserve_format_placeholders(self):
        for locale in LOCALES[1:]:
            for key, value in CATALOG[locale].items():
                self.assertEqual(
                    collections.Counter(PLACEHOLDER.findall(value)),
                    collections.Counter(PLACEHOLDER.findall(key)),
                    f"{locale}: {key}",
                )

    def test_target_languages_do_not_leak_korean_text(self):
        for locale in LOCALES[1:]:
            leaked = [key for key, value in CATALOG[locale].items() if HANGUL.search(value)]
            self.assertEqual(leaked, [], locale)


if __name__ == "__main__":
    unittest.main()
