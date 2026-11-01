#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <errno.h>
#include "quirc_internal.h"
#include "ax7021b_fitness.h"
#include "qr_fitness_backend.h"
#include "qr_profile.h"
#include "qr_binary_pack.h"
#include "qr_fitness_tree.h"
_Static_assert(sizeof(quirc_float_t)==8,"Fitness backend requires C04 binary64 coefficients");
static struct qr_fitness_metrics metrics;
static struct qr_fitness_prepare_metrics phases;
static struct qr_fitness_prepare resident;
static int fd=-1,active,failed,compare;
static struct qr_fitness_phase_metrics details={.version=1};
static struct qr_fitness_fault_metrics failures={.version=1};
static struct qr_fitness_r3_metrics r3_metrics={.version=1};
static const struct quirc *binary_owner;
static uint32_t binary_generation;
static int packed_valid,roi_loaded,grid_mode,reuse_mode,device_v2=-1,reference_active;
static struct qr_fitness_roi roi_token;
static struct qr_fitness_grid grid_request;
static uint64_t *candidate_tree;
static unsigned reference_step,reference_node[8];
static uint64_t reference_c[8];static int reference_best;
static void release_roi(void);
void qr_fitness_binary_begin(const struct quirc *q){
 release_roi();binary_owner=q;packed_valid=0;
 if(!++binary_generation)++binary_generation;
 ++r3_metrics.binary_generations;
}
void qr_fitness_binary_end(const struct quirc *q){
 if(binary_owner==q){
  uint64_t before=metrics.release_us;release_roi();
  uint64_t elapsed=metrics.release_us-before;
  qr_profile_add_time(7,elapsed);qr_profile_add_time(6,elapsed);
  binary_owner=NULL;packed_valid=0;
 }
}
static int grid_width,grid_height,grid_size;
static unsigned diagnostic_score_ordinal;
static void failure(uint64_t *counter,int error){
 ++*counter;failures.last_errno=error;failures.last_width=grid_width;failures.last_height=grid_height;failures.last_grid_size=grid_size;
 failures.last_epoch=resident.epoch;failures.last_frame=resident.frame;failures.last_config=resident.config;failures.last_job=resident.job;
}
static void diagnostic(unsigned operation){
 const char *env=getenv("QR_FITNESS_PROFILE");struct qr_fitness_profile p={.version=1};uint64_t begin;
 if(operation==1&&diagnostic_score_ordinal++%QR_FITNESS_PROFILE_STRIDE)return;
 if(!env||strcmp(env,"1"))return;
 begin=qr_profile_now();
 if(ioctl(fd,QR_FITNESS_GET_PROFILE,&p)||p.operation!=operation||p.job!=resident.job||p.frame!=resident.frame||p.epoch!=resident.epoch||p.config!=resident.config){++details.invalid_records;goto done;}
 if(p.flags&4)++details.invalid_records;
 if(operation==0)++details.prepare_count;else ++details.score_count;
 details.copy_ns+=p.copy_ns;details.register_ns+=p.register_ns;details.wait_ns+=p.wait_ns;details.isr_ns+=p.isr_ns;details.wake_ns+=p.wake_ns;details.result_ns+=p.result_ns;details.ioctl_ns+=p.ioctl_ns;details.control_writes+=p.control_writes;
 if(p.flags&2){if(operation==0){++details.pl_load_count;details.pl_load_cycles+=p.pl_cycles;}else{++details.pl_score_count;details.pl_score_cycles+=p.pl_cycles;}}
 done:details.diagnostic_ns+=(qr_profile_now()-begin)*1000;
}
static uint32_t serial;
static uint32_t *memory;
void qr_fitness_set_frame(uint32_t epoch,uint32_t frame,uint32_t config){
 if(resident.epoch!=epoch||resident.frame!=frame||resident.config!=config){release_roi();packed_valid=0;}
 resident.epoch=epoch;resident.frame=frame;resident.config=config;
}
static void cell(uint32_t *f,unsigned *n,int x,int y,int w){if(*n<2048)f[(*n)++]=(uint32_t)x|((uint32_t)y<<8)|((uint32_t)(uint8_t)w<<16);else *n=2049;}
static void ring(uint32_t*f,unsigned*n,int x,int y,int r,int w){for(int i=0;i<r*2;i++){cell(f,n,x-r+i,y-r,w);cell(f,n,x-r,y+r-i,w);cell(f,n,x+r,y-r+i,w);cell(f,n,x+r-i,y+r,w);}}
static void cap(uint32_t*f,unsigned*n,int x,int y){x+=3;y+=3;cell(f,n,x,y,1);ring(f,n,x,y,1,1);ring(f,n,x,y,2,-1);ring(f,n,x,y,3,1);}
static void apat(uint32_t*f,unsigned*n,int x,int y){cell(f,n,x,y,1);ring(f,n,x,y,1,-1);ring(f,n,x,y,2,1);}
int qr_fitness_begin(const struct quirc *q,int index){
 const char *mode=getenv("QR_FITNESS_BACKEND");int size=q->grids[index].grid_size,version=(size-17)/4;
 unsigned n=0,stride=(q->w+31)/32,words=stride*q->h;uint64_t begin,phase;uint32_t *f;
 ++metrics.grids;active=failed=reference_active=0;diagnostic_score_ordinal=0;grid_width=q->w;grid_height=q->h;grid_size=size;
 grid_mode=mode&&(!strcmp(mode,"pl-grid")||!strcmp(mode,"compare-grid"));
 reuse_mode=grid_mode||(mode&&!strcmp(mode,"pl-reuse"));
 compare=mode&&(!strcmp(mode,"compare")||!strcmp(mode,"compare-grid"));
 if(!mode||!strcmp(mode,"software")){++metrics.software_grids;return 0;}
 if(strcmp(mode,"pl")&&strcmp(mode,"compare")&&!reuse_mode)goto fault;
 if(version<1||version>40||size!=17+version*4){failure(&failures.unsupported_grid,ERANGE);goto fault;}
 if(q->w<=0||q->h<=0||q->w>1280||q->h>720){failure(&failures.unsupported_roi,ERANGE);goto fault;}
 begin=qr_profile_now();
 if(fd<0)fd=open("/dev/ax7021b-fitness0",O_RDWR|O_CLOEXEC);
 if(fd<0){failure(&failures.open_device,errno);goto fault;}
 if(reuse_mode&&device_v2<0){
  struct qr_fitness_capabilities caps={.version=2};
  device_v2=!ioctl(fd,QR_FITNESS_CAPABILITIES,&caps)&&caps.version==2&&
     caps.hardware_abi==2&&caps.magic==0xAC04F003&&caps.tree_nodes==8184&&
     caps.trace_entries==81&&caps.max_roi_words>=28800&&caps.max_cells>=2048&&
     (caps.capabilities&(QR_FITNESS_CAP_ROI_LIFETIME|QR_FITNESS_CAP_GRID_JOB))==(QR_FITNESS_CAP_ROI_LIFETIME|QR_FITNESS_CAP_GRID_JOB);
 }
 if(reuse_mode&&!device_v2){failure(&failures.prepare_ioctl,EOPNOTSUPP);goto fault;}
 if(!memory)memory=malloc(QR_FITNESS_MAX_WORDS*4);
 if(!memory){failure(&failures.allocation,ENOMEM);goto fault;}
 phase=qr_profile_now();
 if(!packed_valid||binary_owner!=q){
  if(qr_binary_pack(memory,words,q->pixels,q->w,q->h,sizeof(*q->pixels))){failure(&failures.unsupported_roi,EINVAL);goto fault;}
  packed_valid=binary_owner==q;++r3_metrics.packed_rois;
 }else ++r3_metrics.pack_reuses;
 phases.pack_us+=qr_profile_now()-phase;phase=qr_profile_now();
 f=memory+words;
 for(int i=0;i<size-14;i++){int w=(i&1)?1:-1;cell(f,&n,i+7,6,w);cell(f,&n,6,i+7,w);}
 cap(f,&n,0,0);cap(f,&n,size-7,0);cap(f,&n,0,size-7);
 const struct quirc_version_info *info=&quirc_version_db[version];int count=0;
 while(count<QUIRC_MAX_ALIGNMENT&&info->apat[count])count++;
 for(int i=1;i+1<count;i++){apat(f,&n,6,info->apat[i]);apat(f,&n,info->apat[i],6);}
 for(int i=1;i<count;i++)for(int j=1;j<count;j++)apat(f,&n,info->apat[i],info->apat[j]);
 if(n>2048){failure(&failures.feature_overflow,EOVERFLOW);goto fault;}
 resident.version=1;resident.flags=0;resident.width=q->w;resident.height=q->h;resident.stride=stride;resident.cells=n;
 resident.job=++serial;if(!resident.job)resident.job=++serial;resident.data=(uintptr_t)memory;
 phases.features_us+=qr_profile_now()-phase;phase=qr_profile_now();
 if(reuse_mode){
  if(!roi_loaded){
   roi_token=(struct qr_fitness_roi){.version=2,.width=q->w,.height=q->h,.stride=stride,
    .epoch=resident.epoch,.frame=resident.frame,.config=resident.config,.roi=++serial,
    .binary_generation=binary_generation?binary_generation:++serial,.data=(uintptr_t)memory};
   if(!roi_token.roi)roi_token.roi=++serial;
   if(ioctl(fd,QR_FITNESS_LOAD_ROI,&roi_token)){failure(&failures.prepare_ioctl,errno);goto fault;}
   roi_loaded=1;++r3_metrics.roi_loads;metrics.bytes+=words*4;
  }
  memset(&grid_request,0,sizeof(grid_request));grid_request.version=2;
  grid_request.epoch=resident.epoch;grid_request.frame=resident.frame;grid_request.config=resident.config;
  grid_request.roi=roi_token.roi;grid_request.binary_generation=roi_token.binary_generation;
  grid_request.job=resident.job;grid_request.cells=n;grid_request.features=(uintptr_t)f;
  if(!grid_mode){if(ioctl(fd,QR_FITNESS_LOAD_GRID,&grid_request)){failure(&failures.prepare_ioctl,errno);release_roi();goto fault;}metrics.bytes+=n*4;}
 }else if(ioctl(fd,QR_FITNESS_PREPARE,&resident)){failure(&failures.prepare_ioctl,errno);goto fault;}
 phases.prepare_ioctl_us+=qr_profile_now()-phase;if(!reuse_mode)diagnostic(0);
 metrics.prepare_us+=qr_profile_now()-begin;if(!reuse_mode)metrics.bytes+=(words+n)*4;++metrics.prepared;active=1;return 1;
fault:++metrics.faults;failed=1;return 0;
}
int qr_fitness_evaluate(const double c[8],int *score){
 struct qr_fitness_score s={0};uint64_t begin;
 if(!active||failed||grid_mode)return 0;
 s.version=1;s.epoch=resident.epoch;s.frame=resident.frame;s.config=resident.config;s.job=resident.job;
 memcpy(s.coefficients,c,sizeof(s.coefficients));begin=qr_profile_now();
 if(ioctl(fd,QR_FITNESS_SCORE,&s)){
  int error=errno;failure((error==ERANGE||error==EINVAL)?&failures.unsupported_coefficients:&failures.score_ioctl,error);failed=1;++metrics.faults;return 0;
 }
 if(s.status||s.job!=resident.job||s.epoch!=resident.epoch||s.frame!=resident.frame||s.config!=resident.config){failure(&failures.bad_completion,EPROTO);failed=1;++metrics.faults;return 0;}
 metrics.score_us+=qr_profile_now()-begin;++metrics.hardware_calls;++r3_metrics.logical_scores;diagnostic(1);*score=s.score;return 1;
}
int qr_fitness_compare(void){return compare;}
void qr_fitness_mismatch(void){failure(&failures.mismatch,EPROTO);++metrics.mismatches;if(grid_mode)++r3_metrics.trace_differences;failed=1;}
void qr_fitness_software_time(uint64_t us){metrics.software_us+=us;++metrics.compared;}
int qr_fitness_end(void){
 uint64_t begin=qr_profile_now();
 if(active&&!reuse_mode&&ioctl(fd,QR_FITNESS_RELEASE)){failure(&failures.release_ioctl,errno);++metrics.faults;failed=1;}
 if(active)metrics.release_us+=qr_profile_now()-begin;
 if(reference_active&&reference_step!=81)qr_fitness_mismatch();
 active=0;reference_active=0;
 if(reuse_mode&&(!binary_owner||failed))release_roi();
 if(failed)++metrics.fallback_grids;return failed;
}
void qr_fitness_get_metrics(struct qr_fitness_metrics *out){if(out)*out=metrics;}

