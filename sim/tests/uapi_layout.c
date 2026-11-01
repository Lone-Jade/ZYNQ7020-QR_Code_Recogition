#include <stddef.h>
#include "ax7021b_display.h"
#include "ax7021b_qr.h"
_Static_assert(sizeof(struct ax7021b_display_info)==64,"info ABI");
_Static_assert(sizeof(struct ax7021b_display_rects)==144,"four reserved rectangles");
_Static_assert(sizeof(struct ax7021b_display_text)==144,"text ABI");
_Static_assert(sizeof(struct ax7021b_display_status)==128,"status ABI");
_Static_assert(offsetof(struct ax7021b_display_status,read_irqs)==72,"aligned counters");
_Static_assert(sizeof(struct ax7021b_qr_source_tag)==32,"source tag ABI");
_Static_assert(sizeof(struct ax7021b_qr_info)==64,"old ABI unchanged");
int main(void){return 0;}
