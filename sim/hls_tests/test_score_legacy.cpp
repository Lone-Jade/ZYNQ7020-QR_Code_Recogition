/* Run the unchanged R2/C04 reference fixture through the v2 legacy ports.
 * This includes 40 versions, eight rotations, non-word widths and 30 explicit
 * half-integer/clipping cases, while the whole-grid fixture checks decisions. */
#include "qr_fitness.h"
static void legacy_adapter(const uint32_t *memory,uint32_t operation,
 uint32_t width,uint32_t height,uint32_t stride,uint32_t cells,
 double c0,double c1,double c2,double c3,double c4,double c5,double c6,double c7,
 uint32_t epoch,uint32_t frame,uint32_t config,uint32_t job,
 int32_t *score,uint32_t *status,uint32_t *completed)
{
 uint32_t count,error,trace[81],magic,abi,caps;uint64_t final[8];
 qr_fitness(memory,operation,width,height,stride,cells,
  c0,c1,c2,c3,c4,c5,c6,c7,epoch,frame,config,job,score,status,completed,
  0,0,0,0,&count,&error,final,trace,&magic,&abi,&caps);
}
#define qr_fitness legacy_adapter
#include "test_legacy_fitness.cpp"
#undef qr_fitness