void qr_fitness_get_prepare_metrics(struct qr_fitness_prepare_metrics *out){if(out)*out=phases;}

int qr_fitness_get_phase_metrics(void *out,uint32_t bytes){if(!out||bytes!=sizeof(details))return -1;memcpy(out,&details,sizeof(details));return 0;}

int qr_fitness_get_fault_metrics(void *out,uint32_t bytes){if(!out||bytes!=sizeof(failures))return -1;memcpy(out,&failures,sizeof(failures));return 0;}

int qr_fitness_get_r3_metrics(void *out,uint32_t bytes){if(!out||bytes!=sizeof(r3_metrics))return -1;memcpy(out,&r3_metrics,sizeof(r3_metrics));return 0;}

static void release_roi(void){
 uint64_t started;
 if(!roi_loaded)return;
 struct qr_fitness_roi_release p={.version=2,.epoch=roi_token.epoch,.frame=roi_token.frame,
  .config=roi_token.config,.roi=roi_token.roi,.binary_generation=roi_token.binary_generation};
 started=qr_profile_now();
 if(ioctl(fd,QR_FITNESS_RELEASE_ROI,&p)){
  if(errno!=ESTALE){failure(&failures.release_ioctl,errno);++metrics.faults;
   /* close() takes the driver's noninterruptible recovery path. */
   close(fd);fd=-1;device_v2=-1;
  }
 }else ++r3_metrics.roi_releases;
 uint64_t elapsed=qr_profile_now()-started;
 metrics.release_us+=elapsed;
 roi_loaded=0;
}
int qr_fitness_grid_mode(void){return active&&grid_mode;}
int qr_fitness_optimize(double c[8]){
 uint64_t started=qr_profile_now(),tree_started;
 if(!active||failed||!grid_mode)return 0;
 if(!candidate_tree)candidate_tree=malloc(QR_FITNESS_TREE_BYTES);
 if(!candidate_tree){failure(&failures.allocation,ENOMEM);goto bad;}
 tree_started=qr_profile_now();
 if(qr_fitness_tree_build(c,candidate_tree)){failure(&failures.unsupported_coefficients,ERANGE);goto bad;}
 r3_metrics.tree_us+=qr_profile_now()-tree_started;r3_metrics.tree_bytes+=QR_FITNESS_TREE_BYTES;
 grid_request.tree=(uintptr_t)candidate_tree;
 grid_request.flags=compare?QR_FITNESS_JOB_TRACE:0;
 memcpy(grid_request.coefficients,c,64);memcpy(reference_c,c,64);
 memset(reference_node,0,sizeof(reference_node));reference_step=0;
 if(ioctl(fd,QR_FITNESS_OPTIMIZE_GRID,&grid_request)){
  int error=errno;failure((error==ERANGE||error==EINVAL)?&failures.unsupported_coefficients:&failures.score_ioctl,error);goto bad;
 }
 if(grid_request.status||grid_request.score_count!=81||grid_request.error_step||grid_request.job!=resident.job||
    grid_request.epoch!=resident.epoch||grid_request.frame!=resident.frame||grid_request.config!=resident.config||
    grid_request.roi!=roi_token.roi||grid_request.binary_generation!=roi_token.binary_generation){failure(&failures.bad_completion,EPROTO);goto bad;}
 memcpy(c,grid_request.coefficients,64);reference_active=compare;
 metrics.score_us+=qr_profile_now()-started;++metrics.hardware_calls;
 ++r3_metrics.grid_jobs;r3_metrics.logical_scores+=81;
 metrics.bytes+=grid_request.cells*4+QR_FITNESS_TREE_BYTES;return 1;
bad:failed=1;release_roi();++metrics.faults;return 0;
}
void qr_fitness_reference_score(const double c[8],int score){
 unsigned n,j=0;uint64_t old=0;int hardware_score,accept;
 if(!reference_active)return;
 n=reference_step++;
 if(n>=81){qr_fitness_mismatch();return;}
 if(n){j=((n-1)%16)/2;old=reference_c[j];reference_c[j]=candidate_tree[j*1023+reference_node[j]];}
 hardware_score=(int32_t)(grid_request.trace[n]<<1)>>1;
 accept=n&&score>reference_best;
 if(hardware_score!=score||((grid_request.trace[n]>>31)!=!!accept)||memcmp(c,reference_c,64)){
  qr_fitness_mismatch();
 }
 if(!n||accept)reference_best=score;
 if(n){
  int hardware_accept=grid_request.trace[n]>>31;
  if(!hardware_accept)reference_c[j]=old;
  reference_node[j]=reference_node[j]*2+1+hardware_accept;
 }
}
