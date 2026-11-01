#ifndef QR_FITNESS_TREE_H
#define QR_FITNESS_TREE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
#define QR_FITNESS_TREE_COEFFICIENTS 8U
#define QR_FITNESS_TREE_LEVELS 10U
#define QR_FITNESS_TREE_NODES 1023U
#define QR_FITNESS_TREE_TOTAL_NODES 8184U
#define QR_FITNESS_TREE_BYTES 65472U
/* Heap nodes are candidate binary64 bits. Reject selects 2*n+1, accept 2*n+2.
 * The root is pass 0/minus; successive levels are plus, pass 1/minus, etc.
 * Compile with -ffp-contract=off -fno-fast-math, as the C04 scoring loop. */
int qr_fitness_tree_build(const double initial[8], uint64_t nodes[8184]);
#ifdef __cplusplus
}
#endif
#endif
