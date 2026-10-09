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
    @patch('verify.fetch',return_value=(200,'<html></html>'))
    def test_browser_403_with_http_200_is_access_restricted(self,_):
        row=dict(MARY['results'][0],status=403)
        proof=verify({'results':[row]},'mary')['verification'][0]
        self.assertEqual(proof['classification'],'browser_access_restricted')
        self.assertEqual(proof['browser_http_status'],403)
        self.assertFalse(proof['passed'])
    def test_http_catalog_identity_does_not_certify_browser(self):
        row=dict(MARY['results'][0],status=403)
        html='<html><a href="/products/cigar-30-test-shirt">Test</a></html>'
        product='<html><title>Cigar 30 Test Shirt</title>cigar-30-test-shirt</html>'
        with patch('verify.fetch',side_effect=[(200,html),(200,product)]):
            result=verify({'results':[row]},'mary')
        proof=result['verification'][0]
        self.assertTrue(proof['http_catalog_identity_verified'])
        self.assertEqual(proof['http_product_pages_ok'],1)
        self.assertEqual(proof['http_catalog_classification'],'all_discovered_product_pages_retrievable')
        self.assertEqual(proof['classification'],'browser_access_restricted')
        self.assertFalse(result['overall_passed'])
    def test_failed_product_http_does_not_certify_catalog(self):
        row=dict(MARY['results'][0],status=403)
        html='<html><a href="/products/cigar-30-test-shirt">Test</a></html>'
        with patch('verify.fetch',side_effect=[(200,html),HTTPError('https://cigar30-shop.fourthwall.com/products/cigar-30-test-shirt',404,'Not Found',None,None)]):
            proof=verify({'results':[row]},'mary')['verification'][0]
        self.assertFalse(proof['http_catalog_identity_verified'])
        self.assertEqual(proof['http_catalog_classification'],'product_page_http_incomplete')
        self.assertFalse(proof['passed'])
    def test_generic_cigar_branding_cannot_certify_product(self):
        row=dict(MARY['results'][0],browser_passed=True,status=200,products=[{'url':'https://cigar30-shop.fourthwall.com/products/cigar-30-test-shirt'}],product_navigation={'url':'https://cigar30-shop.fourthwall.com/products/cigar-30-test-shirt'})
        html='<html><a href="/products/cigar-30-test-shirt">Cigar</a></html>'
        generic='<html><title>Cigar 30 Store</title>cigar brand generic</html>'
        with patch('verify.fetch',side_effect=[(200,html),(200,generic),(200,generic)]):
            proof=verify({'results':[row]},'mary')['verification'][0]
        self.assertFalse(proof['passed'])
        self.assertEqual(proof['classification'],'product_content_unverified')
    def test_wrong_scope_rejected(self):
        with self.assertRaises(ValueError):
            verify(MARY,'jeff')
if __name__=='__main__':
    unittest.main()
