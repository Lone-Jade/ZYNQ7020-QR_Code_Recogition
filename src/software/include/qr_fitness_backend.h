#ifndef QR_FITNESS_BACKEND_H
#define QR_FITNESS_BACKEND_H
#include <stdint.h>
struct quirc;
struct qr_fitness_metrics {
 uint64_t grids,software_grids,prepared,hardware_calls,compared,mismatches,faults,fallback_grids;
 uint64_t prepare_us,score_us,software_us,release_us,bytes;
};
void qr_fitness_set_frame(uint32_t epoch,uint32_t frame,uint32_t config);
void qr_fitness_binary_begin(const struct quirc *q);
void qr_fitness_binary_end(const struct quirc *q);
int qr_fitness_begin(const struct quirc *q,int index);
int qr_fitness_evaluate(const double c[8],int *score);
int qr_fitness_compare(void);
void qr_fitness_mismatch(void);
void qr_fitness_software_time(uint64_t us);
int qr_fitness_end(void);
int qr_fitness_grid_mode(void);
int qr_fitness_optimize(double c[8]);
void qr_fitness_reference_score(const double c[8],int score);
struct qr_fitness_r3_metrics {
 uint64_t version,binary_generations,packed_rois,pack_reuses,roi_loads,grid_jobs;
 uint64_t tree_us,tree_bytes,logical_scores,trace_differences,roi_releases;
};
int qr_fitness_get_r3_metrics(void *out,uint32_t bytes);
struct qr_fitness_prepare_metrics {uint64_t pack_us,features_us,prepare_ioctl_us;};
void qr_fitness_get_prepare_metrics(struct qr_fitness_prepare_metrics *out);
struct qr_fitness_phase_metrics {
 uint64_t version,prepare_count,score_count,copy_ns,register_ns,wait_ns,isr_ns,wake_ns,result_ns,ioctl_ns;
 uint64_t pl_load_count,pl_load_cycles,pl_score_count,pl_score_cycles,diagnostic_ns,invalid_records,control_writes;
};
struct qr_fitness_fault_metrics {
 uint64_t version,unsupported_grid,unsupported_roi,feature_overflow,open_device,allocation;
 uint64_t prepare_ioctl,unsupported_coefficients,score_ioctl,bad_completion,release_ioctl,mismatch;
 uint64_t last_errno,last_width,last_height,last_grid_size,last_epoch,last_frame,last_config,last_job;
};
int qr_fitness_get_fault_metrics(void *out,uint32_t bytes);
int qr_fitness_get_phase_metrics(void *out,uint32_t bytes);
void qr_fitness_get_metrics(struct qr_fitness_metrics *out);
#endif
