import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from verify import verify

MARY={'results':[{'worker':'mary','url':'https://cigar30-shop.fourthwall.com/','final_url':'https://cigar30-shop.fourthwall.com/','browser_passed':False,'products':[]}]}
class AuditClassificationTests(unittest.TestCase):
    @patch('verify.fetch',side_effect=HTTPError('https://cigar30-shop.fourthwall.com/',403,'Forbidden',None,None))
    def test_403_is_access_restricted_not_product_missing(self,_):
        result=verify(MARY,'mary')
        self.assertFalse(result['overall_passed'])
        self.assertEqual(result['verification'][0]['classification'],'access_restricted')
        self.assertEqual(result['verification'][0]['http_status'],403)
    @patch('verify.fetch',return_value=(200,'<html></html>'))
    def test_incomplete_browser_is_not_verified(self,_):
        self.assertEqual(verify(MARY,'mary')['verification'][0]['classification'],'browser_incomplete')
    @patch('verify.fetch',return_value=(200,'<html></html>'))
    def test_no_links_is_not_product_verified(self,_):
        row=dict(MARY['results'][0],browser_passed=True)
        result=verify({'results':[row]},'mary')
        self.assertEqual(result['verification'][0]['classification'],'product_links_unverified')
    def test_wrong_scope_rejected(self):
        with self.assertRaises(ValueError):
            verify(MARY,'jeff')
if __name__=='__main__':
    unittest.main()
