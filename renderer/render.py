#!/usr/bin/env python3
import argparse, json, pathlib, subprocess, sys

def run(cmd):
    subprocess.run(cmd, check=True)

def layout(manifest):
    kind=manifest.get("kind","short")
    if kind not in ("short","long"): raise ValueError("unsupported video kind")
    return (1920,1080) if kind=="long" else (1080,1920)

def visual_durations(manifest, audio_seconds=None):
    assets=manifest.get("assets",[])
    if not assets: raise ValueError("manifest requires assets")
    if manifest.get("kind","short")=="long":
        if audio_seconds is None or not 120 <= audio_seconds <= 1800:
            raise ValueError("long-form requires 2-30 minutes of narration")
        # Match the narration instead of truncating it to a short image sequence.
        return [audio_seconds/len(assets)]*len(assets)
    return [float(x.get("duration",manifest.get("duration_per_asset",4))) for x in assets]

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--manifest",required=True)
    p.add_argument("--output",required=True)
    a=p.parse_args()
    m=json.loads(pathlib.Path(a.manifest).read_text())
    assets=m.get("assets",[])
    if not assets: raise SystemExit("manifest requires assets")
    duration=float(m.get("duration_per_asset",4))
    width,height=layout(m)
    audio=m.get("audio")
    audio_seconds=None
    if audio:
        audio_seconds=float(subprocess.check_output(["ffprobe","-v","error","-show_entries","format=duration","-of","default=noprint_wrappers=1:nokey=1",audio],text=True).strip())
    durations=visual_durations(m,audio_seconds)
    out=pathlib.Path(a.output); out.parent.mkdir(parents=True,exist_ok=True)
    concat=out.with_suffix(".concat.txt")
    lines=[]
    for item,seconds in zip(assets,durations):
        path=pathlib.Path(item["path"]).resolve()
        if not path.exists(): raise SystemExit(f"missing asset: {path}")
        if "'" in path.as_posix() or "\n" in path.as_posix(): raise ValueError("unsafe asset filename")
        lines += [f"file '{path.as_posix()}'",f"duration {seconds}"]
    lines.append(f"file '{pathlib.Path(assets[-1]['path']).resolve().as_posix()}'")
    concat.write_text("\n".join(lines)+"\n")
    # Fill the 9:16 canvas without letterboxing. Keep concat timing intact;
    # motion is applied with a time-based crop/scale chain rather than zoompan,
    # because zoompan d=1 collapses concat still-image durations.
    vf=f"scale={width+120}:{height+214}:force_original_aspect_ratio=increase,crop={width}:{height}:x='(iw-ow)/2+20*sin(t*0.35)':y='(ih-oh)/2+20*cos(t*0.27)',format=yuv420p"
    cmd=["ffmpeg","-y","-f","concat","-safe","0","-i",str(concat)]
    if audio:
        cmd += ["-i",audio]
    cmd += ["-vf",vf,"-r","30","-c:v","libx264","-preset","medium","-crf","20"]
    if audio: cmd += ["-c:a","aac","-b:a","192k","-shortest"]
    else: cmd += ["-an"]
    cmd += ["-movflags","+faststart",str(out)]
    run(cmd)
    probe=json.loads(subprocess.check_output(["ffprobe","-v","error","-show_entries","format=duration,size:stream=codec_name,codec_type,width,height","-of","json",str(out)]))
    actual=float(probe["format"]["duration"])
    expected=sum(durations)
    # With narration and -shortest, output may end at narration length, but a near-zero
    # render is always a production failure rather than a valid artifact.
    if actual < min(5.0, expected * 0.5):
        raise SystemExit(f"render duration invalid: actual={actual:.3f}s expected_visual={expected:.3f}s")
    if m.get("kind")=="long" and abs(actual-audio_seconds)>2:
        raise SystemExit("long-form narration truncated or padded unexpectedly")
    print(json.dumps(probe))
    print(out)
if __name__=="__main__": main()
