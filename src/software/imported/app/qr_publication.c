#include "qr_publication.h"
#include <math.h>
#include <string.h>

static uint32_t payload_hash(const char *s,size_t n){
    uint32_t h=2166136261U;size_t i;
    for(i=0;i<n;i++){h^=(uint8_t)s[i];h*=16777619U;}return h;
}
static float bounded(float v,float limit){return fminf(limit,fmaxf(-limit,v));}
void qr_publication_init(qr_publication_t *p){memset(p,0,sizeof(*p));p->next_id=1;p->frame_period_s=1.0f/30.0f;}
void qr_publication_rebase_frames(qr_publication_t *p){
    unsigned i;for(i=0;i<QR_PUBLICATION_CAPACITY;i++)p->entries[i].frame_valid=0;
}
unsigned qr_publication_pending(const qr_publication_t *p){
    unsigned i,n=0;for(i=0;i<QR_PUBLICATION_CAPACITY;i++)n+=p->entries[i].state==QR_PUB_PENDING;return n;
}
int qr_publication_identity_live(const qr_publication_t *p,uint32_t id,uint64_t now_us){
    unsigned i;if(!id)return 0;
    for(i=0;i<QR_PUBLICATION_CAPACITY;i++){
        const qr_publication_entry_t *e=&p->entries[i];
        if(e->id!=id||e->state==QR_PUB_UNUSED)continue;
        if(e->state==QR_PUB_PENDING)return 1;
        return now_us<e->last_us||now_us-e->last_us<=QR_PUBLICATION_RETENTION_US;
    }
    return 0;
}
static uint32_t next_id(qr_publication_t *p){
    unsigned i;uint32_t id;
    for(;;){id=p->next_id++;if(!id)continue;
        for(i=0;i<QR_PUBLICATION_CAPACITY;i++)
            if(p->entries[i].state&&p->entries[i].id==id)break;
        if(i==QR_PUBLICATION_CAPACITY)return id;
    }
}
static float motion_dt(const qr_publication_t *p,const qr_publication_entry_t *e,const qr_publication_observation_t *o){
    if(p->frame_period_s>0&&e->frame_valid)return (float)(o->frame-e->frame)*p->frame_period_s;
    return o->sample_us>=e->sample_us?(float)(o->sample_us-e->sample_us)/1000000.0f:-1.0f;
}
static float match_cost(const qr_publication_t *p,const qr_publication_entry_t *e,const qr_publication_observation_t *o){
    float dx=o->x-e->x,dy=o->y-e->y,dt,gate,ratio=o->size/e->size;
    uint32_t frames=o->frame-e->frame;
    if(ratio<.6f||ratio>1.67f)return 1.0e30f;
    /* Repeated observations in a frame need a small spatial gate. Distinct
     * symbols with identical text must not claim the same entity. */
    if(e->frame_valid&&!frames){gate=fmaxf(8.0f,.12f*fminf(o->size,e->size));
        return dx*dx+dy*dy<=gate*gate?(dx*dx+dy*dy)/(gate*gate):1.0e30f;}
    if(e->frame_valid&&frames>=0x80000000U)return 1.0e30f;
    dt=motion_dt(p,e,o);
    if(dt<0||dt>6.0f)return 1.0e30f;
    /* A stopped conveyor is a valid continuation even with a stale velocity. */
    gate=fmaxf(8.0f,.12f*fminf(o->size,e->size));
    if(dx*dx+dy*dy<=gate*gate)return 0;
    if(e->velocity_valid){dx-=e->vx*dt;dy-=e->vy*dt;}
    gate=fmaxf(48.0f,.9f*o->size)+(e->velocity_valid?60.0f:300.0f)*dt;
    /* A cold entity has no motion prediction yet. Its displacement may exceed
     * four symbol widths between successful decodes; cap only prediction error. */
    if(e->velocity_valid)gate=fminf(4.0f*fmaxf(o->size,e->size),gate);
    if(fabsf(dy)>fminf(o->size,fmaxf(24.0f,.5f*o->size)+40.0f*dt)||dx*dx+dy*dy>gate*gate)return 1.0e30f;
    return (dx*dx+dy*dy)/(gate*gate)+fabsf(logf(ratio));
}
static void update(qr_publication_t *p,qr_publication_entry_t *e,const qr_publication_observation_t *o){
    uint32_t frames=o->frame-e->frame;
    float dt=motion_dt(p,e,o);
    if((!e->frame_valid||(frames&&frames<0x80000000U))&&dt>0&&dt<=6.0f){
        float vx=bounded((o->x-e->x)/dt,400.0f),vy=bounded((o->y-e->y)/dt,200.0f);
        e->vx=e->velocity_valid?.5f*(e->vx+vx):vx;
        e->vy=e->velocity_valid?.5f*(e->vy+vy):vy;e->velocity_valid=1;
        p->flow_vx=p->flow_samples?.9f*p->flow_vx+.1f*vx:vx;
        p->flow_vy=p->flow_samples?.9f*p->flow_vy+.1f*vy:vy;p->flow_samples++;
        e->x=o->x;e->y=o->y;e->size=o->size;e->frame=o->frame;e->sample_us=o->sample_us;e->frame_valid=1;
    }
    if(o->now_us>e->last_us)e->last_us=o->now_us;
}
int qr_publication_prepare(qr_publication_t *p,const char *payload,size_t length,
                          const qr_publication_observation_t *o,unsigned *slot){
    unsigned i,best=QR_PUBLICATION_CAPACITY,free_slot=QR_PUBLICATION_CAPACITY,oldest=QR_PUBLICATION_CAPACITY;
    float cost=1.0e30f;uint32_t hash;qr_publication_entry_t *e;
    if(!payload||!o||!slot||!length||length>=QR_PUBLICATION_PAYLOAD_BYTES||
       !isfinite(o->x)||!isfinite(o->y)||!isfinite(o->size)||o->size<=0){p->invalid++;return QR_PUB_INVALID;}
    hash=payload_hash(payload,length);
    for(i=0;i<QR_PUBLICATION_CAPACITY;i++){
        float c;e=&p->entries[i];
        if(e->state==QR_PUB_PUBLISHED&&o->now_us>=e->last_us&&
           o->now_us-e->last_us>QR_PUBLICATION_RETENTION_US)e->state=QR_PUB_UNUSED;
        if(!e->state){if(free_slot==QR_PUBLICATION_CAPACITY)free_slot=i;continue;}
        if(e->state==QR_PUB_PUBLISHED&&(oldest==QR_PUBLICATION_CAPACITY||e->last_us<p->entries[oldest].last_us))oldest=i;
        if(e->hash!=hash||e->length!=length||memcmp(e->payload,payload,length))continue;
        c=match_cost(p,e,o);if(c<cost){best=i;cost=c;}
    }
    if(best!=QR_PUBLICATION_CAPACITY){
        e=&p->entries[best];update(p,e,o);*slot=best;
        if(e->state==QR_PUB_PENDING)return QR_PUB_RETRY;
        p->duplicates++;return QR_PUB_DUPLICATE;
    }
    best=free_slot;
    if(best==QR_PUBLICATION_CAPACITY){best=oldest;
        if(best==QR_PUBLICATION_CAPACITY){p->full_pending++;return QR_PUB_FULL;}p->evictions++;}
    e=&p->entries[best];memset(e,0,sizeof(*e));e->id=next_id(p);e->hash=hash;
    e->length=(uint16_t)length;memcpy(e->payload,payload,length);e->payload[length]=0;
    e->x=o->x;e->y=o->y;e->size=o->size;e->frame=o->frame;
    e->sample_us=o->sample_us;e->last_us=o->now_us;e->state=QR_PUB_PENDING;e->frame_valid=1;
    if(p->flow_samples>=3){e->vx=p->flow_vx;e->vy=p->flow_vy;e->velocity_valid=1;}
    p->created++;*slot=best;return QR_PUB_NEW;
}
int qr_publication_commit(qr_publication_t *p,unsigned slot,uint32_t id){
    if(slot>=QR_PUBLICATION_CAPACITY||p->entries[slot].id!=id||p->entries[slot].state!=QR_PUB_PENDING)return -1;
    p->entries[slot].state=QR_PUB_PUBLISHED;p->committed++;return 0;
}
