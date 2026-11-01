#ifndef AX7021B_DISPLAY_UAPI_H
#define AX7021B_DISPLAY_UAPI_H
#include <linux/types.h>
#include <linux/ioctl.h>
#define AX7021B_DISPLAY_ABI 2U
#define AX7021B_DISPLAY_TEXT 1U
#define AX7021B_DISPLAY_SOURCE_TAG 2U
#define AX7021B_DISPLAY_RECT_RESERVED 4U
#define AX7021B_DISPLAY_MAX_RECTS 8U
/* No rectangle-render capability is advertised in R4. Original 1280x720
 * coordinates and source epoch/frame are reserved for a later matching policy. */
struct ax7021b_display_rect { __u32 x0,y0,x1,y1,source_epoch,source_frame,flags,reserved; };
/* Reserved layout only: no submit-rectangles ioctl or render capability in R4.
 * A later implementation must define matching delayed results to scan frames. */
struct ax7021b_display_rects {
 __u32 version,count,flags,reserved;
 struct ax7021b_display_rect rect[AX7021B_DISPLAY_MAX_RECTS];
};
struct ax7021b_display_info {
 __u32 version,capabilities,width,height,stride,slots,columns,rows;
 __u32 cell_width,cell_height,color565,text_bytes,reserved[4];
};
struct ax7021b_display_text { __u32 version,sequence,flags,reserved; __u8 text[128]; };
struct ax7021b_display_status {
 __u32 version,running,requested,applied,flags,source_epoch;
 __u32 source_frames,branch_frames,display_drops,qr_drops,unique_frames,committed_frames;
 __u32 monitor_errors,valid_slots,scan_epoch,scan_frame,read_dma_status,write_dma_status;
 __aligned_u64 read_irqs,write_irqs,dma_errors,recoveries,quarantined,submissions;
 __u32 reserved[2];
};
#define AX7021B_DISPLAY_SCENE 8U
struct ax7021b_display_annotation {
 __u32 x0,y0,x1,y1,label_x,label_y,source_epoch,source_frame;
 __u8 label[64];
};
struct ax7021b_display_scene {
 __u32 version,sequence,count,reserved;
 __u8 hud[128];
 struct ax7021b_display_annotation annotation[8];
};
#define AX7021B_DISPLAY_SUBMIT_SCENE _IOW('D',5,struct ax7021b_display_scene)
#define AX7021B_DISPLAY_GET_INFO _IOR('D',0,struct ax7021b_display_info)
#define AX7021B_DISPLAY_START _IO('D',1)
#define AX7021B_DISPLAY_STOP _IO('D',2)
#define AX7021B_DISPLAY_SUBMIT _IOW('D',3,struct ax7021b_display_text)
#define AX7021B_DISPLAY_STATUS _IOR('D',4,struct ax7021b_display_status)
#endif
