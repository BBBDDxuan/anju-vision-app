"""B integration fixture: real A HTTP handlers, temporary synthetic data only.

Never opens a camera, calls a paid model, or edits the backend repository.
The source collector is replaced on this test app instance to retain explicitly
seeded projections; this is transport/contract validation, not recognition QA.
"""
from pathlib import Path
from types import SimpleNamespace
from datetime import datetime, timezone
import argparse,json,sys,tempfile,subprocess

parser=argparse.ArgumentParser()
parser.add_argument('--backend-root',required=True)
parser.add_argument('--ffmpeg-dir',required=True)
parser.add_argument('--ready-file',required=True)
parser.add_argument('--port',type=int,default=18031)
args=parser.parse_args()
backend=Path(args.backend_root).resolve()
sys.path.insert(0,str(backend))
import cv2,numpy as np,httpx,uvicorn
from backend.config import Settings
from backend.phone_app import create_app
from backend.alert_center import alert_id
from tests.conftest import MockVisionProvider

token='b-contract-fixture-'+'x'*32
with tempfile.TemporaryDirectory(prefix='anju-b-contract-') as directory:
 root=Path(directory)
 ffmpeg=Path(args.ffmpeg_dir)
 settings=Settings(data_dir=root/'data',allowed_hosts=('127.0.0.1','localhost','10.0.2.2'),
   lan_token=token,hybrid_safety_enabled=False,enhanced_safety_sampling=False,
   ffmpeg=str(ffmpeg/'ffmpeg.exe'),ffprobe=str(ffmpeg/'ffprobe.exe'))
 def upstream(request):
  if request.url.path.endswith('/preferences'):
   return httpx.Response(200,json={'escalation_seconds':60,'notifications_enabled':True,
      'contacts':[{'contact_id':'primary','name':'Contract fixture'}]})
  return httpx.Response(200,json=[])
 app=create_app(settings,MockVisionProvider(),
   safety_repo=SimpleNamespace(s=SimpleNamespace(user_token='fixture-internal-not-production')),
   transport=httpx.MockTransport(upstream))
 app.state.alert_sources.sync=lambda:None
 # Deterministic embeddings only on this isolated fixture. Transport/lifecycle
 # checks must never enroll a real person or depend on detector accuracy.
 feature=np.zeros(128,dtype='<f4');feature[0]=1
 app.state.face_recognition._features=lambda data:[{'feature':feature,'bbox':[.1,.1,.8,.8],
   'detection_score':.99,'quality':'usable'}]
 app.state.alert_sources.status={source:{'ready':True} for source in ('live_camera','uploaded_recording')}
 frame=root/'synthetic.jpg'
 assert cv2.imwrite(str(frame),np.zeros((32,32,3),dtype=np.uint8))
 center=app.state.alert_center
 for source in ('live_camera','uploaded_recording'):
  identifier=alert_id(source,'B_SYNTHETIC_CONTRACT_ONLY')
  image=center.save_image(identifier,0,frame,root)
  center.upsert({'id':identifier,'source':source,'source_key':'B_SYNTHETIC_CONTRACT_ONLY',
    'source_event_id':'B_SYNTHETIC_CONTRACT_ONLY','camera_id':'fixture-camera' if source=='live_camera' else None,
    'video_id':'fixture-recording' if source=='uploaded_recording' else None,
    'run_id':'fixture-run' if source=='uploaded_recording' else None,
    'title':'SYNTHETIC CONTRACT ONLY','event_type':'help_requested','severity':'critical',
    'occurred_at':datetime.now(timezone.utc).isoformat() if source=='live_camera' else None,
    'video_offset_ms':1200 if source=='uploaded_recording' else None,
    'review_status':'confirmed','review_model':'SYNTHETIC_FIXTURE_NO_MODEL_CALL',
    'review_reason':'Contract projection only; no camera or real recognition',
    'evidence':[image],'evidence_status':'available','playback_url':None},historical=True)
 raw=root/'raw-synthetic.mp4'
 video=root/'synthetic.mp4'
 writer=cv2.VideoWriter(str(raw),cv2.VideoWriter_fourcc(*'mp4v'),10,(320,180))
 assert writer.isOpened()
 for n in range(120):
  frame=np.zeros((180,320,3),dtype=np.uint8)
  cv2.rectangle(frame,(10+n,90),(35+n,115),(100,210,80),-1)
  writer.write(frame)
 writer.release()
 # H.264 fixture exercises phone upload without hiding the separately recorded
 # A/FFmpeg9 legacy -vsync incompatibility on codecs requiring transcoding.
 subprocess.run([str(ffmpeg/'ffmpeg.exe'),'-v','error','-y','-i',str(raw),
   '-c:v','libx264','-pix_fmt','yuv420p','-an',str(video)],check=True,capture_output=True)
 Path(args.ready_file).write_text(json.dumps({'synthetic':True,'base_url':f'http://127.0.0.1:{args.port}',
   'video_path':str(video),'backend_revision':'d272b8737ddd59a33e66b79ef120e60bf6d2be6b'}),encoding='utf-8')
 uvicorn.run(app,host='127.0.0.1',port=args.port,log_level='warning')
