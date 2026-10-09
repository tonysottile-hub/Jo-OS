"""Regression tests for the Unmapped America visual-diversity guard."""
import importlib.util
import pathlib
import tempfile
import unittest

MODULE = pathlib.Path(__file__).with_name("visual_diversity.py")
spec = importlib.util.spec_from_file_location("visual_diversity", MODULE)
qa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qa)

def asset(title):
    return {"title": "File:" + title, "source_url": "https://commons.wikimedia.org/wiki/File:" + title}

class VisualDiversityTests(unittest.TestCase):
    def test_rhyolite_tiff_jpeg_duplicates_fail(self):
        sources = []
        for year in (1909, 1912):
            for plate in (1, 2):
                base = f"Sanborn Fire Insurance Map from Rhyolite, Nevada, {year}, Plate {plate:04d}"
                sources.extend((asset(base + ".tiff"), asset(base + ".jpg")))
        result = qa.inspect({"media_sources": sources})
        self.assertFalse(result["passed"])
        self.assertEqual(result["distinct_works"], 4)
        self.assertEqual(len(result["duplicate_works"]), 4)
        self.assertEqual(result["media_categories"], ["map"])

    def test_distinct_mixed_sources_pass(self):
        sources = [asset(x) for x in (
            "Rhyolite 1905 photograph.jpg",
            "Rhyolite 1906 photo.jpg",
            "Rhyolite 1907 postcard.jpg",
            "Rhyolite 1908 newspaper.jpg",
            "Rhyolite 1912 Sanborn map.jpg")]
        result = qa.inspect({"media_sources": sources})
        self.assertTrue(result["passed"])
        self.assertEqual(result["distinct_works"], 5)
        self.assertTrue(result["requires_human_review"])

    def test_missing_metadata_fails_closed(self):
        self.assertFalse(qa.inspect({})["passed"])

    def test_unknown_category_does_not_count_as_diversity(self):
        sources = [asset(f"Rhyolite building view {i}.jpg") for i in range(5)]
        sources[0] = asset("Rhyolite Sanborn map.jpg")
        self.assertFalse(qa.inspect({"media_sources": sources})["passed"])

    def test_invalid_source_entry_fails_closed(self):
        self.assertFalse(qa.inspect({"media_sources": [None]})["passed"])

    def test_missing_identity_fails_closed(self):
        self.assertFalse(qa.inspect({"media_sources": [{}]})["passed"])

    def test_insufficient_unique_sources_fails(self):
        self.assertFalse(qa.inspect({"media_sources": [asset("One photograph.jpg") ]})["passed"])

if __name__ == "__main__":
    unittest.main()
