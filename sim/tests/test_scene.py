import ctypes as C
import math,unittest
from ax7021b_qr.r4_display import SceneState,Scene,Annotation,DisplayInfo,Status,label_bytes,overlap,match_score,rectangle_distance,label_candidates,place_labels

STATUS=dict(source_epoch=9,unique_frames=100)
def row(frame=1,boxes=(),regions=(),epoch=9):
 symbols=[]
 for identity,box,payload,roi in boxes:
  x0,y0,x1,y1=box
  symbols.append(dict(publication_id=identity,track_id=identity,payload=payload,corners=[x0,y0,x1,y0,x1,y1,x0,y1],roi=roi,geometry_epoch=7,geometry_frame=frame))
 return dict(source_epoch=epoch,source_frame=frame,pl_epoch=7,pl_frame_sequence=frame,symbols=symbols,regions=regions)
class Tests(unittest.TestCase):
 def test_abi(self):self.assertEqual([C.sizeof(t) for t in (DisplayInfo,Status,Annotation,Scene)],[64,128,96,912])
 def test_geometry_label_and_retained_identity_does_not_leave_visible_box(self):
  s=SceneState();s.update(row(boxes=[(1,(100,110,200,210),'HELLO-QR',(80,90,220,230))]),10)
  scene,keys=s.scene(STATUS,10,1);a=scene.annotation[0]
  self.assertEqual((a.x0,a.y0,a.x1,a.y1),(96,106,204,214));self.assertTrue(bytes(a.label).startswith(b'HELLO-QR'))
  self.assertNotIn(b'HELLO-QR',bytes(scene.hud));s.acknowledge(keys,10)
  self.assertEqual(s.scene(STATUS,10.501,2)[0].count,0);self.assertEqual(len(s.tracks),1)
  self.assertEqual(s.scene(STATUS,11,3)[0].count,0);self.assertFalse(s.tracks)
 def test_continuous_motion_and_lost_timeout(self):
  s=SceneState();roi=(80,90,220,230)
  s.update(row(boxes=[(1,(100,110,200,210),'ABC1234',roi)]),0);_,keys=s.scene(STATUS,0,1);s.acknowledge(keys,0)
  for i in range(1,51):
   b=(80+i,90,220+i,230);s.update(row(i+1,boxes=[(1,(100+i,110,200+i,210),'ABC1234',b)]),i/10)
  self.assertAlmostEqual(next(iter(s.tracks.values())).box[0],150)
  self.assertEqual(s.scene(STATUS,5.99,2)[0].count,0);self.assertEqual(len(s.tracks),1)
  self.assertEqual(s.scene(STATUS,6,3)[0].count,0);self.assertFalse(s.tracks)
 def test_ambiguous_candidates_cannot_move_payload(self):
  s=SceneState();s.update(row(boxes=[(1,(100,110,200,210),'ABC1234',(80,90,220,230))]),0)
  before=next(iter(s.tracks.values())).box;s.update(row(2,regions=[(81,90,221,230),(79,90,219,230)]),.1)
  self.assertEqual(next(iter(s.tracks.values())).box,before);self.assertEqual(s.ambiguous,1)
 def test_same_text_spatially_distinct_and_eight_labels(self):
  s=SceneState();boxes=[]
  for i in range(8):
   x=20+300*(i%4);y=120+280*(i//4);boxes.append((i+1,(x,y,x+90,y+90),'SAME-PAYLOAD',(x-4,y-4,x+94,y+94)))
  s.update(row(boxes=boxes),0);scene,keys=s.scene(STATUS,0,1);self.assertEqual(scene.count,8);self.assertEqual(s.accepted,8)
  self.assertEqual(s.visible_labels,8)
  for i,a in enumerate(scene.annotation):
   raw=bytes(a.label);start=next(j for j,c in enumerate(raw) if c!=32)
   x=a.label_x+12*(start%32);y=a.label_y+16*(start//32);rect=(x,y,x+108,y+16)
   self.assertFalse(overlap(rect,(880,16,1264,80)))
   own=(a.x0,a.y0,a.x1,a.y1);self.assertLessEqual(rectangle_distance(rect,own),6)
   for j,b in enumerate(scene.annotation):
    if i!=j:self.assertGreaterEqual(rectangle_distance(rect,(b.x0,b.y0,b.x1,b.y1)),rectangle_distance(rect,own)+16)
    if j<i:self.assertFalse(overlap(rect,(b.label_x,b.label_y,b.label_x+384,b.label_y+32)))
  s.update(row(2,boxes=boxes),.1);self.assertEqual(s.accepted,8)
 def test_epoch_out_of_order_and_clear(self):
  s=SceneState();s.update(row(10,boxes=[(1,(100,100,200,200),'ABC1234',(80,80,220,220))]),0)
  s.update(row(9),.1);self.assertEqual(s.frame,10);self.assertEqual(s.stale,1)
  self.assertEqual(s.scene(dict(STATUS,source_epoch=10),.2,1)[0].count,0)
  s.update(row(1,epoch=10,boxes=[(2,(100,100,200,200),'NEW1234',(80,80,220,220))]),.3)
  self.assertEqual(s.scene(dict(STATUS,source_epoch=10),.4,2,stopped=True)[0].count,0)
 def test_long_label_boundaries_and_rolling_fps(self):
  self.assertEqual(label_bytes('BOX-01001|SKU-4801|ZONE-B'),b'BOX-01001'+b' '*55)
  self.assertEqual(label_bytes('A'*100),b'A'*9+b' '*55)
  self.assertEqual(label_bytes('SHORT'),b'SHORT'+b' '*59)
  s=SceneState();s.scene(STATUS,0,1);s.processed=20
  hud=bytes(s.scene(dict(STATUS,unique_frames=130),1,2)[0].hud)
  self.assertIn(b'30.0 FPS',hud);self.assertIn(b'20.0 FPS',hud)
 def test_wrong_epoch_cannot_publish(self):
  s=SceneState();s.scene(STATUS,0,1)
  s.update(row(epoch=8,boxes=[(1,(100,100,200,200),"WRONG-EPOCH",(90,90,210,210))]),.1)
  self.assertEqual(s.epoch,9);self.assertFalse(s.tracks);self.assertEqual(s.accepted,0)
 def test_epoch_counter_restart_resets_fps_window_and_keeps_total(self):
  s=SceneState();s.scene(dict(STATUS,unique_frames=100000),0,1)
  s.update(row(10,boxes=[(1,(100,100,200,200),'ABC1234',(80,80,220,220))]),.1)
  s.scene(dict(STATUS,unique_frames=100030),1,2)
  self.assertEqual(s.preview_fps,30);self.assertEqual(s.accepted,1)
  hud=bytes(s.scene(dict(STATUS,source_epoch=10,unique_frames=0),1.1,3)[0].hud)
  self.assertEqual(s.preview_fps,0);self.assertIn(b'SUCCESS 1',hud)
  s.scene(dict(STATUS,source_epoch=10,unique_frames=30),2.1,4)
  self.assertAlmostEqual(s.preview_fps,30);self.assertEqual(s.accepted,1)
 def test_success_total_requires_publication_identity(self):
  s=SceneState();r=row(1,boxes=[(1,(100,100,200,200),'ABC1234',(80,80,220,220))])
  r['symbols'][0]['publication_id']=0
  s.update(r,0);self.assertEqual(s.accepted,0)
  r['source_frame']=r['pl_frame_sequence']=2;r['symbols'][0]['geometry_frame']=2
  r['symbols'][0]['publication_id']=3
  s.update(r,.1);self.assertEqual(s.accepted,1)
 def test_invalid_stale_geometry_not_displayed(self):
  s=SceneState();r=row(boxes=[(1,(1,2,3,4),'ABC1234',(1,2,3,4))]);r['symbols'][0]['corners'][0]=math.nan
  s.update(r,1);self.assertFalse(s.tracks);self.assertEqual(s.accepted,1)
  r=row(2,boxes=[(1,(1,2,3,4),'ABC1234',(1,2,3,4))]);r.update(board_monotonic_ns=2_000_000_000,capture_completed_ns=1_000_000_000)
  s.update(r,2);self.assertFalse(s.tracks)

class LabelLayoutTests(unittest.TestCase):
 def test_right_edge_text_stays_next_to_owner_with_legal_hardware_origin(self):
  box=(1180,200,1280,300);placements,order=place_labels([box],['BOX-01001|REST'])
  p=placements[0];self.assertIsNotNone(p);self.assertEqual(p['glyph'],(1172,178,1280,194))
  self.assertEqual(p['origin'],(896,178));self.assertEqual(p['column'],23)
  self.assertEqual(label_bytes('BOX-01001|REST',p['column'],p['row']),b' '*23+b'BOX-01001'+b' '*32)
 def test_bottom_row_offsets_fit_existing_abi(self):
  candidates=list(label_candidates((20,600,1280,698),108))
  p=next(p for p in candidates if p['glyph'][1]==704)
  self.assertEqual(p['row'],1);self.assertEqual(p['origin'][1],688)
  self.assertEqual(label_bytes('BOX-01001',p['column'],p['row'])[32+p['column']:41+p['column']],b'BOX-01001')
 def test_crowded_label_is_hidden_instead_of_sent_to_distant_free_space(self):
  boxes=[(500,300,600,400),(380,300,490,400),(610,300,720,400),(500,190,600,290),(500,410,600,510)]
  placements,order=place_labels(boxes,['BOX-01001']*5)
  self.assertIsNone(placements[0]);self.assertIn(0,order)
  labelled=[i for i in order if placements[i] is not None];blank=[i for i in order if placements[i] is None]
  self.assertEqual(order,labelled+blank)
 def test_labels_avoid_hud_and_are_closer_to_their_own_box(self):
  boxes=[(900,80,1020,200),(1040,80,1160,200),(1168,82,1280,202)]
  placements,order=place_labels(boxes,['BOX-01001','BOX-01002','BOX-01003'])
  for i,p in enumerate(placements):
   if p is None:continue
   glyph=p['glyph'];self.assertFalse(overlap(glyph,(880,16,1264,80)))
   own=rectangle_distance(glyph,boxes[i]);self.assertLessEqual(own,6)
   for j,b in enumerate(boxes):
    if i!=j:self.assertGreaterEqual(rectangle_distance(glyph,b),own+16)
 def test_character_offsets_never_cross_hardware_row(self):
  with self.assertRaises(ValueError):label_bytes('BOX-01001',24,0)
  with self.assertRaises(ValueError):label_bytes('BOX-01001',0,2)

class ClientIntegrationTests(unittest.TestCase):
 def test_scene_client_commits_and_clears_without_stopping_video(self):
  import threading
  from ax7021b_qr.r4_display import ResultDisplay
  class Device:
   def __init__(self):self.sequence=0;self.scenes=[];self.condition=threading.Condition();self.closed=False
   def status(self):return dict(source_epoch=9,unique_frames=100,source_frames=100,requested=self.sequence,applied=self.sequence,flags=0,quarantined=0,running=1)
   def submit_scene(self,scene):
    with self.condition:
     self.sequence=scene.sequence;self.scenes.append(Scene.from_buffer_copy(bytes(scene)));self.condition.notify_all()
   def close(self):self.closed=True
  device=Device();client=ResultDisplay(device)
  client.submit_results(row(boxes=[(1,(100,110,200,210),'CLIENT-1234567',(80,90,220,230))]))
  with device.condition:self.assertTrue(device.condition.wait_for(lambda:any(s.count==1 for s in device.scenes),timeout=1))
  summary=client.close();self.assertIsNone(summary['osd_failure']);self.assertEqual(summary['peak_annotations'],1)
  self.assertTrue(device.closed);self.assertEqual(device.scenes[-1].count,0)
  self.assertIn(b'STOP',bytes(device.scenes[-1].hud));self.assertEqual(summary['hardware_status']['running'],1)

class LatestSourceTests(unittest.TestCase):
 def test_missing_or_ambiguous_candidate_hides_box_and_label_on_that_scan(self):
  for regions in [[],[(81,90,221,230),(79,90,219,230)]]:
   s=SceneState();s.update(row(10,boxes=[(1,(100,110,200,210),'BOX-01001|LONG',(80,90,220,230))]),1)
   _,keys=s.scene(dict(STATUS,scan_epoch=9,scan_frame=10),1,1);s.acknowledge(keys,1)
   s.candidates(9,11,regions,1.03)
   # Do not hide early while the older supported source frame is scanning.
   self.assertEqual(s.scene(dict(STATUS,scan_epoch=9,scan_frame=10),1.04,2)[0].count,1)
   scene,_=s.scene(dict(STATUS,scan_epoch=9,scan_frame=11),1.04,3)
   self.assertEqual(scene.count,0);self.assertEqual(bytes(scene.annotation[0].label),bytes(64))
   self.assertEqual(len(s.tracks),1)
 def test_stale_scan_box_not_reused_for_seconds(self):
  s=SceneState();s.update(row(10,boxes=[(1,(100,110,200,210),'BOX-01001',(80,90,220,230))]),1)
  self.assertEqual(s.scene(dict(STATUS,scan_epoch=9,scan_frame=14),1.1,1)[0].count,0)
  self.assertEqual(s.scene(dict(STATUS,scan_epoch=9,scan_frame=10),1.501,2)[0].count,0)
 def test_candidate_jitter_cannot_create_velocity_or_draw_a_distant_box(self):
  s=SceneState();s.update(row(10,boxes=[(1,(100,110,200,210),'BOX-01001',(80,90,220,230))]),1)
  s.candidates(9,11,[(90,90,230,230)],1.033)
  self.assertEqual(next(iter(s.tracks.values())).box,(100,110,200,210))
  self.assertEqual(s.scene(dict(STATUS,scan_epoch=9,scan_frame=23),1.43,1)[0].count,0)
  self.assertEqual(s.predicted,0)
 def test_three_real_stationary_decodes_allow_fixed_box_despite_roi_jitter(self):
  s=SceneState()
  for frame in [10,11,12]:
   s.update(row(frame,boxes=[(1,(100,110,200,210),'BOX-01001',(80,90,220,230))]),1+(frame-10)/30)
  s.candidates(9,13,[(90,90,230,230)],1.1)
  scene,_=s.scene(dict(STATUS,scan_epoch=9,scan_frame=25),1.45,1)
  self.assertEqual(scene.count,1);self.assertEqual(scene.annotation[0].x0,96)
  self.assertEqual(scene.annotation[0].source_frame,12);self.assertEqual(s.predicted,0)
 def test_moving_decodes_are_not_extrapolated_across_capture_backlog(self):
  s=SceneState()
  for frame in [10,11,12]:
   x=100+10*(frame-10);s.update(row(frame,boxes=[(1,(x,110,x+100,210),'BOX-01001',(x-20,90,x+120,230))]),1+(frame-10)/30)
  s.candidates(9,13,[(100,90,240,230)],1.1)
  self.assertEqual(s.scene(dict(STATUS,scan_epoch=9,scan_frame=25),1.45,1)[0].count,0)
  scene,_=s.scene(dict(STATUS,scan_epoch=9,scan_frame=13),1.08,2)
  self.assertEqual(scene.count,1);self.assertEqual(scene.annotation[0].x0,116)
 def test_proposals_cannot_keep_decoded_geometry_alive_forever(self):
  s=SceneState();s.update(row(10,boxes=[(1,(100,110,200,210),'BOX-01001',(80,90,220,230))]),1)
  s.candidates(9,20,[(80,90,220,230)],1.9)
  s.scene(STATUS,2.01,1);self.assertFalse(s.tracks)
 def test_candidate_resize_does_not_resize_decoded_box(self):
  s=SceneState();s.update(row(10,boxes=[(1,(100,110,200,210),'BOX-01001',(80,90,220,230))]),1)
  s.candidates(9,11,[(50,60,250,260)],1.03)
  t=next(iter(s.tracks.values()));self.assertEqual(t.box,(100,110,200,210));self.assertEqual(t.frame,10)
 def test_republished_same_physical_code_cannot_leave_duplicate_overlay(self):
  s=SceneState();box=(100,110,200,210);roi=(80,90,220,230)
  s.update(row(10,boxes=[(1,box,'BOX-01001',roi)]),1)
  s.update(row(11,boxes=[(2,box,'BOX-01001',roi)]),1.03)
  self.assertEqual(len(s.tracks),1);self.assertIn((9,2),s.tracks)
 def test_payload_change_cannot_inherit_stationary_confirmation(self):
  s=SceneState()
  for frame in [10,11,12]:s.update(row(frame,boxes=[(1,(100,110,200,210),'BOX-01001',(80,90,220,230))]),1+(frame-10)/30)
  s.update(row(13,boxes=[(1,(100,110,200,210),'BOX-01002',(80,90,220,230))]),1.1)
  s.candidates(9,14,[(80,90,220,230)],1.13)
  self.assertEqual(s.scene(dict(STATUS,scan_epoch=9,scan_frame=25),1.4,1)[0].count,0)
 def test_projected_exit_does_not_pin_box_at_screen_edge(self):
  s=SceneState();s.update(row(10,boxes=[(1,(1190,110,1270,190),'BOX-01001',(1180,100,1280,200))]),1)
  s.candidates(9,11,[],1.03)
  self.assertEqual(s.scene(dict(STATUS,scan_epoch=9,scan_frame=11),1.04,1)[0].count,0)
 def test_never_acknowledged_tracks_expire(self):
  s=SceneState();s.update(row(10,boxes=[(1,(100,110,200,210),'BOX-01001',(80,90,220,230))]),1)
  self.assertEqual(s.scene(dict(STATUS,scan_epoch=9,scan_frame=9),1.1,1)[0].count,0)
  s.scene(STATUS,2.01,2);self.assertFalse(s.tracks)
 def test_late_decode_replays_presence_without_inventing_new_coordinates(self):
  s=SceneState();s.scene(STATUS,1,1)
  s.candidates(9,10,[(80,90,220,230)],1.0)
  s.candidates(9,11,[(90,90,230,230)],1.03)
  s.candidates(9,12,[(100,90,240,230)],1.06)
  r=row(10,boxes=[(1,(100,110,200,210),'LATEST1234567',(80,90,220,230))]);r.update(capture_completed_ns=1_000_000_000,board_monotonic_ns=1_100_000_000)
  s.update(r,1.1);t=next(iter(s.tracks.values()));self.assertEqual(t.frame,10);self.assertAlmostEqual(t.box[0],100)
  # A delayed single decode is hidden, not shifted using newer proposals.
  scene,keys=s.scene(dict(STATUS,scan_epoch=9,scan_frame=13),1.1,2)
  self.assertEqual(scene.count,0);self.assertEqual(s.predicted,0)
  scene,_=s.scene(dict(STATUS,scan_epoch=9,scan_frame=10),1.03,3)
  self.assertEqual(scene.annotation[0].x0,96)
 def test_future_scan_and_wrong_epoch_do_not_show_old_boxes(self):
  s=SceneState();s.update(row(10,boxes=[(1,(100,110,200,210),'FUTURE123',(80,90,220,230))]),1)
  self.assertEqual(s.scene(dict(STATUS,scan_epoch=9,scan_frame=9),1.01,1)[0].count,0)
  self.assertEqual(s.scene(dict(STATUS,scan_epoch=8,scan_frame=10),1.02,2)[0].count,0)
  self.assertIsNone(next(iter(s.tracks.values())).first_ack)
 def test_ambiguous_neighbor_blocks_shared_candidate(self):
  s=SceneState();s.update(row(1,boxes=[(1,(5,10,45,50),'LEFT123',(0,0,100,100)),(2,(105,10,145,50),'RIGHT123',(50,0,150,100))]),0)
  original=[t.box for t in s.tracks.values()]
  s.candidates(9,2,[(20,0,120,100),(80,0,180,100)],.1)
  self.assertEqual([t.box for t in s.tracks.values()],original);self.assertEqual(s.motion_updates,0)
 def test_duplicate_metadata_never_rewinds_track(self):
  s=SceneState();s.update(row(10,boxes=[(1,(100,110,200,210),'LATEST123',(80,90,220,230))]),1)
  s.candidates(9,11,[(90,90,230,230)],1.03);s.candidates(9,10,[(0,0,100,100)],1.04)
  self.assertEqual(next(iter(s.tracks.values())).frame,10);self.assertEqual(s.candidate_rejects,1)

if __name__=='__main__':unittest.main()
