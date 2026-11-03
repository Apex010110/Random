import json, glob, subprocess, sys
from PIL import Image
import numpy as np
FPS=30
stages=json.load(open('stages.pptx.stages.json'))
files=sorted(glob.glob('st/f-*.png'))
assert len(files)==len(stages)
imgs=[np.asarray(Image.open(f).convert('RGB'),dtype=np.float32) for f in files]
H,W,_=imgs[0].shape
ff=subprocess.Popen(['ffmpeg','-y','-loglevel','error','-f','rawvideo','-pix_fmt','rgb24','-s',f'{W}x{H}','-r',str(FPS),'-i','-','-c:v','libx264','-pix_fmt','yuv420p','-crf','18','-movflags','+faststart',sys.argv[1]],stdin=subprocess.PIPE)
def emit(a,n=1):
    b=a.clip(0,255).astype(np.uint8).tobytes()
    for _ in range(n): ff.stdin.write(b)
ease=lambda t: t*t*(3-2*t)
xs=np.linspace(0,1,W)[None,:,None]; ys=np.linspace(0,1,H)[:,None,None]
prev=np.zeros_like(imgs[0])+np.array([7,11,27],dtype=np.float32)
for st,img in zip(stages,imgs):
    n=max(1,round(st['fade']/1000*FPS))
    lab=st['label']
    for k in range(1,n+1):
        t=ease(k/n)
        if 'wipeR' in lab: m=np.clip((t*1.15-xs)/0.15,0,1)
        elif 'wipeD' in lab: m=np.clip((t*1.15-ys)/0.15,0,1)
        else: m=t
        emit(prev*(1-m)+img*m)
    emit(img, max(1,round(st['hold']/1000*FPS)))
    prev=img
ff.stdin.close(); ff.wait()
