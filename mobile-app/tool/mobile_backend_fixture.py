"""QA only: imports the unchanged web backend; uses synthetic object results, no model/network calls."""
import sys, time
from pathlib import Path
from dataclasses import replace
import uvicorn
web = Path(sys.argv[1]).resolve()
sys.path.insert(0,str(web))
from backend.config import Settings
from backend.main import create_app
from backend.providers.base import ProviderResult
from backend.events import Extraction
class FixtureProvider:
    name='mobile-qa-synthetic'; model='synthetic-no-inference'; is_mock=True
    def ready(self): pass
    def extract(self, *, window, entities, **kw):
        time.sleep(.3)
        obj=next((e for e in entities if e.get('entity_type')=='object'),None)
        loc=next((e for e in entities if e.get('entity_type')=='location'),None)
        oid=obj['id'] if obj else 'test-key'; lid=loc['id'] if loc else 'test-desk'
        return ProviderResult(Extraction.model_validate({'entities': ([obj] if obj else [{'id':oid,'label':'QA key','entity_type':'object'}])+([loc] if loc else [{'id':lid,'label':'QA desk','entity_type':'location'}]), 'events':[{'subject_id':oid,'target_id':lid,'action':'seen_at','frame_ids':[window['frames'][0]['id']]}]}), {'input_tokens':0,'output_tokens':0,'cost':0})
binpath=Path('D:/AndroidDev/ffmpeg/ffmpeg-9.0.2-essentials_build/bin')
settings=Settings(data_dir=Path('D:/AndroidDev/qa-v120-backend'), allowed_hosts=('127.0.0.1','localhost','10.0.2.2'), ffmpeg=str(binpath/'ffmpeg.exe'), ffprobe=str(binpath/'ffprobe.exe'), hybrid_safety_enabled=False, activity_filter_enabled=False)
app=create_app(settings, FixtureProvider())
if __name__=='__main__': uvicorn.run(app,host='127.0.0.1',port=18020,log_level='warning')
