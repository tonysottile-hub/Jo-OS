#!/usr/bin/env python3
import argparse,json,pathlib,urllib.parse,urllib.request,re,html

API="https://commons.wikimedia.org/w/api.php"
UA="Jo-OS-UnmappedAmerica/1.0 (automated media sourcing; Wikimedia Commons)"

def api(params):
    q=urllib.parse.urlencode({**params,"format":"json","formatversion":"2"})
    req=urllib.request.Request(API+"?"+q,headers={"User-Agent":UA})
    with urllib.request.urlopen(req,timeout=30) as r:return json.load(r)

def clean(s):
    s=re.sub(r"<[^>]+>"," ",s or "")
    return html.unescape(re.sub(r"\s+"," ",s)).strip()

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--query",required=True)
    p.add_argument("--out-dir",required=True)
    p.add_argument("--manifest",required=True)
    p.add_argument("--count",type=int,default=6)
    p.add_argument("--duration",type=float,default=8.0)
    a=p.parse_args()
    out=pathlib.Path(a.out_dir);out.mkdir(parents=True,exist_ok=True)
    search=api({"action":"query","generator":"search","gsrsearch":a.query+" filetype:bitmap","gsrnamespace":6,
      "gsrlimit":min(max(a.count*5,20),50),"prop":"imageinfo","iiprop":"url|size|mime|extmetadata"})
    candidates=[]
    for page in search.get("query",{}).get("pages",[]):
        ii=(page.get("imageinfo") or [{}])[0]; mime=ii.get("mime","")
        if not mime.startswith("image/"):continue
        w,h=ii.get("width",0),ii.get("height",0)
        if min(w,h)<800:continue
        meta=ii.get("extmetadata",{})
        candidates.append({"title":page.get("title"),"url":ii.get("url"),"width":w,"height":h,
          "license":clean(meta.get("LicenseShortName",{}).get("value")),
          "artist":clean(meta.get("Artist",{}).get("value")),
          "credit":clean(meta.get("Credit",{}).get("value")),
          "description":clean(meta.get("ImageDescription",{}).get("value"))})
    candidates.sort(key=lambda x:(x["width"]*x["height"]),reverse=True)
    assets=[]; sources=[]
    for i,c in enumerate(candidates[:a.count],1):
        ext=pathlib.Path(urllib.parse.urlparse(c["url"]).path).suffix.lower()
        if ext not in {".jpg",".jpeg",".png",".webp"}:ext=".jpg"
        dest=out/f"commons-{i:02d}{ext}"
        req=urllib.request.Request(c["url"],headers={"User-Agent":UA})
        with urllib.request.urlopen(req,timeout=60) as r:dest.write_bytes(r.read())
        assets.append({"path":str(dest),"duration":a.duration})
        sources.append({**c,"local_path":str(dest)})
    if not assets:raise SystemExit("No suitable Commons images found")
    pathlib.Path(a.manifest).write_text(json.dumps({"assets":assets,"duration_per_asset":a.duration,
      "media_sources":sources},indent=2)+"\n")
    print(json.dumps({"query":a.query,"downloaded":len(assets),"manifest":a.manifest,
      "sources":sources},indent=2))
if __name__=="__main__":main()
