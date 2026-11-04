"""Run the ORIGINAL backend against isolated synthetic data. Never calls a model.
Usage: python original_api_fixture.py --original-root <project> --data-dir <empty-test-dir>
The test service binds only to localhost. Port 18000 can be adb-reversed.
"""
from pathlib import Path
import argparse, hashlib, sys
import cv2
import numpy as np
import uvicorn

p=argparse.ArgumentParser()
p.add_argument('--original-root', required=True)
p.add_argument('--data-dir', required=True)
args=p.parse_args()
sys.path.insert(0,str(Path(args.original_root).resolve()))
from backend.main import create_app
from backend.config import Settings
from backend.events import Extraction, normalize

class NoNetworkProvider:
    name, model, is_mock = 'SYNTHETIC_QA', 'handwritten-contract-fixture', True
    def ready(self): raise AssertionError('Model calls forbidden during contract QA')
    def extract(self, **kwargs): raise AssertionError('Model calls forbidden during contract QA')

root=Path(args.data_dir).resolve()
root.mkdir(parents=True,exist_ok=True)
settings=Settings(data_dir=root, enable_network=False, enhanced_safety_sampling=False)
app=create_app(settings,NoNetworkProvider())
db=app.state.db
video_path=root/'synthetic-contract-only.mp4'
writer=cv2.VideoWriter(str(video_path),cv2.VideoWriter_fourcc(*'mp4v'),10,(640,360))
assert writer.isOpened()
for i in range(40):
    image=np.full((360,640,3),35,np.uint8)
    cv2.rectangle(image,(80,170),(560,300),(100,140,160),-1)
    cv2.circle(image,(200+i,200),15,(40,210,240),3)
    cv2.putText(image,'SYNTHETIC API TEST - NOT AI OUTPUT',(25,45),cv2.FONT_HERSHEY_SIMPLEX,.7,(240,240,240),1)
    writer.write(image)
writer.release()
frames=[{'id':'f1','pts_ms':0,'kind':'sampled'},{'id':'f2','pts_ms':1000,'kind':'sampled'}]
frame_dir=root/'runs'/'qa-run'/'frames'
frame_dir.mkdir(parents=True,exist_ok=True)
for f in frames: cv2.imwrite(str(frame_dir/(f['id']+'.jpg')),image)
if not db.list_videos():
    video={'id':'qa-video','sha256':hashlib.sha256(video_path.read_bytes()).hexdigest(),'name':'合成接口验收录像（非模型识别）','duration_ms':4000,'original_path':str(video_path),'playback_path':str(video_path),'metadata':{}}
    db.add_video(video)
    job={'id':'qa-run','video_id':'qa-video','status':'completed','is_mock':True,'skipped_static_ranges':[]}
    db.save_job(job)
    raw=Extraction.model_validate({'entities':[{'id':'keys','label':'钥匙','entity_type':'object'},{'id':'table','label':'测试桌面','entity_type':'location'}],'events':[{'subject_id':'keys','target_id':'table','action':'place_on','frame_ids':['f1','f2']}]})
    entities,evidence,events=normalize(raw,'qa-video',{'frames':frames,'start_ms':0},{})
    document=app.state.manager.document(video,frames,entities,evidence,events)
    db.save_memory('qa-run',document,job)
uvicorn.run(app,host='127.0.0.1',port=18000,log_level='info')
