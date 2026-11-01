#ifndef AX7021B_FITNESS_H
#define AX7021B_FITNESS_H
#include <linux/types.h>
#include <linux/ioctl.h>
#define QR_FITNESS_ABI 1U
#define QR_FITNESS_CAP_BOUNDED_BINARY64 1U
#define QR_FITNESS_CAP_TAGGED_JOBS 2U
#define QR_FITNESS_CAP_CACHED_ROI 4U
#define QR_FITNESS_CAP_PROFILE 8U
#define QR_FITNESS_PROFILE_ABI 1U
#define QR_FITNESS_PROFILE_STRIDE 17U
#define QR_FITNESS_MAX_WORDS 30848U
#define QR_FITNESS_JOB_ABI 2U
#define QR_FITNESS_CAP_ROI_LIFETIME 16U
#define QR_FITNESS_CAP_GRID_JOB 32U
#define QR_FITNESS_JOB_TREE_NODES 8184U
#define QR_FITNESS_TREE_WORDS (QR_FITNESS_JOB_TREE_NODES*2U)
#define QR_FITNESS_GRID_WORDS (2048U+QR_FITNESS_TREE_WORDS)
#define QR_FITNESS_JOB_TRACE 1U
struct qr_fitness_capabilities {
 __u32 version,capabilities,max_roi_words,max_cells,tree_nodes,trace_entries,magic,hardware_abi;
};
struct qr_fitness_roi {
 __u32 version,flags,width,height,stride,epoch,frame,config,roi,binary_generation;
 __aligned_u64 data;
};
struct qr_fitness_grid {
 __u32 version,flags,epoch,frame,config,roi,binary_generation,job,cells,reserved;
 __aligned_u64 features,tree,coefficients[8];
 __s32 score;__u32 status,score_count,error_step;
 __aligned_u64 elapsed_ns;
 __u32 trace[81],padding;
};
struct qr_fitness_roi_release {
 __u32 version,epoch,frame,config,roi,binary_generation;
};
struct qr_fitness_job_stats {
 __u32 version,capabilities;
 __aligned_u64 roi_loads,grid_loads,grid_jobs,logical_scores,roi_releases,bytes;
 __aligned_u64 copy_ns,register_ns,wait_ns,result_ns,ioctl_ns;
};
#define QR_FITNESS_CAPABILITIES _IOWR('F',5,struct qr_fitness_capabilities)
#define QR_FITNESS_LOAD_ROI _IOW('F',6,struct qr_fitness_roi)
#define QR_FITNESS_LOAD_GRID _IOWR('F',7,struct qr_fitness_grid)
#define QR_FITNESS_OPTIMIZE_GRID _IOWR('F',8,struct qr_fitness_grid)
#define QR_FITNESS_RELEASE_ROI _IOW('F',9,struct qr_fitness_roi_release)
#define QR_FITNESS_JOB_STATS _IOR('F',10,struct qr_fitness_job_stats)
struct qr_fitness_prepare {
 __u32 version,flags,width,height,stride,cells,epoch,frame,config,job;
 __aligned_u64 data; /* packed binary rows, followed by signed feature cells */
};
struct qr_fitness_score {
 __u32 version,epoch,frame,config,job,reserved;
 __aligned_u64 coefficients[8]; /* IEEE754 binary64, no kernel FP */
 __s32 score; __u32 status;
 __aligned_u64 elapsed_ns;
};
struct qr_fitness_stats {
 __u32 version,capabilities;
 __aligned_u64 prepares,scores,releases,rejected,timeouts,bytes,hardware_ns;
};
/* Diagnostic ABI is independent of prepare/score/stats ABI and opt-in. */
struct qr_fitness_profile {
 __u32 version,capabilities,operation,flags,epoch,frame,config,job;
 __aligned_u64 ordinal,copy_ns,register_ns,wait_ns,isr_ns,wake_ns,result_ns,ioctl_ns;
 __aligned_u64 pl_cycles,pl_start,pl_end,control_writes;
};
#define QR_FITNESS_GET_PROFILE _IOWR('F',4,struct qr_fitness_profile)
#define QR_FITNESS_PREPARE _IOW('F',0,struct qr_fitness_prepare)
#define QR_FITNESS_SCORE _IOWR('F',1,struct qr_fitness_score)
#define QR_FITNESS_RELEASE _IO('F',2)
#define QR_FITNESS_STATS _IOR('F',3,struct qr_fitness_stats)
#endif
