#include "qr_tracker.h"
#include <math.h>
#include <string.h>

#define NO_MATCH 1.0e30f

static qr_track_retire_fn retire_observer;

void qr_tracker_set_retire_observer(qr_track_retire_fn observer){retire_observer=observer;}
void qr_tracker_finish(qr_tracker_t *t,const char *reason){unsigned i;for(i=0;i<QR_TRACKER_CAPACITY;i++)if(t->tracks[i].active&&retire_observer)retire_observer(&t->tracks[i],reason);}
qr_track_t *qr_tracker_find(qr_tracker_t *t,uint32_t id){unsigned i;for(i=0;i<QR_TRACKER_CAPACITY;i++)if(t->tracks[i].active&&t->tracks[i].id==id)return&t->tracks[i];return 0;}
void qr_tracker_init(qr_tracker_t *t){memset(t,0,sizeof(*t));t->next_id=1;}
void qr_tracker_retire(qr_tracker_t *t,uint64_t now){unsigned i;for(i=0;i<QR_TRACKER_CAPACITY;i++)if(t->tracks[i].active&&now-t->tracks[i].last_us>1200000U){if(retire_observer)retire_observer(&t->tracks[i],"timeout");t->tracks[i].active=0;t->retired++;}}

#if !QR_TRACKER_POINT_ASSOC
static float legacy_track_cost(const qr_track_t *t,const qr_track_observation_t *o,uint64_t now){
  float dt=(float)(now-t->last_us)/1000000.0f,px=t->x+t->vx*dt,py=t->y+t->vy*dt,dx=o->x-px,dy=o->y-py,d=sqrtf(dx*dx+dy*dy),ratio=o->size/t->size;
  float ygate=fmaxf(32.0f,.4f*o->size),dgate=fmaxf(48.0f,.75f*o->size+400.0f*dt);
  if(ratio<.6f||ratio>1.67f||fabsf(dy)>ygate||d>dgate)return NO_MATCH;
  return d/dgate+fabsf(logf(ratio));
}
#endif

#if QR_TRACKER_POINT_ASSOC
static int finite_points(const qr_track_observation_t *o){
  unsigned i;if(!o->finder_valid||o->module_size<=0.0f||!isfinite(o->module_size))return 0;
  for(i=0;i<3;i++)if(!isfinite(o->finder_x[i])||!isfinite(o->finder_y[i]))return 0;
  return 1;
}

static float point_track_cost(const qr_track_t *t,const qr_track_observation_t *o,uint64_t now){
  static const uint8_t permutations[6][3]={{0,1,2},{0,2,1},{1,0,2},{1,2,0},{2,0,1},{2,1,0}};
  float dt,ratio,gate,gate2,best=NO_MATCH;
  unsigned p,i;
  if(!t->finder_valid||!t->velocity_valid||!finite_points(o)||!o->geometry_reliable)return NO_MATCH;
  ratio=o->module_size/t->module_size;
  if(ratio<.8f||ratio>1.25f)return NO_MATCH;
  dt=now>=t->last_us?(float)(now-t->last_us)/1000000.0f:0.0f;
  if(dt>1.2f)return NO_MATCH;
  gate=fmaxf(4.0f,2.0f*fmaxf(o->module_size,t->module_size));gate2=gate*gate;
  for(p=0;p<6;p++){
    float sum=0.0f;int valid=1;
    for(i=0;i<3;i++){
      float px=t->finder_x[i]+t->vx*dt,py=t->finder_y[i]+t->vy*dt;
      float dx=o->finder_x[permutations[p][i]]-px;
      float dy=o->finder_y[permutations[p][i]]-py;
      float d2=dx*dx+dy*dy;
      if(d2>gate2){valid=0;break;}sum+=d2/gate2;
    }
    if(valid&&sum<best)best=sum/3.0f+fabsf(logf(ratio));
  }
  return best;
}

