const {chromium}=require('playwright');
const fs=require('node:fs');
const {permitted}=require('./policy.cjs');
// Fixed operations; untrusted page text is never interpreted as commands.
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
  const r={worker,url,checked_at:new Date().toISOString(),scope:'public_read_only_audit',products:[]};
  try{
   const response=await page.goto(url,{waitUntil:'domcontentloaded',timeout:30000});
   r.status=response.status();r.final_url=page.url();r.title=await page.title();
   const links=await page.locator('a[href]').evaluateAll(as=>as.map(a=>({url:a.href,text:(a.textContent||'').trim().slice(0,200)})));
   r.products=links.filter(l=>permitted(l.url)&&new URL(l.url).pathname.includes('/products/')).filter((l,i,a)=>a.findIndex(x=>x.url===l.url)===i).slice(0,30);
   if(worker==='mary'&&r.products.length){
    const product=r.products[0];
    await page.locator('a[href]').filter({hasText:product.text}).first().click({timeout:15000}).catch(()=>page.goto(product.url,{waitUntil:'domcontentloaded',timeout:15000}));
    r.product_navigation={url:page.url(),title:await page.title(),body_excerpt:(await page.locator('body').innerText()).slice(0,2000)};
   }
   r.browser_passed=r.status===200&&permitted(r.final_url)&&(worker!=='mary'||r.products.length>0);
   await page.screenshot({path:'browser-output/'+worker+'.png',fullPage:false});
  }catch(e){r.browser_passed=false;r.error=String(e.message).slice(0,300);}
  r.denied_requests=denied;console.log(JSON.stringify(r));results.push(r);await context.close();
 }
 await browser.close();
 fs.writeFileSync('browser-output/execution.json',JSON.stringify({version:1,scope:auditScope,results},null,2));
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
