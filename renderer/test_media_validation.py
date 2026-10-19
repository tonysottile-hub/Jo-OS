import unittest
from media_validation import required_terms_match

class GeographicProvenanceTests(unittest.TestCase):
    def test_rejects_namesake_even_when_query_contains_state(self):
        self.assertFalse(required_terms_match([{'title':'Alexander Hamilton portrait',
            'matched_query':'Hamilton Nevada', 'credit':'Nevada collection'}], ['Hamilton','Nevada']))

    def test_accepts_location_metadata(self):
        self.assertTrue(required_terms_match([{'title':'Hamilton ruins',
            'location':'White Pine County, Nevada'}], ['Hamilton','Nevada']))

    def test_every_image_requires_provenance(self):
        self.assertFalse(required_terms_match([{'title':'Hamilton Nevada ruins'},
            {'title':'Hamilton Ontario station'}], ['Hamilton','Nevada']))

    def test_empty_set_does_not_pass(self):
        self.assertFalse(required_terms_match([], ['Nevada']))