static float point_result_cost(const qr_track_t *t,const qr_track_observation_t *o,uint64_t now){
  static const uint8_t permutations[6][3]={{0,1,2},{0,2,1},{1,0,2},{1,2,0},{2,0,1},{2,1,0}};
  float dt,ratio,dx,dy,distance,move_gate,shape_gate,shape_gate2,best=NO_MATCH;
  unsigned p,i;
  if(!t->finder_valid||!finite_points(o))return NO_MATCH;
  ratio=o->module_size/t->module_size;
  if(ratio<.8f||ratio>1.25f)return NO_MATCH;
  dt=now>=t->last_us?(float)(now-t->last_us)/1000000.0f:0.0f;
  if(dt>1.2f)return NO_MATCH;
  dx=o->x-(t->x+(t->velocity_valid?t->vx*dt:0.0f));
  dy=o->y-(t->y+(t->velocity_valid?t->vy*dt:0.0f));
  distance=sqrtf(dx*dx+dy*dy);
  move_gate=t->velocity_valid?fmaxf(12.0f,.25f*o->size+100.0f*dt):
                              fmaxf(48.0f,.75f*o->size+400.0f*dt);
  if(fabsf(dy)>fmaxf(24.0f,.4f*o->size)||distance>move_gate)return NO_MATCH;
  shape_gate=fmaxf(4.0f,1.5f*fmaxf(o->module_size,t->module_size));
  shape_gate2=shape_gate*shape_gate;
  for(p=0;p<6;p++){
    float sum=0.0f;int valid=1;
    for(i=0;i<3;i++){
      float tx=t->finder_x[i]-t->x,ty=t->finder_y[i]-t->y;
      float ox=o->finder_x[permutations[p][i]]-o->x;
      float oy=o->finder_y[permutations[p][i]]-o->y;
      float ex=ox-tx,ey=oy-ty,d2=ex*ex+ey*ey;
      if(d2>shape_gate2){valid=0;break;}sum+=d2/shape_gate2;
    }
    if(valid&&sum<best)best=sum/3.0f+distance/move_gate+fabsf(logf(ratio));
  }
  return best;
}
#endif

static float track_cost(const qr_track_t *t,const qr_track_observation_t *o,uint64_t now){
#if QR_TRACKER_POINT_ASSOC
  return point_track_cost(t,o,now);
#else
  return legacy_track_cost(t,o,now);
#endif
}

static int observation_has_points(const qr_track_observation_t *o){
#if QR_TRACKER_POINT_ASSOC
  return finite_points(o);
#else
  (void)o;return 0;
#endif
}

static void update_track(qr_track_t *track,const qr_track_observation_t *o,uint64_t now,int created){
  unsigned i;
  if(!created&&track->last_frame!=o->frame_id&&now>track->last_us){
    float dt=(float)(now-track->last_us)/1000000.0f;
    if(dt>0){float nvx=(o->x-track->x)/dt,nvy=(o->y-track->y)/dt;track->vx=track->velocity_valid?.5f*track->vx+.5f*nvx:nvx;track->vy=track->velocity_valid?.5f*track->vy+.5f*nvy:nvy;track->velocity_valid=1;}
  }
  if(created||track->last_frame!=o->frame_id){
    track->x=o->x;track->y=o->y;track->size=o->size;
    if(observation_has_points(o)){for(i=0;i<3;i++){track->finder_x[i]=o->finder_x[i];track->finder_y[i]=o->finder_y[i];}track->module_size=o->module_size;track->finder_valid=1;}
    track->last_us=now;track->last_frame=o->frame_id;
  }
}

static int decision_return(qr_tracker_t *t,const qr_track_decision_t *d,int result,int rc){
  if(!result){t->roi_queries++;if(rc)t->roi_capacity_skips++;else if(d->should_decode)t->roi_decode_admitted++;else if(d->already_decoded)t->roi_prediction_skips++;else t->roi_retry_wait++;}return rc;
}

