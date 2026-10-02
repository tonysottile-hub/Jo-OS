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
            if getattr(e,"code",None) not in (429,500,502,503,504):raise
            time.sleep(min(20,2**n)+random.random())
    raise last
def api(params):
    q=urllib.parse.urlencode({**params,"format":"json","formatversion":"2","origin":"*"})
    return json.loads(get(API+"?"+q,30).decode())
def clean(s):
    s=re.sub(r"<[^>]+>"," ",s or "")
    return html.unescape(re.sub(r"\s+"," ",s)).strip()
def main():
    p=argparse.ArgumentParser()
    p.add_argument("--query",action="append",required=True)
    p.add_argument("--place")
    p.add_argument("--category")
    p.add_argument("--file-title",action="append",default=[])
    p.add_argument("--out-dir",required=True)
    p.add_argument("--manifest",required=True)
    p.add_argument("--count",type=int,default=6)
    p.add_argument("--duration",type=float,default=8)
    a=p.parse_args();out=pathlib.Path(a.out_dir);out.mkdir(parents=True,exist_ok=True)
    candidates=[];seen=set()
    reject=re.compile(r"\b(cemetery|grave|graves|headstone|headstones|tombstone|tombstones|memorial\s+park|burial|funeral|stereoscopic|stereo|cross[ -]?eyed|3d)\b",re.I)
    place=re.compile(r"\b"+re.escape(a.place.strip())+r"\b",re.I) if a.place and a.place.strip() else None
    goldfield_conflicting=re.compile(r"\b(hawthorne|aurora|mineral county courthouse|juniata mill)\b",re.I) if (a.place or "").strip().lower()=="goldfield" else None
    batches=[]
    if a.file_title:
        titles=[t if t.lower().startswith("file:") else "File:"+t for t in a.file_title]
        for i in range(0,len(titles),40):
            search=api({"action":"query","titles":"|".join(titles[i:i+40]),
              "prop":"imageinfo","iiprop":"url|size|mime|extmetadata","iiurlwidth":1600})
            batches.append(("explicit_files",search.get("query",{}).get("pages",[])))
    for query in a.query:
        search=api({"action":"query","generator":"search","gsrsearch":query+" filetype:bitmap","gsrnamespace":6,"gsrlimit":50,"gsrwhat":"text",
          "prop":"imageinfo","iiprop":"url|size|mime|extmetadata","iiurlwidth":1600})
        batches.append((query,search.get("query",{}).get("pages",[])))
    if a.category and a.category.strip():
        cat=a.category.strip()
        if not cat.lower().startswith("category:"):cat="Category:"+cat
        search=api({"action":"query","generator":"categorymembers","gcmtitle":cat,"gcmnamespace":6,"gcmtype":"file","gcmlimit":100,
          "prop":"imageinfo","iiprop":"url|size|mime|extmetadata","iiurlwidth":1600})
        batches.append((cat,search.get("query",{}).get("pages",[])))
    for query,pages in batches:
        for page in pages:
            ii=(page.get("imageinfo") or [{}])[0]
            if not ii.get("mime","").startswith("image/"):continue
            w,h=ii.get("width",0),ii.get("height",0)
            if min(w,h)<500:continue
            meta=ii.get("extmetadata",{});title=page.get("title") or "";desc=clean(meta.get("ImageDescription",{}).get("value"))
            cats=clean(meta.get("Categories",{}).get("value"));credit=clean(meta.get("Credit",{}).get("value"));loc=clean(meta.get("Location",{}).get("value"))
            md=" ".join((title,desc,cats,credit,loc))
            if reject.search(md):continue
            if goldfield_conflicting and goldfield_conflicting.search(md):continue
            if place and not place.search(md):continue
            url=ii.get("thumburl") or ii.get("url")
            if not url or url in seen:continue
            seen.add(url);candidates.append({"title":title,"url":url,"source_url":ii.get("descriptionurl"),"width":w,"height":h,
              "license":clean(meta.get("LicenseShortName",{}).get("value")),"license_url":clean(meta.get("LicenseUrl",{}).get("value")),
              "artist":clean(meta.get("Artist",{}).get("value")),"credit":credit,"description":desc,"categories":cats,"location":loc,"matched_query":query})
    candidates.sort(key=lambda x:x["width"]*x["height"],reverse=True)
    assets=[];sources=[];hotel_count=0
    for c in candidates:
        if len(assets)>=a.count:break
        is_goldfield_hotel=(a.place or "").strip().lower()=="goldfield" and bool(re.search(r"\bgoldfield hotel\b",c["title"]+" "+c["description"],re.I))
        if is_goldfield_hotel and hotel_count>=2:continue
        try:data=get(c["url"],60);time.sleep(1.2)
        except Exception as e:print("skip",c["title"],repr(e));continue
        ext=pathlib.Path(urllib.parse.urlparse(c["url"]).path).suffix.lower()
        if ext not in {".jpg",".jpeg",".png",".webp"}:ext=".jpg"
        dest=out/f"commons-{len(assets)+1:02d}{ext}";dest.write_bytes(data)
        assets.append({"path":str(dest),"duration":a.duration});sources.append({**c,"local_path":str(dest)})
        if is_goldfield_hotel:hotel_count+=1
    if len(assets)<3:raise SystemExit(f"Only {len(assets)} suitable Commons images downloaded")
    pathlib.Path(a.manifest).write_text(json.dumps({"assets":assets,"duration_per_asset":a.duration,"required_place":a.place,"media_sources":sources},indent=2)+"\n")
    print(json.dumps({"queries":a.query,"required_place":a.place,"downloaded":len(assets),"manifest":a.manifest,"sources":sources},indent=2))
if __name__=="__main__":main()
