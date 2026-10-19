import unittest
from media_validation import required_terms_match, unique_source_count

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

    def test_missing_requirements_fail_closed(self):
        self.assertFalse(required_terms_match([{'title':'Fay hurricane'}], []))

    def test_fay_storm_is_not_fay_nevada(self):
        self.assertFalse(required_terms_match([{'title':'Fay satellite image',
            'description':'Tropical Storm Fay over Florida',
            'matched_query':'Fay Nevada'}], ['Fay','Nevada']))

    def test_crops_do_not_inflate_source_diversity(self):
        self.assertEqual(unique_source_count([
            {'title':'full frame','source_url':'https://example.com/a.jpg'},
            {'title':'detail crop','source_url':'https://example.com/a.jpg'},
            {'title':'map','source_url':'https://example.com/b.jpg'}]), 2)
