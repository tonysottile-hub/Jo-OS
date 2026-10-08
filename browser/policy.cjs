const ORIGINS = new Set(['https://cigar30-shop.fourthwall.com', 'https://cigars30jax.com', 'https://www.cigars30jax.com']);
function permitted(raw, method='GET', type='document') {
  try {
    const u=new URL(raw);
    return ORIGINS.has(u.origin) && !u.username && !u.password && !u.search &&
      method==='GET' && type==='document' &&
      (u.pathname==='/' || u.pathname==='/robots.txt' || u.pathname==='/sitemap.xml' ||
        /^\/(products|collections)\/[a-zA-Z0-9_-]+\/?$/.test(u.pathname));
  } catch { return false; }
}
module.exports={permitted};
