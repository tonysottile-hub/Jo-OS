"""Independent HTTP verifier. No browser evidence can self-certify success."""
import json, hashlib, urllib.request, urllib.parse, os
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
execution=json.load(open('browser-output/execution.json'))
expected_worker=os.environ.get('JO_AUDIT_WORKER')
if expected_worker and expected_worker not in {'mary','jeff'}:
    raise SystemExit('Unknown worker scope')
expected={'mary','jeff'} if not expected_worker else {expected_worker}
actual=[row.get('worker') for row in execution.get('results',[])]
if set(actual)!=expected or len(actual)!=len(expected):
    raise SystemExit('Audit scope mismatch: expected '+repr(sorted(expected))+'; got '+repr(actual))
results=[]
for row in execution['results']:
    proof={'worker':row['worker'],'url':row['url'],'checked_at':datetime.now(timezone.utc).isoformat(),'mechanism':'independent_urllib_get','passed':False}
    try:
        status,html=fetch(row.get('final_url',row['url']))
        proof.update(http_status=status,sha256=hashlib.sha256(html.encode()).hexdigest())
        if row['worker']=='mary':
            matches=[p for p in row['products'] if urllib.parse.urlsplit(p['url']).path in html]
            proof['confirmed_products']=matches
            product_url=row.get('product_navigation',{}).get('url','')
            if not product_url: raise ValueError('Browser could not navigate storefront: HTTP '+str(row.get('status','unknown')))
            pstatus,phtml=fetch(product_url)
            proof['product_http_status']=pstatus
            proof['passed']=bool(row.get('browser_passed') and matches and pstatus==200 and 'cigar' in phtml.lower())
        else:
            proof['passed']=bool(row.get('browser_passed') and status==200)
        proof['scope']='public pages only; no logo, cart, checkout, indexing, or post claims'
    except Exception as e:
        proof['error']=str(e)[:300]
    results.append(proof)
overall_passed=bool(results) and all(row['passed'] for row in results)
json.dump({'version':1,'execution':execution,'verification':results,'overall_passed':overall_passed,'scope':sorted(expected)},open('browser-output/result.json','w'),indent=2)
print(json.dumps(results,indent=2))
if not overall_passed:
    raise SystemExit('Independent public audit verification failed')
