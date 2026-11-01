#ifndef QR_FITNESS_H
#define QR_FITNESS_H
#include <stdint.h>
#define QR_FITNESS_ROI_WORDS 28800U
#define QR_FITNESS_CELLS 2048U
#define QR_FITNESS_MEMORY_WORDS 30848U
#define QR_FITNESS_TREE_NODES 1023U
#define QR_FITNESS_TREE_WORDS 16368U
#define QR_FITNESS_MAGIC 0xAC04F003U
#define QR_FITNESS_HW_ABI 2U
#define QR_FITNESS_HW_CAPS 0x3fU
enum qr_fitness_operation {
 QR_FITNESS_LEGACY_LOAD=0, QR_FITNESS_LEGACY_SCORE=1,
 QR_FITNESS_INVALIDATE=2, QR_FITNESS_LOAD_ROI=3,
 QR_FITNESS_OPTIMIZE=4, QR_FITNESS_LOAD_GRID=5
};
/* Old ports remain first. New fields follow the original completed_job output.
 * LOAD_ROI memory contains packed ROI only. LOAD_GRID memory contains features.
 * OPTIMIZE memory starts with features; tree_word_offset is >=cells, and
 * addresses 8*1023 candidate binary64 values as low/high uint32 words.
 * trace[0] is initial score; trace[1..80] are candidate scores (signed 31 bits)
 * and bit 31 marks acceptance. It is readable only if trace_enable was set.
 * result_coefficients contain bit patterns, never converted integers.
 * status: 0 success, 1 geometry, 2 identity/operation, 3 numeric domain,
 *         4 feature encoding, 5 tree bounds. error_step is failing 0..80.
 */
void qr_fitness(const uint32_t *memory,uint32_t operation,
 uint32_t width,uint32_t height,uint32_t stride_words,uint32_t cells,
 double c0,double c1,double c2,double c3,double c4,double c5,double c6,double c7,
 uint32_t epoch,uint32_t frame,uint32_t config,uint32_t job_id,
 int32_t *score,uint32_t *status,uint32_t *completed_job,
 uint32_t roi_id,uint32_t binary_generation,uint32_t tree_word_offset,
 uint32_t trace_enable,uint32_t *score_count,uint32_t *error_step,
 uint64_t result_coefficients[8],uint32_t trace[81],
 uint32_t *hardware_magic,uint32_t *hardware_abi,uint32_t *hardware_caps);
#endif
