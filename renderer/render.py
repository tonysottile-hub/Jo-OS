#!/usr/bin/env python3
import argparse, json, pathlib, subprocess, sys

def run(cmd):
    subprocess.run(cmd, check=True)

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--manifest",required=True)
    p.add_argument("--output",required=True)
    a=p.parse_args()
    m=json.loads(pathlib.Path(a.manifest).read_text())
    assets=m.get("assets",[])
    if not assets: raise SystemExit("manifest requires assets")
    duration=float(m.get("duration_per_asset",4))
    out=pathlib.Path(a.output); out.parent.mkdir(parents=True,exist_ok=True)
    concat=out.with_suffix(".concat.txt")
    lines=[]
    for item in assets:
        path=pathlib.Path(item["path"]).resolve()
        if not path.exists(): raise SystemExit(f"missing asset: {path}")
        lines += [f"file '{path.as_posix()}'",f"duration {float(item.get('duration',duration))}"]
    lines.append(f"file '{pathlib.Path(assets[-1]['path']).resolve().as_posix()}'")
    concat.write_text("\n".join(lines)+"\n")
    vf="scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2,format=yuv420p"
    cmd=["ffmpeg","-y","-f","concat","-safe","0","-i",str(concat)]
    audio=m.get("audio")
    if audio:
        cmd += ["-i",audio]
    cmd += ["-vf",vf,"-r","30","-c:v","libx264","-preset","medium","-crf","20"]
    if audio: cmd += ["-c:a","aac","-b:a","192k","-shortest"]
    else: cmd += ["-an"]
    cmd += ["-movflags","+faststart",str(out)]
    run(cmd)
    run(["ffprobe","-v","error","-show_entries","format=duration,size:stream=codec_name,codec_type,width,height","-of","json",str(out)])
    print(out)
if __name__=="__main__": main()
