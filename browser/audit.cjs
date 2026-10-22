const {chromium}=require('playwright');
const fs=require('node:fs');
const {permitted}=require('./policy.cjs');
// Fixed operations; untrusted page text is never interpreted as commands.
function cleanText(html){return html.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi,' ').replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi,' ').replace(/<[^>]+>/g,' ').replace(/\s+/g,' ').trim();}
function pageTitle(html){const m=html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);return m?cleanText(m[1]).slice(0,300):'';}
function productLinks(html,base){
 const seen=new Set(), links=[];
 for(const m of html.matchAll(/href\s*=\s*["']([^"']+)["']/gi)){
  try{
   const url=new URL(m[1].replace(/&amp;/g,'&'),base).toString();
   if(permitted(url)&&new URL(url).pathname.includes('/products/')&&!seen.has(url)){seen.add(url);links.push({url,text:''});}
  }catch{}
  if(links.length>=30) break;
 }
 return links;
}
async function boundedFetch(url,redirects=0){
 if(!permitted(url)) throw new Error('Fallback URL denied');
 if(redirects>3) throw new Error('Too many redirects');
 const response=await fetch(url,{redirect:'manual',headers:{'User-Agent':'Jo-OS-Public-Audit/1.0','Accept':'text/html,application/xhtml+xml'}});
 if(response.status>=300&&response.status<400){
  const location=response.headers.get('location');
  if(!location) throw new Error('Redirect missing location');
  return boundedFetch(new URL(location,url).toString(),redirects+1);
 }
 const body=Buffer.from(await response.arrayBuffer());
 if(body.length>2_000_000) throw new Error('Fallback response too large');
 return {status:response.status,url:response.url||url,html:body.toString('utf8')};
}
async function main(){
 if(process.env.JO_AUDIT_WORKER && !['mary','jeff'].includes(process.env.JO_AUDIT_WORKER)) throw new Error('Unknown worker scope');
 fs.mkdirSync('browser-output',{recursive:true});
 const browser=await chromium.launch({args:['--disable-background-networking','--disable-component-update','--disable-sync','--disable-extensions']});
 const results=[];
 const auditScope=process.env.JO_AUDIT_WORKER||'combined';
 for(const [worker,url] of [['mary','https://cigar30-shop.fourthwall.com/'],['jeff','https://cigars30jax.com/']].filter(([worker])=>!process.env.JO_AUDIT_WORKER||process.env.JO_AUDIT_WORKER===worker)){
  const context=await browser.newContext({javaScriptEnabled:false,acceptDownloads:false,serviceWorkers:'block',permissions:[]});
  let denied=0;
  await context.route('**/*',async route=>{
   const req=route.request();
   if(!permitted(req.url(),req.method(),req.resourceType())){denied++;return route.abort('blockedbyclient');}
   return route.continue();
  });
  await context.routeWebSocket('**/*',ws=>ws.close());
  const page=await context.newPage();
  page.on('download',d=>d.cancel());
  page.on('popup',p=>p.close());
  const r={worker,url,checked_at:new Date().toISOString(),scope:'public_read_only_audit',products:[],transport:'playwright'};
  try{
   const response=await page.goto(url,{waitUntil:'domcontentloaded',timeout:30000});
   r.status=response.status();r.final_url=page.url();r.title=await page.title();
   const links=await page.locator('a[href]').evaluateAll(as=>as.map(a=>({url:a.href,text:(a.textContent||'').trim().slice(0,200)})));
   r.products=links.filter(l=>permitted(l.url)&&new URL(l.url).pathname.includes('/products/')).filter((l,i,a)=>a.findIndex(x=>x.url===l.url)===i).slice(0,30);
   r.browser_passed=r.status===200&&permitted(r.final_url)&&(worker!=='mary'||r.products.length>0);
   if(worker==='mary'&&!r.browser_passed){
    r.browser_status=r.status;
    const fallback=await boundedFetch(url);
    r.transport='bounded_https_fallback';
    r.status=fallback.status;r.final_url=fallback.url;r.title=pageTitle(fallback.html);
    r.products=productLinks(fallback.html,fallback.url);
    if(r.products.length){
     const product=await boundedFetch(r.products[0].url);
     r.product_navigation={url:product.url,title:pageTitle(product.html),body_excerpt:cleanText(product.html).slice(0,2000)};
    }
    r.fallback_passed=r.status===200&&permitted(r.final_url)&&r.products.length>0&&Boolean(r.product_navigation);
   }else if(worker==='mary'&&r.products.length){
    const product=r.products[0];
    await page.locator('a[href]').filter({hasText:product.text}).first().click({timeout:15000}).catch(()=>page.goto(product.url,{waitUntil:'domcontentloaded',timeout:15000}));
    r.product_navigation={url:page.url(),title:await page.title(),body_excerpt:(await page.locator('body').innerText()).slice(0,2000)};
   }
   await page.screenshot({path:'browser-output/'+worker+'.png',fullPage:false});
  }catch(e){r.browser_passed=false;r.fallback_passed=false;r.error=String(e.message).slice(0,300);}
  r.denied_requests=denied;console.log(JSON.stringify(r));results.push(r);await context.close();
 }
 await browser.close();
 fs.writeFileSync('browser-output/execution.json',JSON.stringify({version:2,scope:auditScope,results},null,2));
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