static int observe(qr_tracker_t *t,const qr_track_observation_t *o,uint64_t now,qr_track_decision_t *d,int decoded_result,const char *payload){
  unsigned i,best=QR_TRACKER_CAPACITY,free_slot=QR_TRACKER_CAPACITY,matches=0;float best_cost=NO_MATCH,second=NO_MATCH;qr_track_t *track;
  memset(d,0,sizeof(*d));qr_tracker_retire(t,now);
#if QR_TRACKER_POINT_ASSOC
  if(!decoded_result&&(!finite_points(o)||!o->geometry_reliable))t->unreliable_geometry++;
#endif
  for(i=0;i<QR_TRACKER_CAPACITY;i++){
    float c;
    if(!t->tracks[i].active){if(free_slot==QR_TRACKER_CAPACITY)free_slot=i;continue;}
    if(payload&&t->tracks[i].decoded&&strcmp(t->tracks[i].payload,payload)){t->payload_conflicts++;continue;}
#if QR_TRACKER_POINT_ASSOC
    if(!decoded_result&&!t->tracks[i].publication_id){t->unbound_rejects++;continue;}
#else
    if((!decoded_result&&t->tracks[i].last_frame==o->frame_id)||(decoded_result&&t->tracks[i].last_result_frame==o->frame_id))continue;
#endif
    c=
#if QR_TRACKER_POINT_ASSOC
      decoded_result?point_result_cost(&t->tracks[i],o,now):
#endif
      track_cost(&t->tracks[i],o,now);
    if(c>=NO_MATCH){t->point_rejects++;continue;}
    matches++;t->point_matches++;
    if(c<best_cost){second=best_cost;best_cost=c;best=i;}else if(c<second)second=c;
  }
  d->matched_tracks=(uint8_t)(matches>255U?255U:matches);
#if QR_TRACKER_POINT_ASSOC
  if(matches>1U){
    d->ambiguous=1;d->should_decode=!decoded_result;t->ambiguous++;t->multi_match_decode+=!decoded_result;
    return decision_return(t,d,decoded_result,0);
  }
#endif
  if(best==QR_TRACKER_CAPACITY){
    if(!decoded_result)t->roi_unmatched++;
#if QR_STEP1_SUCCESS_ONLY
    if(!decoded_result){d->should_decode=1;if(free_slot==QR_TRACKER_CAPACITY)t->capacity_bypass++;return decision_return(t,d,decoded_result,0);}
    if(!payload||!payload[0]){d->should_decode=1;return decision_return(t,d,decoded_result,0);}
#endif
    if(free_slot==QR_TRACKER_CAPACITY){t->capacity_rejects++;return decision_return(t,d,decoded_result,-1);}
    best=free_slot;track=&t->tracks[best];memset(track,0,sizeof(*track));track->active=1;track->id=t->next_id++;if(t->next_id==0)t->next_id=1;track->first_us=now;d->created=1;t->created++;
  }
  track=&t->tracks[best];track->associations++;
#if !QR_TRACKER_POINT_ASSOC
  if(!d->created&&second<NO_MATCH&&second<=best_cost*1.15f){d->ambiguous=1;t->ambiguous++;track->ambiguities++;}
#else
  (void)second;
#endif
  update_track(track,o,now,d->created);
  d->track_id=track->id;d->already_decoded=track->decoded;
  if(decoded_result)track->last_result_frame=o->frame_id;
  if(track->decoded){t->decoded_skips++;track->skips++;d->should_decode=d->ambiguous;track->sharpness=o->sharpness;return decision_return(t,d,decoded_result,0);}
#if QR_STEP1_SUCCESS_ONLY
  if(decoded_result&&payload){track->decoded=1;strncpy(track->payload,payload,QR_TRACKER_PAYLOAD_BYTES-1);track->payload[QR_TRACKER_PAYLOAD_BYTES-1]=0;track->last_attempt_us=now;track->sharpness=o->sharpness;return decision_return(t,d,decoded_result,0);}
#endif
  if(d->created||track->last_attempt_us==0)d->should_decode=1;
  else{uint64_t age=now-track->last_attempt_us;if((age>=150000U&&o->sharpness>=track->sharpness*1.10f)||age>=300000U){d->should_decode=1;t->retries++;track->retry_decisions++;}}
  if(d->ambiguous)d->should_decode=1;
  track->sharpness=o->sharpness;
  return decision_return(t,d,decoded_result,0);
}

int qr_tracker_observe(qr_tracker_t *t,const qr_track_observation_t *o,uint64_t now,qr_track_decision_t *d){return observe(t,o,now,d,0,0);}
int qr_tracker_observe_result(qr_tracker_t *t,const qr_track_observation_t *o,uint64_t now,qr_track_decision_t *d){return observe(t,o,now,d,1,0);}
int qr_tracker_observe_success(qr_tracker_t *t,const qr_track_observation_t *o,uint64_t now,const char *payload,qr_track_decision_t *d){return observe(t,o,now,d,1,payload);}
void qr_tracker_claim_result(qr_tracker_t *t,uint32_t id,uint32_t frame_id){qr_track_t *track=qr_tracker_find(t,id);if(track)track->last_result_frame=frame_id;}
int qr_tracker_mark_attempt(qr_tracker_t *t,uint32_t id,uint64_t now,int success,const char *payload){qr_track_t *track=qr_tracker_find(t,id);if(!track)return-1;if(success&&track->decoded&&payload&&strcmp(track->payload,payload))return-2;track->last_attempt_us=now;if(success&&!track->decoded){track->decoded=1;if(payload){strncpy(track->payload,payload,QR_TRACKER_PAYLOAD_BYTES-1);track->payload[QR_TRACKER_PAYLOAD_BYTES-1]=0;}return 1;}return 0;}
int qr_tracker_bind_publication(qr_tracker_t *t,uint32_t id,uint32_t publication_id){qr_track_t *track=qr_tracker_find(t,id);if(!track||!publication_id)return-1;track->publication_id=publication_id;return 0;}
void qr_tracker_invalidate_publication(qr_tracker_t *t,uint32_t id){qr_track_t *track=qr_tracker_find(t,id);if(track&&track->publication_id){track->publication_id=0;t->publication_invalidated++;}}
