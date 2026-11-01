#ifndef AX7021B_QR_UAPI_H
#define AX7021B_QR_UAPI_H

#include <linux/ioctl.h>
#include <linux/types.h>

#define AX7021B_QR_DEVICE_NAME "ax7021b-qr0"
#define AX7021B_QR_ABI_VERSION 0x00010000U
#define AX7021B_QR_COLOR_ABI_VERSION 0x00010001U
#define AX7021B_QR_LAYOUT_ABI 1U
#define AX7021B_QR_LAYOUT_GRAY8 0U
#define AX7021B_QR_LAYOUT_RGB565_GRAY8_ROWS 1U
#define AX7021B_QR_PL_ABI_VERSION 0x00020003U
#define AX7021B_QR_DIAG45_CAPABILITY 0x44470101U
#define AX7021B_QR_BUFFER_COUNT 3U
#define AX7021B_QR_ROI_BANK_COUNT 3U
#define AX7021B_QR_ROI_BANK_WORDS 496U

struct ax7021b_qr_info {
	__u32 abi_version;
	__u32 pl_abi_version;
	__u32 width;
	__u32 visible_height;
	__u32 storage_height;
	__u32 stride;
	__u32 buffer_count;
	__u32 frame_bytes;
	__u32 mmap_slot_bytes;
	__u32 reserved[7];
};

struct ax7021b_qr_buffer {
	__u32 index;
	__u32 bytes_used;
	__u64 sequence;
	__u64 monotonic_ns;
};

struct ax7021b_qr_counters {
	__u64 frames_completed;
	__u64 dequeue_count;
	__u64 queue_count;
	__u64 dma_errors;
	__u64 stop_count;
	__u64 reserved[3];
};

/* Raw read-only PL result bank: 16 descriptor words followed by 30 ROIs. */
struct ax7021b_qr_roi_bank {
	__u32 bank;
	__u32 words;
	__u32 data[AX7021B_QR_ROI_BANK_WORDS];
};

/* Opt-in capability: old applications remain paced. reserved[0] advertises it. */
#define AX7021B_QR_CAP_PREFETCH 1U
#define AX7021B_QR_CAP_TIMING 2U
#define AX7021B_QR_CAP_LAYOUT 4U
#define AX7021B_QR_CAP_SOURCE_TAG 8U
struct ax7021b_qr_source_tag {
 __u32 version,index;__u64 sequence;
 __u32 source_epoch,source_frame,flags,reserved;
};
#define AX7021B_QR_IOC_GET_SOURCE_TAG _IOWR('Q',0x0d,struct ax7021b_qr_source_tag)
/* Independent physical layout ABI. Guards live at gray_offset in their rows. */
struct ax7021b_qr_layout {
 __u32 version,capabilities,format,width,height,storage_height,row_stride;
 __u32 rgb_offset,rgb_bytes,gray_offset,gray_bytes,header_rows,footer_rows;
 __u32 frame_bytes,mmap_slot_bytes,reserved;
};
#define AX7021B_QR_IOC_GET_LAYOUT _IOR('Q',0x0b,struct ax7021b_qr_layout)
/* Global formatter counters, sampled read-only; not a per-frame snapshot. */
struct ax7021b_qr_layout_diagnostics {
 __u32 version,capabilities,peak_rows,format_errors,input_stall_cycles,reserved[3];
};
#define AX7021B_QR_IOC_GET_LAYOUT_DIAGNOSTICS _IOR('Q',0x0c,struct ax7021b_qr_layout_diagnostics)
/* Independent diagnostics ABI. Nanoseconds use the kernel monotonic clock. */
enum ax7021b_qr_time_stage {
 QR_TIME_ARM_START, QR_TIME_TERMINATE_DONE, QR_TIME_CONFIG_DONE,
 QR_TIME_SUBMIT_DONE, QR_TIME_ISSUE_DONE, QR_TIME_ARM_HIGH,
 QR_TIME_IRQ_ENTER, QR_TIME_DDR_VALID, QR_TIME_SNAPSHOT_DONE,
 QR_TIME_PUBLISH, QR_TIME_COUNT
};
struct ax7021b_qr_timing {
 __u32 version,index;
 __u64 sequence;
 __u32 flags,pl_words;
 __u64 ns[QR_TIME_COUNT];
 __u32 pl[32];
};
#define AX7021B_QR_IOC_GET_TIMING _IOWR('Q',0x0a,struct ax7021b_qr_timing)
struct ax7021b_qr_frame_snapshot {
 __u32 index, flags;
 __u64 sequence;
 __u32 data[AX7021B_QR_ROI_BANK_WORDS];
 __u32 diag[48]; /* coherent dynamic block, flags bit1 means available */
};
#define AX7021B_QR_IOC_SET_MODE _IOW('Q',0x08,__u32)
#define AX7021B_QR_IOC_GET_FRAME_SNAPSHOT _IOWR('Q',0x09,struct ax7021b_qr_frame_snapshot)

#define AX7021B_QR_IOC_MAGIC 'Q'
#define AX7021B_QR_IOC_GET_INFO     _IOR(AX7021B_QR_IOC_MAGIC, 0x00, struct ax7021b_qr_info)
#define AX7021B_QR_IOC_START        _IO(AX7021B_QR_IOC_MAGIC, 0x01)
#define AX7021B_QR_IOC_STOP         _IO(AX7021B_QR_IOC_MAGIC, 0x02)
#define AX7021B_QR_IOC_DEQUEUE      _IOR(AX7021B_QR_IOC_MAGIC, 0x03, struct ax7021b_qr_buffer)
#define AX7021B_QR_IOC_QUEUE        _IOW(AX7021B_QR_IOC_MAGIC, 0x04, struct ax7021b_qr_buffer)
#define AX7021B_QR_IOC_GET_COUNTERS _IOR(AX7021B_QR_IOC_MAGIC, 0x05, struct ax7021b_qr_counters)
#define AX7021B_QR_IOC_GET_ROI_BANK _IOWR(AX7021B_QR_IOC_MAGIC, 0x06, struct ax7021b_qr_roi_bank)
#define AX7021B_QR_IOC_RESET_SENSOR _IO(AX7021B_QR_IOC_MAGIC, 0x07)

#endif
