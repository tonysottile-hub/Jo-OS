"""Classify independent storefront checks without conflating access failures with product absence."""
from __future__ import annotations
import json, hashlib, urllib.request, urllib.parse, urllib.error, os
from datetime import datetime, timezone

ALLOWED={'cigar30-shop.fourthwall.com','cigars30jax.com','www.cigars30jax.com'}
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,*args,**kwargs): return None

def fetch(url):
    parsed=urllib.parse.urlsplit(url)
    if parsed.scheme!='https' or parsed.hostname not in ALLOWED or parsed.username or parsed.password or parsed.query or parsed.port not in (None,443):
        raise ValueError('URL denied')
    request=urllib.request.Request(url,headers={'User-Agent':'Jo-OS-Public-Audit/1.0'})
    with urllib.request.build_opener(NoRedirect).open(request,timeout=25) as response:
        data=response.read(2_000_001)
        if len(data)>2_000_000: raise ValueError('Response too large')
        return response.status,data.decode('utf-8','replace')

def classify_error(error):
    if isinstance(error, urllib.error.HTTPError):
        if error.code in (401,403,429): return 'access_restricted'
        return 'http_error'
    if isinstance(error,ValueError) and str(error)=='URL denied': return 'url_denied'
    return 'navigation_error'

def verify(execution, expected_worker=None):
    expected={'mary','jeff'} if not expected_worker else {expected_worker}
    if expected_worker and expected_worker not in {'mary','jeff'}:
        raise ValueError('Unknown worker scope')
    actual=[row.get('worker') for row in execution.get('results',[])]
    if set(actual)!=expected or len(actual)!=len(expected):
        raise ValueError('Audit scope mismatch')
    results=[]
    for row in execution['results']:
        proof={'worker':row['worker'],'url':row['url'],'checked_at':datetime.now(timezone.utc).isoformat(),'mechanism':'independent_urllib_get','passed':False,'scope':'public pages only; no logo, cart, checkout, indexing, or post claims'}
        try:
            status,html=fetch(row.get('final_url',row['url']))
            proof.update(http_status=status,sha256=hashlib.sha256(html.encode()).hexdigest())
            if row['worker']=='mary':
                matches=[p for p in row.get('products',[]) if urllib.parse.urlsplit(p['url']).path in html]
                proof['confirmed_products']=matches
                product_url=row.get('product_navigation',{}).get('url','')
                if not row.get('browser_passed'):
                    proof['classification']='browser_incomplete'
                elif not matches:
                    proof['classification']='product_links_unverified'
                elif not product_url:
                    proof['classification']='product_navigation_missing'
                else:
                    pstatus,phtml=fetch(product_url)
                    proof['product_http_status']=pstatus
                    proof['passed']=bool(pstatus==200 and 'cigar' in phtml.lower())
                    proof['classification']='public_product_page_verified' if proof['passed'] else 'product_content_unverified'
            else:
                proof['passed']=bool(row.get('browser_passed') and status==200)
                proof['classification']='public_page_verified' if proof['passed'] else 'browser_incomplete'
        except Exception as e:
            proof['classification']=classify_error(e)
            proof['error']=str(e)[:300]
            if isinstance(e,urllib.error.HTTPError): proof['http_status']=e.code
        results.append(proof)
    return {'version':2,'execution':execution,'verification':results,'overall_passed':bool(results) and all(row['passed'] for row in results),'scope':sorted(expected)}

if __name__=='__main__':
    execution=json.load(open('browser-output/execution.json'))
    result=verify(execution,os.environ.get('JO_AUDIT_WORKER'))
    json.dump(result,open('browser-output/result.json','w'),indent=2)
    print(json.dumps(result['verification'],indent=2))
    if not result['overall_passed']:
        raise SystemExit('Independent public audit verification failed; inspect classification')
