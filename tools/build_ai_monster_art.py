"""Export selected original monster animations with verified native action slots.

The four existing gameplay actors are left byte-identical. New multipart actors
are anchored to a persistent native body part, with explicit extent fallback for
whole-body replacement poses. Source ANI and archive atlases remain unchanged.
"""
import copy,json,hashlib
from pathlib import Path
from PIL import Image
from import_assets import ROOT,ANALYSIS,DEST,TRANSFORMS,parse_ani,bake,readable_json
from native_ani import native_steps,event_masks
from ai_world_monsters import ART_KEYS
LEGACY={'langw','xt1','hs1','nt1'}

def build_asset(name,write_texture=True):
 key='monster/'+name
 original=parse_ani(ANALYSIS/'unpacked/ssjx/monster'/(name+'.ani'))
 playback={mode:native_steps(original,slot) for mode,slot in [('idle',4),('walk',4),('attack',5),('hurt',6)]}
 assert all(playback.values()),key+' missing common native state'
 source=original['sources'][0];folder=ANALYSIS/'decoded_png/ssjx/monster'
 images={}
 for layers in original['frames']:
  for l in layers:
   pair=(l['source'],l['frame'])
   if pair not in images:
    with Image.open(folder/f"{pair[0]}_frame{pair[1]:03}.png") as im:images[pair]=im.copy()
 combat={f for steps in playback.values() for f,_ in steps}
 candidates=None
 for f in combat:
  layers=original['frames'][f]
  counts={n:sum(l['source']==source and l['frame']==n for l in layers) for s,n in images if s==source}
  present={l['frame'] for l in layers if l['source']==source and l['transform'] in (0,4) and counts[l['frame']]==1}
  candidates=present if candidates is None else candidates&present
 anchor=max(candidates,key=lambda n:images[source,n].width*images[source,n].height) if candidates else None
 # Compose transform flags for reflecting an entire original pose, rather than
 # flipping the head while leaving its weapon or attack effect behind.
 sample=Image.new('L',(2,3));sample.putdata([1,2,3,4,5,6])
 variants={n:sample.transpose(t) if n else sample for n,t in {0:None,**TRANSFORMS}.items()}
 flips={n:next(k for k,v in variants.items() if v.size==im.size and v.tobytes()==im.transpose(Image.Transpose.FLIP_LEFT_RIGHT).tobytes()) for n,im in variants.items()}
 aligned=copy.deepcopy(original);centers=[];strategies=[]
 for index,layers in enumerate(original['frames']):
  body=[l for l in layers if l['source']==source and l['frame']==anchor] if anchor is not None else []
  mirrored=len(body)==1 and body[0]['transform']==4
  if len(body)==1 and body[0]['transform'] in (0,4):
   l=body[0];center=l['x']+images[source,l['frame']].width//2;strategy='persistent_body_part'
  else:
   body=[l for l in layers if l['source']==source]
   bounds=[]
   for l in body:
    im=images[source,l['frame']];im=im.transpose(TRANSFORMS[l['transform']]) if l['transform'] else im
    bounds.extend([l['x'],l['x']+im.width])
   if not bounds and index in combat:raise ValueError(key+' has no primary body in combat frame '+str(index))
   center=(min(bounds)+max(bounds))//2 if bounds else 0
   strategy='primary_body_extent' if bounds else 'unused_effect_only'
  centers.append(-center if mirrored else center);strategies.append(strategy)
  for l in aligned['frames'][index]:
   if mirrored:
    im=images[l['source'],l['frame']];im=im.transpose(TRANSFORMS[l['transform']]) if l['transform'] else im
    l['x']=-l['x']-im.width;l['transform']=flips[l['transform']]
   l['x']-=centers[-1]
 info=bake(key,aligned,output_key=key,write_texture=write_texture)
 masks=event_masks(original);ids=dict(idle=4,walk=4,attack=5,hurt=6)
 info['playback']=playback
 info['native_battle']=dict(indexing='reverse_serialized_tables',source_frame_count=len(original['frames']),sequence_ids=ids,
  impact_steps={mode:[i for i in range(len(playback[mode])) if slot<len(masks) and masks[slot]&(1<<i)] for mode,slot in ids.items()},
  attack_x=[centers[f] for f,_ in playback['attack']],pose_x={mode:[centers[f] for f,_ in playback[mode]] for mode in ['idle','walk','hurt']},
  attack_basis='target',cast_mapping=None)
 info['alignment']=dict(source='AI接入，原生动作槽4/5/6',primary_source=source,body_frame=anchor,
  combat_extent_frames=sorted(f for f in combat if strategies[f]=='primary_body_extent'),
  source_sha256=hashlib.sha256((ANALYSIS/'unpacked/ssjx/monster'/(name+'.ani')).read_bytes()).hexdigest())
 return info

def build_assets(write_textures=True):
 return {'monster/'+name:build_asset(name,write_textures) for name in sorted(ART_KEYS-LEGACY)}

def main():
 assets=build_assets();path=DEST/'data/actors.json';index=json.loads(path.read_text(encoding='utf8'))
 for key,info in assets.items():
  target=DEST/'data/actors'/(key+'.json');target.parent.mkdir(parents=True,exist_ok=True)
  target.write_text(readable_json(info)+'\n',encoding='utf8',newline='\n')
  index['actors'][key]='res://assets/data/actors/'+key+'.json'
 index['actors']=dict(sorted(index['actors'].items()))
 path.write_text(json.dumps(index,ensure_ascii=False,indent=2)+'\n',encoding='utf8',newline='\n')
 print('New gameplay monster exports:',len(assets),'total selected:',len(ART_KEYS))

if __name__=='__main__':main()
