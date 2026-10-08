import unittest
from render import layout,visual_durations
class LayoutTests(unittest.TestCase):
    def test_short_preserves_timing(self):
        self.assertEqual(layout({}),(1080,1920))
        self.assertEqual(visual_durations({'assets':[{}, {'duration':6}]}),[4,6])
    def test_long_covers_full_audio(self):
        self.assertEqual(layout({'kind':'long'}),(1920,1080))
        self.assertEqual(sum(visual_durations({'kind':'long','assets':[{}, {}, {}]},240)),240)
    def test_long_rejects_short_audio(self):
        with self.assertRaises(ValueError): visual_durations({'kind':'long','assets':[{}]},72)
if __name__=='__main__': unittest.main()
