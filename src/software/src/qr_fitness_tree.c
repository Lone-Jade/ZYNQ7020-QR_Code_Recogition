#include "qr_fitness_tree.h"
#include <string.h>
#if defined(__FAST_MATH__)
#error "The C04 decision tree requires strict binary64 operations"
#endif

static void build_branch(uint64_t *nodes, unsigned node, unsigned level,
                         double current, const double steps[5])
{
    double candidate;
    if (level & 1U)
        candidate = current + steps[level >> 1];
    else
        candidate = current - steps[level >> 1];
    memcpy(&nodes[node], &candidate, sizeof(candidate));
    if (level + 1U < QR_FITNESS_TREE_LEVELS) {
        build_branch(nodes, node * 2U + 1U, level + 1U, current, steps);
        build_branch(nodes, node * 2U + 2U, level + 1U, candidate, steps);
    }
}

int qr_fitness_tree_build(const double initial[8], uint64_t nodes[8184])
{
    unsigned coefficient, pass;
    if (!initial || !nodes)
        return -1;
    for (coefficient = 0; coefficient < 8; ++coefficient) {
        double steps[5];
        uint64_t bits;
        memcpy(&bits, &initial[coefficient], sizeof(bits));
        if (((bits >> 52) & 2047U) == 2047U)
            return -2;
        /* Exactly C04's initial multiplication followed by repeated halves. */
        steps[0] = initial[coefficient] * 0.02;
        for (pass = 1; pass < 5; ++pass)
            steps[pass] = steps[pass - 1] * 0.5;
        build_branch(nodes + coefficient * QR_FITNESS_TREE_NODES,
                     0, 0, initial[coefficient], steps);
    }
    return 0;
}
