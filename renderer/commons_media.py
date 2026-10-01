#!/usr/bin/env python3
import argparse,json,pathlib,urllib.parse,urllib.request,re,html,time,random

API="https://commons.wikimedia.org/w/api.php"
UA="Jo-OS-UnmappedAmerica/1.0 (automated media sourcing; contact via repository tonysottile-hub/Jo-OS)"

def get(url,timeout=60,retries=5):
    last=None
    for n in range(retries):
        try:
            req=urllib.request.Request(url,headers={"User-Agent":UA,"Accept":"application/json,image/*,*/*;q=0.8"})
            with urllib.request.urlopen(req,timeout=timeout) as r:return r.read()
        except Exception as e:
            last=e
            if getattr(e,"code",None) not in (429,500,502,503,504): raise
            time.sleep(min(20,2**n)+random.random())
    raise last

def api(params):
    q=urllib.parse.urlencode({**params,"format":"json","formatversion":"2","origin":"*"})
    return json.loads(get(API+"?"+q,30).decode("utf-8"))

def clean(s):
    s=re.sub(r"<[^>]+>"," ",s or "")
    return html.unescape(re.sub(r"\s+"," ",s)).strip()

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--query",required=True);p.add_argument("--out-dir",required=True)
    p.add_argument("--manifest",required=True);p.add_argument("--count",type=int,default=6)
    p.add_argument("--duration",type=float,default=8.0)
    a=p.parse_args();out=pathlib.Path(a.out_dir);out.mkdir(parents=True,exist_ok=True)
    search=api({"action":"query","generator":"search","gsrsearch":a.query+" filetype:bitmap","gsrnamespace":6,
      "gsrlimit":min(max(a.count*4,16),40),"prop":"imageinfo",
      "iiprop":"url|size|mime|extmetadata","iiurlwidth":1600})
    candidates=[]
    for page in search.get("query",{}).get("pages",[]):
        ii=(page.get("imageinfo") or [{}])[0];mime=ii.get("mime","")
        if not mime.startswith("image/"):continue
        w,h=ii.get("width",0),ii.get("height",0)
        if min(w,h)<800:continue
        meta=ii.get("extmetadata",{})
        candidates.append({"title":page.get("title"),"url":ii.get("thumburl") or ii.get("url"),
          "source_url":ii.get("descriptionurl"),"width":w,"height":h,
          "license":clean(meta.get("LicenseShortName",{}).get("value")),
          "license_url":clean(meta.get("LicenseUrl",{}).get("value")),
          "artist":clean(meta.get("Artist",{}).get("value")),
          "credit":clean(meta.get("Credit",{}).get("value")),
          "description":clean(meta.get("ImageDescription",{}).get("value"))})
    candidates.sort(key=lambda x:(x["width"]*x["height"]),reverse=True)
    assets=[];sources=[]
    for i,c in enumerate(candidates,1):
        if len(assets)>=a.count:break
        try:
            data=get(c["url"],60); time.sleep(1.2)
        except Exception as e:
            print("skip download",c["title"],repr(e));continue
        ext=pathlib.Path(urllib.parse.urlparse(c["url"]).path).suffix.lower().split("?")[0]
        if ext not in {".jpg",".jpeg",".png",".webp"}:ext=".jpg"
        dest=out/f"commons-{len(assets)+1:02d}{ext}";dest.write_bytes(data)
        assets.append({"path":str(dest),"duration":a.duration});sources.append({**c,"local_path":str(dest)})
    if len(assets)<3:raise SystemExit(f"Only {len(assets)} suitable Commons images downloaded")
    pathlib.Path(a.manifest).write_text(json.dumps({"assets":assets,"duration_per_asset":a.duration,
      "media_sources":sources},indent=2)+"\n")
    print(json.dumps({"query":a.query,"downloaded":len(assets),"manifest":a.manifest,"sources":sources},indent=2))
if __name__=="__main__":main()
