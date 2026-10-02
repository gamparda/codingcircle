import pathlib
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]
class KoreanOnlyServiceTest(unittest.TestCase):
    def test_removed_translation_catalog(self):
        self.assertFalse((ROOT / "localization/translations.json").exists())
    def test_no_language_selector(self):
        self.assertNotIn('language.name = "LanguageSelector"', (ROOT / "scripts/Main.gd").read_text(encoding="utf-8"))
    def test_identity_text_facade(self):
        source = (ROOT / "scripts/Localization.gd").read_text(encoding="utf-8")
        self.assertIn('SUPPORTED_LOCALES := ["ko"]', source)
        self.assertIn('return key', source)
        self.assertNotIn('add_translation', source)
if __name__ == "__main__":
    unittest.main()
