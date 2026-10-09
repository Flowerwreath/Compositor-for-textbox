"""Tests for l10n.py. Run: python3 -m unittest discover -s scripts -p 'test_l10n.py'"""
import importlib.util
import json
import os
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("l10n", os.path.join(os.path.dirname(__file__), "l10n.py"))
l10n = importlib.util.module_from_spec(spec)
spec.loader.exec_module(l10n)


class FormatArguments(unittest.TestCase):
    def accepts(self, key, value):
        return l10n.same_arguments(key, value)

    def test_reordering_needs_numbers(self):
        self.assertTrue(self.accepts("%@ × %@ px", "%2$@ × %1$@ px"))
        self.assertFalse(self.accepts("1–%@ pixels, up to %lld megapixels", "최대 %lld메가픽셀, 한 변 %@픽셀"))

    def test_every_argument_keeps_its_number(self):
        self.assertFalse(self.accepts("%@ × %@ px", "%1$@ × %1$@ px"))
        self.assertFalse(self.accepts("%@ color", "%9$@ 색상"))

    def test_an_added_argument_is_refused(self):
        self.assertFalse(self.accepts("%@ color", "%@ 색상 %s"))
        self.assertFalse(self.accepts("%@ color", "%@ 색상 %*s"), "a * width reads an argument too")
        self.assertFalse(self.accepts("%@ color", "%@ 색상 %.*f"))

    def test_each_argument_is_read_as_often_as_in_the_key(self):
        self.assertFalse(self.accepts("%@ color", "%1$@ %1$@ 색상"))
        self.assertFalse(self.accepts("%@ × %@ px", "%1$@ × %2$@ (%1$@) px"))

    def test_literal_percents_are_not_arguments(self):
        self.assertTrue(self.accepts("%lld%%", "%lld%%"))
        self.assertTrue(self.accepts("Drag; double-click switches between Fit and 100%", "드래그; 두 번 클릭하면 맞춤과 100% 사이를 전환해요"))


class Manual(unittest.TestCase):
    def test_an_extracted_key_becomes_manual_and_keeps_its_translation(self):
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "Localizable.xcstrings")
            korean = {"ko": {"stringUnit": {"state": "translated", "value": "자동"}}}
            with open(path, "w", encoding="utf-8") as f:
                json.dump({"sourceLanguage": "en", "strings": {"Auto": {"localizations": korean}}, "version": "1.0"}, f)
            saved, l10n.CATALOGS = l10n.CATALOGS, [path]
            try:
                l10n.cmd_manual(["Auto"])
            finally:
                l10n.CATALOGS = saved
            with open(path, encoding="utf-8") as f:
                entry = json.load(f)["strings"]["Auto"]
            self.assertEqual(entry["extractionState"], "manual")
            self.assertEqual(entry["localizations"], korean)


if __name__ == "__main__":
    unittest.main()
