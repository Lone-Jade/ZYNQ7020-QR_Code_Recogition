// SPDX-License-Identifier: GPL-2.0-only
/* Exclusive, bounded jobs. All HP buffers are owned by this driver. */
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/clk.h>
#include <linux/miscdevice.h>
#include <linux/fs.h>
#include <linux/uaccess.h>
#include <linux/dma-mapping.h>
#include <linux/interrupt.h>
#include <linux/completion.h>
#include <linux/gpio/consumer.h>
#include <linux/delay.h>
#include <linux/io.h>
#include <linux/iopoll.h>
#include <linux/ktime.h>
#include <linux/mutex.h>
#include <linux/bitops.h>
#include "ax7021b_fitness.h"
#include "qr_fitness_registers.h"
static bool profile;
module_param(profile,bool,0644);
MODULE_PARM_DESC(profile,"Collect CPU and passive-PL phase diagnostics; disabled during performance acceptance");
static bool optimize_writes;
module_param(optimize_writes,bool,0644);
MODULE_PARM_DESC(optimize_writes,"Cache unchanged control/coefficient bits; sampled at PREPARE, disabled by default");
#define REG(name) XQR_FITNESS_CONTROL_ADDR_##name
struct fitness {
 struct device *dev; void __iomem *regs; struct clk *clock;
 struct gpio_desc *reset; struct miscdevice misc; struct mutex lock;
 void __iomem *profile_regs; struct qr_fitness_profile trace;
 bool collect; u32 score_ordinal,profile_version; u64 irq_enter,irq_end,writes,run_wait;
 bool optimize,coefficients_valid,control_valid,interrupt_ready;
 u64 coefficient_cache[8];u32 operation_cache,job_cache;
 struct completion done; atomic_t opened; bool valid,broken;
 int irq; bool load_pending,quarantined;
 u64 negative_perspective_limit;
 bool job_abi,roi_valid;u32 roi_id,binary_generation;
 void *job_cpu;dma_addr_t job_dma;struct qr_fitness_job_stats jobs;
 void *cpu; dma_addr_t dma; struct qr_fitness_prepare resident;
 struct qr_fitness_stats stats;
};
static void wr(struct fitness *f,u32 reg,u32 x){iowrite32(x,f->regs+reg);if(f->collect)++f->writes;}
static u32 rd(struct fitness *f,u32 reg){return ioread32(f->regs+reg);}
static void invalidate_cache(struct fitness *f){
 f->coefficients_valid=f->control_valid=f->interrupt_ready=false;
}
static void recover(struct fitness *f){
 u32 status;
 invalidate_cache(f);
 if(f->quarantined)return;
 /* The HLS AXI-Lite slave shares ap_rst_n: do not touch its registers while
  * reset is low, including the initial probe. Quiesce CPU IRQ access first. */
 f->valid=false;f->roi_valid=false;disable_irq(f->irq);
 /* LOAD_ROI, LOAD_GRID and OPTIMIZE also issue HP reads. Never reset the AXI master
  * while its transactions may still be outstanding in the PS/interconnect.
  * Keep its DMA allocation/module alive until reboot if bounded drain fails. */
 if(f->load_pending){
  wr(f,REG(GIE),0);
  if(read_poll_timeout(rd,status,status&4,50,200000,false,f,REG(AP_CTRL))){
   f->broken=f->quarantined=true;__module_get(THIS_MODULE);
   dev_err(f->dev,"LOAD did not drain; accelerator quarantined, reboot required\n");
   return;
  }
  f->load_pending=false;
 }
 gpiod_set_value_cansleep(f->reset,0);usleep_range(10,20);
 gpiod_set_value_cansleep(f->reset,1);usleep_range(10,20);
 wr(f,REG(GIE),0);
 f->broken=!(rd(f,REG(AP_CTRL))&4);
 /* Explicitly invalidate resident storage, independent of HLS reset policy.
  * INVALIDATE never issues HP reads; IRQ is masked throughout this poll. */
 if(!f->broken&&f->job_abi){
  rd(f,REG(AP_CTRL));wr(f,REG(OPERATION_DATA),2);wr(f,REG(JOB_ID_DATA),0);
  wr(f,REG(AP_CTRL),1);
  if(read_poll_timeout(rd,status,status&2,10,20000,false,f,REG(AP_CTRL))||rd(f,REG(STATUS_DATA)))f->broken=true;
  wr(f,REG(ISR),rd(f,REG(ISR))&1);
 }
 enable_irq(f->irq);
}
static irqreturn_t fitness_irq(int irq,void *arg){
 struct fitness *f=arg;u64 irq_started=f->collect?ktime_get_ns():0;u32 status=rd(f,REG(ISR));
 if(!(status&1))return IRQ_NONE;
 if(f->collect)f->irq_enter=irq_started;
 wr(f,REG(ISR),status&1);
 /* Flush the posted acknowledge before waking the next optimized SCORE.
  * It retains IRQ completion and cannot consume a stale high interrupt. */
 if(f->optimize)rd(f,REG(ISR));
 if(f->collect)f->irq_end=ktime_get_ns();
 complete(&f->done);return IRQ_HANDLED;
}
static int run(struct fitness *f,u32 operation,u32 job){
 u64 started=ktime_get_ns(),stamp=0,woke=0;long completed;u32 expected_generation=0;bool observe=f->collect&&f->profile_regs&&operation!=2&&(operation!=1||f->score_ordinal%QR_FITNESS_PROFILE_STRIDE==0);int ret=0;
 if(f->broken)return -EIO;
 if(operation==1)++f->score_ordinal;
 if(!f->optimize){
  wr(f,REG(GIE),0);wr(f,REG(ISR),rd(f,REG(ISR))&1);
  reinit_completion(&f->done);wr(f,REG(OPERATION_DATA),operation);
  wr(f,REG(JOB_ID_DATA),job);wr(f,REG(IER),1);wr(f,REG(GIE),1);
 }else{
  reinit_completion(&f->done);
  if(!f->interrupt_ready){
   wr(f,REG(GIE),0);wr(f,REG(ISR),rd(f,REG(ISR))&1);rd(f,REG(ISR));
   wr(f,REG(IER),1);wr(f,REG(GIE),1);f->interrupt_ready=true;
  }
  if(!f->control_valid||f->operation_cache!=operation)wr(f,REG(OPERATION_DATA),operation);
  if(!f->control_valid||f->job_cache!=job)wr(f,REG(JOB_ID_DATA),job);
  f->operation_cache=operation;f->job_cache=job;f->control_valid=true;
 }
 if(observe)expected_generation=ioread32(f->profile_regs+16)+1;
 dma_wmb();
 if(f->collect){stamp=ktime_get_ns();f->trace.register_ns+=stamp-f->run_wait;f->trace.operation=operation;}
 wr(f,REG(AP_CTRL),1);
 if(operation==0||operation==3||operation==4||operation==5)f->load_pending=true;
 completed=wait_for_completion_timeout(&f->done,msecs_to_jiffies(operation==4?200:20));
 if(f->collect)woke=ktime_get_ns();
 if(!completed){
  ++f->stats.timeouts;ret=-ETIMEDOUT;
 }else{
  /* An IRQ can be stale or corrupt: never drop HP ownership until both
   * completion identity and AP_IDLE prove this exact job has drained. */
  if(!(rd(f,REG(AP_CTRL))&4)||rd(f,REG(COMPLETED_JOB_DATA))!=job)ret=-EPROTO;
  else {u32 status=rd(f,REG(STATUS_DATA));if(status)ret=status==3?-ERANGE:status==2?-ESTALE:-EINVAL;}
  if(!ret&&(operation==0||operation==3||operation==4||operation==5))f->load_pending=false;
 }
 if(f->collect){
  u32 words[18],a,b;int i;
  f->trace.wait_ns=woke-stamp;
  if(f->irq_end>=stamp){f->trace.isr_ns=f->irq_end-f->irq_enter;f->trace.wake_ns=woke>=f->irq_end?woke-f->irq_end:0;}
  if(observe&&!ret){
   a=ioread32(f->profile_regs+16);
   for(i=0;i<18;i++)words[i]=ioread32(f->profile_regs+i*4);
   b=ioread32(f->profile_regs+16);
   if(a==expected_generation&&a==b&&words[0]==0xAC04F002&&words[1]==f->profile_version&&!words[11]&&words[5]==operation&&words[6]==job&&words[7]==f->resident.epoch&&words[8]==f->resident.frame&&words[9]==f->resident.config){
    f->trace.flags|=2;f->trace.ordinal=words[10];
    f->trace.pl_start=words[12]|((u64)words[13]<<32);f->trace.pl_end=words[14]|((u64)words[15]<<32);f->trace.pl_cycles=words[16]|((u64)words[17]<<32);
   }else f->trace.flags|=4;
  }
  f->trace.result_ns+=ktime_get_ns()-woke;
 }
 /* Legacy name includes MMIO, IP execution, IRQ delivery and scheduling. */
 f->stats.hardware_ns+=ktime_get_ns()-started;
 if(ret)recover(f);
 return ret;
}
static int fitness_open(struct inode *ino,struct file *file){
 struct fitness *f=container_of(file->private_data,struct fitness,misc);
 if(atomic_cmpxchg(&f->opened,0,1))return -EBUSY;
 file->private_data=f;mutex_lock(&f->lock);recover(f);mutex_unlock(&f->lock);
 return nonseekable_open(ino,file);
}
static int fitness_close(struct inode *ino,struct file *file){
 struct fitness *f=file->private_data;mutex_lock(&f->lock);recover(f);
 mutex_unlock(&f->lock);atomic_set(&f->opened,0);return 0;
}
static bool roi_identity(struct fitness *f,u32 epoch,u32 frame,u32 config,u32 roi,u32 generation){
 return f->roi_valid&&epoch==f->resident.epoch&&frame==f->resident.frame&&config==f->resident.config&&roi==f->roi_id&&generation==f->binary_generation;
}
static int check_features(struct fitness *f,u32 cells){
 u32 i,max_coordinate=1;
 for(i=0;i<cells;i++){
  u32 cell=((u32*)f->job_cpu)[i];s32 weight=(s8)(cell>>16);
  if((cell&255)>=177||((cell>>8)&255)>=177||cell>>24||(weight!=1&&weight!=-1))return -EINVAL;
  max_coordinate=max(max_coordinate,(cell&255)+1);
  max_coordinate=max(max_coordinate,((cell>>8)&255)+1);
 }
 f->negative_perspective_limit=(u64)(1023-fls(4*max_coordinate-1))<<52;
 return 0;
}
static int check_coefficients(struct fitness *f,const u64 c[8]){
 unsigned i;
 for(i=0;i<8;i++){
  u32 exponent=(c[i]>>52)&2047;u64 magnitude=c[i]&0x7fffffffffffffffULL;
  if(exponent==2047)return -EINVAL;
  if(magnitude&&(exponent<923||exponent>1122))return -ERANGE;
  if(i>=6&&(c[i]>>63)&&magnitude>f->negative_perspective_limit)return -ERANGE;
 }
 return 0;
}
static void set_coefficients(struct fitness *f,const u64 c[8]){
 unsigned i;
 for(i=0;i<8;i++){
  wr(f,REG(C0_DATA)+12*i,lower_32_bits(c[i]));
  wr(f,REG(C0_DATA)+12*i+4,upper_32_bits(c[i]));
 }
 f->coefficients_valid=false;
}
static int job_ioctl(struct fitness *f,unsigned int cmd,void __user *user){
 u64 started=ktime_get_ns(),stamp;unsigned i;int ret;
 if(cmd==QR_FITNESS_CAPABILITIES){
  struct qr_fitness_capabilities c={.version=2,.capabilities=f->stats.capabilities,
   .max_roi_words=28800,.max_cells=2048,.tree_nodes=QR_FITNESS_JOB_TREE_NODES,
   .trace_entries=81,.magic=f->job_abi?0xAC04F003:0,.hardware_abi=f->job_abi?2:1};
  u32 version;if(copy_from_user(&version,user,4))return -EFAULT;
  if(version!=2)return -EINVAL;
  return copy_to_user(user,&c,sizeof(c))?-EFAULT:0;
 }
 if(!f->job_abi)return -EOPNOTSUPP;
 if(cmd==QR_FITNESS_JOB_STATS)return copy_to_user(user,&f->jobs,sizeof(f->jobs))?-EFAULT:0;
 if(cmd==QR_FITNESS_LOAD_ROI){
  struct qr_fitness_roi p;u32 words;
  if(copy_from_user(&p,user,sizeof(p)))return -EFAULT;
  if(p.version!=2||p.flags||!p.width||p.width>1280||!p.height||p.height>720||
     p.stride!=(p.width+31)/32||!p.roi||!p.binary_generation)return -EINVAL;
  f->roi_valid=f->valid=false;invalidate_cache(f);f->optimize=READ_ONCE(optimize_writes);
  words=p.stride*p.height;stamp=ktime_get_ns();
  if(copy_from_user(f->cpu,u64_to_user_ptr(p.data),words*4))return -EFAULT;
  f->jobs.copy_ns+=ktime_get_ns()-stamp;stamp=ktime_get_ns();
  f->resident=(struct qr_fitness_prepare){.version=1,.width=p.width,.height=p.height,
   .stride=p.stride,.epoch=p.epoch,.frame=p.frame,.config=p.config};
  f->roi_id=p.roi;f->binary_generation=p.binary_generation;
  wr(f,REG(MEMORY_R_DATA),lower_32_bits(f->dma));wr(f,REG(MEMORY_R_DATA)+4,0);
  wr(f,REG(WIDTH_DATA),p.width);wr(f,REG(HEIGHT_DATA),p.height);wr(f,REG(STRIDE_WORDS_DATA),p.stride);
  wr(f,REG(EPOCH_DATA),p.epoch);wr(f,REG(FRAME_DATA),p.frame);wr(f,REG(CONFIG_R_DATA),p.config);
  wr(f,REG(ROI_ID_DATA),p.roi);wr(f,REG(BINARY_GENERATION_DATA),p.binary_generation);
  f->jobs.register_ns+=ktime_get_ns()-stamp;f->run_wait=ktime_get_ns();
  ret=run(f,3,p.roi);if(ret)return ret;
  f->roi_valid=true;++f->jobs.roi_loads;f->jobs.bytes+=words*4;
  return 0;
 }
 if(cmd==QR_FITNESS_RELEASE_ROI){
  struct qr_fitness_roi_release p;
  if(copy_from_user(&p,user,sizeof(p)))return -EFAULT;
  if(p.version!=2||!roi_identity(f,p.epoch,p.frame,p.config,p.roi,p.binary_generation))return -ESTALE;
  recover(f);++f->jobs.roi_releases;return f->broken?-EIO:0;
 }
 if(cmd==QR_FITNESS_LOAD_GRID||cmd==QR_FITNESS_OPTIMIZE_GRID){
  struct qr_fitness_grid p;
  if(copy_from_user(&p,user,sizeof(p)))return -EFAULT;
  if(p.version!=2||p.reserved||p.padding||(p.flags&~QR_FITNESS_JOB_TRACE)||!p.job||!p.cells||p.cells>2048)return -EINVAL;
  if(!roi_identity(f,p.epoch,p.frame,p.config,p.roi,p.binary_generation))return -ESTALE;
  /* Match the PS per-grid diagnostic stride, including reused ROI grids. */
  f->score_ordinal=0;
  f->valid=false;stamp=ktime_get_ns();
  if(copy_from_user(f->job_cpu,u64_to_user_ptr(p.features),p.cells*4))return -EFAULT;
  if(cmd==QR_FITNESS_OPTIMIZE_GRID&&copy_from_user(f->job_cpu+p.cells*4,u64_to_user_ptr(p.tree),QR_FITNESS_TREE_WORDS*4))return -EFAULT;
  f->jobs.copy_ns+=ktime_get_ns()-stamp;
  ret=check_features(f,p.cells);if(ret)return ret;
  if(cmd==QR_FITNESS_OPTIMIZE_GRID){ret=check_coefficients(f,p.coefficients);if(ret)return ret;}
  stamp=ktime_get_ns();
  wr(f,REG(MEMORY_R_DATA),lower_32_bits(f->job_dma));wr(f,REG(MEMORY_R_DATA)+4,0);
  wr(f,REG(CELLS_DATA),p.cells);wr(f,REG(TREE_WORD_OFFSET_DATA),p.cells);
  wr(f,REG(TRACE_ENABLE_DATA),!!(p.flags&QR_FITNESS_JOB_TRACE));
  if(cmd==QR_FITNESS_OPTIMIZE_GRID)set_coefficients(f,p.coefficients);
  f->resident.job=p.job;f->resident.cells=p.cells;
  f->jobs.register_ns+=ktime_get_ns()-stamp;f->run_wait=ktime_get_ns();stamp=ktime_get_ns();
  ret=run(f,cmd==QR_FITNESS_OPTIMIZE_GRID?4:5,p.job);
  f->jobs.wait_ns+=ktime_get_ns()-stamp;if(ret)return ret;
  f->valid=true;++f->jobs.grid_loads;f->jobs.bytes+=p.cells*4;
  p.status=0;p.error_step=0;p.score_count=0;p.score=0;memset(p.trace,0,sizeof(p.trace));
  if(cmd==QR_FITNESS_OPTIMIZE_GRID){
   stamp=ktime_get_ns();p.score_count=rd(f,REG(SCORE_COUNT_DATA));
   p.error_step=rd(f,REG(ERROR_STEP_DATA));
   if(p.score_count!=81||p.error_step)return -EPROTO;
   p.score=(s32)rd(f,REG(SCORE_DATA));
   for(i=0;i<8;i++)p.coefficients[i]=rd(f,REG(RESULT_COEFFICIENTS_BASE)+i*8)|((u64)rd(f,REG(RESULT_COEFFICIENTS_BASE)+i*8+4)<<32);
   ret=check_coefficients(f,p.coefficients);if(ret)return ret;
   if(p.flags&QR_FITNESS_JOB_TRACE)for(i=0;i<81;i++)p.trace[i]=rd(f,REG(TRACE_BASE)+i*4);
   f->jobs.result_ns+=ktime_get_ns()-stamp;++f->jobs.grid_jobs;f->jobs.logical_scores+=81;
   f->jobs.bytes+=QR_FITNESS_TREE_WORDS*4;
  }
  p.elapsed_ns=ktime_get_ns()-started;
  if(copy_to_user(user,&p,sizeof(p)))return -EFAULT;
  f->jobs.ioctl_ns+=ktime_get_ns()-started;return 0;
 }
 return -ENOTTY;
}
static long fitness_ioctl(struct file *file,unsigned int cmd,unsigned long arg){
 struct fitness *f=file->private_data;void __user *user=(void __user *)arg;
 struct qr_fitness_prepare p;struct qr_fitness_score s;int ret=0;u32 words,i,max_coordinate;u64 begin,entered=0,stamp=0,writes=0;
 bool readonly=cmd==QR_FITNESS_GET_PROFILE||cmd==QR_FITNESS_STATS||cmd==QR_FITNESS_CAPABILITIES||cmd==QR_FITNESS_JOB_STATS;
 if(mutex_lock_interruptible(&f->lock))return -ERESTARTSYS;
 if(f->quarantined&&cmd!=QR_FITNESS_STATS){mutex_unlock(&f->lock);return -EIO;}
 if(!readonly)
  f->collect=READ_ONCE(profile)&&(cmd!=QR_FITNESS_SCORE||f->score_ordinal%QR_FITNESS_PROFILE_STRIDE==0);
 if(f->collect&&!readonly){
  entered=ktime_get_ns();writes=f->writes;memset(&f->trace,0,sizeof(f->trace));f->trace.version=1;f->trace.capabilities=f->profile_regs?3:1;f->trace.flags=1;
 }
 switch(cmd){
 case QR_FITNESS_CAPABILITIES:case QR_FITNESS_LOAD_ROI:case QR_FITNESS_LOAD_GRID:
 case QR_FITNESS_OPTIMIZE_GRID:case QR_FITNESS_RELEASE_ROI:case QR_FITNESS_JOB_STATS:
  ret=job_ioctl(f,cmd,user);break;
 case QR_FITNESS_PREPARE:
  f->valid=false;f->roi_valid=false;f->score_ordinal=0;invalidate_cache(f);f->optimize=READ_ONCE(optimize_writes);
  if(copy_from_user(&p,user,sizeof(p))){ret=-EFAULT;break;}
  if(p.version!=QR_FITNESS_ABI||p.flags||!p.width||p.width>1280||!p.height||p.height>720||
   p.stride!=(p.width+31)/32||!p.cells||p.cells>2048||!p.job){ret=-EINVAL;break;}
  words=p.stride*p.height+p.cells;
  if(words>QR_FITNESS_MAX_WORDS){ret=-E2BIG;break;}
  if(f->collect)stamp=ktime_get_ns();
  if(copy_from_user(f->cpu,u64_to_user_ptr(p.data),words*4)){ret=-EFAULT;break;}
  if(f->collect)f->trace.copy_ns=ktime_get_ns()-stamp;
  /* Reject malformed feature encodings; cells must be in a QR v1..40 grid. */
  max_coordinate=1;
  for(i=p.stride*p.height;i<words;i++){
   u32 cell=((u32*)f->cpu)[i];s32 weight=(s8)(cell>>16);
   if((cell&0xff)>=177||((cell>>8)&0xff)>=177||cell>>24||(weight!=1&&weight!=-1)){ret=-EINVAL;break;}
   max_coordinate=max(max_coordinate,(cell&255)+1);
   max_coordinate=max(max_coordinate,((cell>>8)&255)+1);
  }
  if(ret)break;
  /* Each negative projective term is below 1/4 over this feature domain.
   * Thus the denominator stays above 1/2, even when both slopes are negative.
   * Compare IEEE bit patterns, never execute kernel FP instructions. */
  f->negative_perspective_limit=(u64)(1023-fls(4*max_coordinate-1))<<52;
  if(f->broken)recover(f);
  if(f->job_abi){wr(f,REG(ROI_ID_DATA),0);wr(f,REG(BINARY_GENERATION_DATA),0);}
  f->resident=p;if(f->collect)f->run_wait=ktime_get_ns();
  wr(f,REG(MEMORY_R_DATA),lower_32_bits(f->dma));wr(f,REG(MEMORY_R_DATA)+4,0);
  wr(f,REG(WIDTH_DATA),p.width);wr(f,REG(HEIGHT_DATA),p.height);
  wr(f,REG(STRIDE_WORDS_DATA),p.stride);wr(f,REG(CELLS_DATA),p.cells);
  wr(f,REG(EPOCH_DATA),p.epoch);wr(f,REG(FRAME_DATA),p.frame);wr(f,REG(CONFIG_R_DATA),p.config);
  ret=run(f,0,p.job);if(!ret){f->resident=p;f->valid=true;++f->stats.prepares;f->stats.bytes+=words*4;}break;
 case QR_FITNESS_SCORE:
  if(f->collect)stamp=ktime_get_ns();
  if(copy_from_user(&s,user,sizeof(s))){ret=-EFAULT;break;}
  if(f->collect)f->trace.copy_ns=ktime_get_ns()-stamp;
  if(s.version!=QR_FITNESS_ABI||s.reserved||!f->valid||s.epoch!=f->resident.epoch||
     s.frame!=f->resident.frame||s.config!=f->resident.config||s.job!=f->resident.job){ret=-ESTALE;break;}
  /* PG060 arithmetic flushes subnormals. Restrict accepted coefficients so
   * every finite intermediate stays normal: |c| in [2^-100,2^100), or zero.
   * Feature coordinates are below 177. Even exact cancellation cannot reach
   * the binary64 subnormal range. Outside this domain the PS reruns C04. */
  for(i=0;i<8;i++){
   u32 exponent=(s.coefficients[i]>>52)&2047;
   u64 magnitude=s.coefficients[i]&0x7fffffffffffffffULL;
   if(exponent==2047){ret=-EINVAL;break;}
   if(magnitude&&(exponent<923||exponent>1122)){ret=-ERANGE;break;}
   if(i>=6&&(s.coefficients[i]>>63)&&magnitude>f->negative_perspective_limit){ret=-ERANGE;break;}
  }
  if(ret)break;
  begin=ktime_get_ns();if(f->collect)f->run_wait=begin;
  for(i=0;i<8;i++){
   u64 previous=f->coefficient_cache[i],next=s.coefficients[i];
   if(!f->optimize||!f->coefficients_valid||lower_32_bits(previous)!=lower_32_bits(next))wr(f,REG(C0_DATA)+12*i,lower_32_bits(next));
   if(!f->optimize||!f->coefficients_valid||upper_32_bits(previous)!=upper_32_bits(next))wr(f,REG(C0_DATA)+12*i+4,upper_32_bits(next));
   f->coefficient_cache[i]=next;
  }
  f->coefficients_valid=true;
  ret=run(f,1,s.job);if(ret)break;
  if(f->collect)stamp=ktime_get_ns();
  s.score=(s32)rd(f,REG(SCORE_DATA));s.status=0;s.elapsed_ns=ktime_get_ns()-begin;
  ++f->stats.scores;if(copy_to_user(user,&s,sizeof(s)))ret=-EFAULT;
  if(f->collect)f->trace.result_ns+=ktime_get_ns()-stamp;
  break;
 case QR_FITNESS_RELEASE:recover(f);++f->stats.releases;break;
 case QR_FITNESS_GET_PROFILE: {
  u32 version;
  if(copy_from_user(&version,user,sizeof(version))){ret=-EFAULT;break;}
  if(version!=QR_FITNESS_PROFILE_ABI){ret=-EINVAL;break;}
  if(!f->collect){ret=-ENODATA;break;}
  if(copy_to_user(user,&f->trace,sizeof(f->trace)))ret=-EFAULT;
  break;
 }
 case QR_FITNESS_STATS:if(copy_to_user(user,&f->stats,sizeof(f->stats)))ret=-EFAULT;break;
 default:ret=-ENOTTY;
 }
 if(f->collect&&entered){
  f->trace.ioctl_ns=ktime_get_ns()-entered;f->trace.control_writes=f->writes-writes;
  f->trace.epoch=f->resident.epoch;f->trace.frame=f->resident.frame;f->trace.config=f->resident.config;f->trace.job=f->resident.job;
 }
 if(ret&&cmd!=QR_FITNESS_GET_PROFILE){
  ++f->stats.rejected;
  if(cmd!=QR_FITNESS_CAPABILITIES&&cmd!=QR_FITNESS_JOB_STATS)recover(f);
 }
 mutex_unlock(&f->lock);return ret;
}
static const struct file_operations fitness_fops={.owner=THIS_MODULE,.open=fitness_open,.release=fitness_close,.unlocked_ioctl=fitness_ioctl};
static int fitness_probe(struct platform_device *pdev){
 struct fitness *f;int irq,ret;
 f=devm_kzalloc(&pdev->dev,sizeof(*f),GFP_KERNEL);if(!f)return -ENOMEM;f->dev=&pdev->dev;
 f->clock=devm_clk_get_enabled(f->dev,"s_axi_aclk");if(IS_ERR(f->clock))return PTR_ERR(f->clock);
 f->regs=devm_platform_ioremap_resource(pdev,0);if(IS_ERR(f->regs))return PTR_ERR(f->regs);
 if(platform_get_resource(pdev,IORESOURCE_MEM,1)){
  f->profile_regs=devm_platform_ioremap_resource(pdev,1);if(IS_ERR(f->profile_regs))return PTR_ERR(f->profile_regs);
  if(ioread32(f->profile_regs)!=0xAC04F002)return -ENODEV;
  f->profile_version=ioread32(f->profile_regs+4);if(f->profile_version!=1&&f->profile_version!=2)return -ENODEV;
 }
 f->reset=devm_gpiod_get(f->dev,"reset",GPIOD_OUT_LOW);if(IS_ERR(f->reset))return PTR_ERR(f->reset);
 ret=dma_set_mask_and_coherent(f->dev,DMA_BIT_MASK(32));if(ret)return ret;
 f->cpu=dmam_alloc_coherent(f->dev,QR_FITNESS_MAX_WORDS*4,&f->dma,GFP_KERNEL);if(!f->cpu)return -ENOMEM;
 f->job_abi=of_device_is_compatible(pdev->dev.of_node,"qrproject,c04-fitness-v2");
 if(f->job_abi){f->job_cpu=dmam_alloc_coherent(f->dev,QR_FITNESS_GRID_WORDS*4,&f->job_dma,GFP_KERNEL);if(!f->job_cpu)return -ENOMEM;}
 mutex_init(&f->lock);init_completion(&f->done);atomic_set(&f->opened,0);
 irq=platform_get_irq(pdev,0);if(irq<0)return irq;
 f->irq=irq;
 ret=devm_request_irq(f->dev,irq,fitness_irq,0,dev_name(f->dev),f);if(ret)return ret;
 f->stats.version=QR_FITNESS_ABI;f->stats.capabilities=QR_FITNESS_CAP_BOUNDED_BINARY64|QR_FITNESS_CAP_TAGGED_JOBS|QR_FITNESS_CAP_CACHED_ROI;recover(f);if(f->broken)return -EIO;
 if(f->profile_regs)f->stats.capabilities|=QR_FITNESS_CAP_PROFILE;
 if(f->job_abi){
  ret=run(f,2,0);if(ret)return ret;
  if(rd(f,REG(HARDWARE_MAGIC_DATA))!=0xAC04F003||rd(f,REG(HARDWARE_ABI_DATA))!=2)return -ENODEV;
  f->stats.capabilities|=QR_FITNESS_CAP_ROI_LIFETIME|QR_FITNESS_CAP_GRID_JOB;
 }
 f->jobs.version=2;f->jobs.capabilities=f->stats.capabilities;
 f->misc.minor=MISC_DYNAMIC_MINOR;f->misc.name="ax7021b-fitness0";f->misc.fops=&fitness_fops;f->misc.parent=f->dev;
 ret=misc_register(&f->misc);if(ret)return ret;platform_set_drvdata(pdev,f);return 0;
}
static void fitness_remove(struct platform_device *pdev){struct fitness *f=platform_get_drvdata(pdev);misc_deregister(&f->misc);recover(f);}
static const struct of_device_id fitness_match[]={{.compatible="qrproject,c04-fitness-v2"},{.compatible="qrproject,c04-fitness-v1"},{}};
MODULE_DEVICE_TABLE(of,fitness_match);
static struct platform_driver fitness_driver={.probe=fitness_probe,.remove=fitness_remove,.driver={.name="ax7021b_qr_fitness",.of_match_table=fitness_match,.suppress_bind_attrs=true}};
module_platform_driver(fitness_driver);
MODULE_LICENSE("GPL");MODULE_DESCRIPTION("C04 binary64 PL perspective fitness accelerator");
