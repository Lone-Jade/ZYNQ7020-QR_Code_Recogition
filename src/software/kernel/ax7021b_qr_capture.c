// SPDX-License-Identifier: GPL-2.0-only
/* Static-bitstream Gray8 capture driver for the AX7021B QR profile. */
#include <linux/atomic.h>
#include <linux/clk.h>
#include <linux/dmaengine.h>
#include <linux/dma/xilinx_dma.h>
#include <linux/dma-mapping.h>
#include <linux/fs.h>
#include <linux/gpio/consumer.h>
#include <linux/io.h>
#include <linux/interrupt.h>
#include <linux/ktime.h>
#include <linux/delay.h>
#include <linux/miscdevice.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/poll.h>
#include <linux/slab.h>
#include <linux/uaccess.h>
#include <linux/wait.h>
#include <linux/workqueue.h>

#include "ax7021b_qr.h"

#define QR_WIDTH 1280U
#define QR_VISIBLE_HEIGHT 720U
#define QR_STORAGE_HEIGHT 722U
#define QR_PL_ABI_REGISTER 0x20U
#define QR_PL_BANK_BASE 0xA000U
#define QR_PL_BANK_STRIDE 0x0800U

#include "qr_ring_policy.h"

static bool early_rearm;
module_param(early_rearm,bool,0444);
MODULE_PARM_DESC(early_rearm,"Prepare the next FREE slot after DDR commit, concurrently with metadata caching");

struct ax7021b_qr;

struct qr_dma_buffer {
	struct ax7021b_qr *qr;
	void *cpu;
	dma_addr_t dma;
	enum qr_buffer_state state;
	u64 sequence;
	u64 monotonic_ns;
	u32 index;
	struct ax7021b_qr_frame_snapshot snapshot;
	struct ax7021b_qr_timing timing;
 struct ax7021b_qr_source_tag source_tag;
};

struct ax7021b_qr {
	struct device *dev;
	struct clk *core_clk;
	void __iomem *regs;
	void __iomem *timing_regs;
	struct dma_chan *capture;
	struct gpio_desc *reset_gpio;
	struct gpio_desc *arm_gpio;
	struct miscdevice misc;
	struct qr_dma_buffer buffers[AX7021B_QR_BUFFER_COUNT];
	spinlock_t lock;
	wait_queue_head_t wait;
	struct mutex control_lock;
	atomic_t opened;
	bool running;
	bool inflight;
	bool failed;
	bool prefetch, stopping;
	struct delayed_work prefetch_work;
	int irq;
	u32 active_index;
	u32 stride, frame_bytes, slot_bytes, gray_offset, layout_caps;
	bool color_layout,source_tags;
	u64 next_sequence;
	struct ax7021b_qr_counters counters;
};

static int qr_arm_frame(struct ax7021b_qr *qr, u32 index);

static void qr_read_timing(struct ax7021b_qr *qr, struct qr_dma_buffer *buffer)
{
 u32 generation, after; unsigned retry;
 if (!qr->timing_regs) return;
 for (retry=0; retry<8; ++retry) {
  generation=ioread32(qr->timing_regs+8);
  memcpy_fromio(buffer->timing.pl,qr->timing_regs,sizeof(buffer->timing.pl));
  after=ioread32(qr->timing_regs+8);
  if (generation==after && buffer->timing.pl[2]==generation) {
   buffer->timing.pl_words=32;buffer->timing.flags|=2;
   if(ioread32(qr->regs+0x200)==0xAC040002U){
    buffer->timing.flags|=4;buffer->timing.pl[30]=ioread32(qr->regs+0x204);
    buffer->timing.pl[31]=ioread32(qr->regs+0x208);
   }
   return;
  }
 }
}

/* All transitions use lock. A full ring pauses admission; DONE/USER storage
 * is never recycled. The worker never blocks on control_lock, so STOP can
 * cancel it synchronously while holding that mutex. */
static void qr_prefetch_work(struct work_struct *work)
{
 struct ax7021b_qr *qr=container_of(to_delayed_work(work),struct ax7021b_qr,prefetch_work);
 unsigned long flags; unsigned state[AX7021B_QR_BUFFER_COUNT],i,index;
 int ret;
 if(!mutex_trylock(&qr->control_lock)){
  if(READ_ONCE(qr->running)&&!READ_ONCE(qr->stopping))
   mod_delayed_work(system_wq,&qr->prefetch_work,msecs_to_jiffies(1));
  return;
 }
 spin_lock_irqsave(&qr->lock,flags);
 if(!qr->running||qr->stopping||qr->failed||qr->inflight)goto unlock;
 for(i=0;i<AX7021B_QR_BUFFER_COUNT;i++)state[i]=qr->buffers[i].state;
 index=qr_ring_free(state,AX7021B_QR_BUFFER_COUNT);
 if(index==AX7021B_QR_BUFFER_COUNT){qr->counters.reserved[0]++;goto unlock;}
 qr->buffers[index].state=QR_BUF_QUEUED;
 spin_unlock_irqrestore(&qr->lock,flags);
 ret=qr_arm_frame(qr,index);
 if(ret){
  spin_lock_irqsave(&qr->lock,flags);qr->failed=true;qr->counters.dma_errors++;
  spin_unlock_irqrestore(&qr->lock,flags);wake_up_interruptible(&qr->wait);
 }
 mutex_unlock(&qr->control_lock);return;
unlock:
 spin_unlock_irqrestore(&qr->lock,flags);mutex_unlock(&qr->control_lock);
}

/* Cache the exact frame bank before publishing this QUEUED slot. Normal
 * prefetch waits for this copy; early re-arm overlaps it with another FREE
 * slot. Generation and full frame/epoch/config/threshold identity are checked
 * across the read. Timeout fails closed instead of using a newer bank. */
static bool qr_cache_snapshot(struct ax7021b_qr *qr,struct qr_dma_buffer *buffer)
{
 struct ax7021b_qr_frame_snapshot *s=&buffer->snapshot;
 const u32 *h=buffer->cpu+qr->gray_offset;u64 deadline=ktime_get_ns()+60000000ULL;
 u32 b,g,*d=s->data,j;
 memset(s,0,sizeof(*s));s->index=buffer->index;s->sequence=buffer->sequence;
 do{
  for(b=0;b<AX7021B_QR_ROI_BANK_COUNT;b++){
   void __iomem *base=qr->regs+QR_PL_BANK_BASE+b*QR_PL_BANK_STRIDE;
   g=ioread32(base);if(!g||(g&1))continue;
   memcpy_fromio(d,base,sizeof(s->data));
   if(ioread32(base)!=g||d[0]!=g||d[1]!=h[2]||d[2]!=h[3]||d[3]!=h[5]||
      d[4]>30||!(d[5]&1)||(d[5]&34)||d[6]!=h[8]||d[7]!=h[9])continue;
   for(j=0;j<4;j++)if(d[10+j]!=h[12+j])break;
   if(j!=4)continue;
   s->flags=1;
   g=ioread32(qr->regs+0x128);
   if(!(g&1)){
    memcpy_fromio(s->diag,qr->regs+0x128,sizeof(s->diag));
    if(ioread32(qr->regs+0x128)==g&&s->diag[0]==g&&s->diag[1]==h[3]&&s->diag[2]==h[2])s->flags|=2;
   }
   return true;
  }
  usleep_range(100,200);
 }while(ktime_get_ns()<deadline&&!READ_ONCE(qr->stopping));
 return false;
}

static bool qr_has_done(struct ax7021b_qr *qr)
{
	unsigned long flags;
	bool ready = false;
	u32 i;

	spin_lock_irqsave(&qr->lock, flags);
	for (i = 0; i < AX7021B_QR_BUFFER_COUNT; ++i)
		ready |= qr->buffers[i].state == QR_BUF_DONE;
	spin_unlock_irqrestore(&qr->lock, flags);
	return ready;
}

static void qr_record_dma_error(struct ax7021b_qr *qr)
{
	unsigned long flags;

	spin_lock_irqsave(&qr->lock, flags);
	qr->counters.dma_errors++;
	spin_unlock_irqrestore(&qr->lock, flags);
}

static void qr_publish_buffer(void *arg)
{
	struct qr_dma_buffer *buffer = arg;
	struct ax7021b_qr *qr = buffer->qr;
	unsigned long flags;

	spin_lock_irqsave(&qr->lock, flags);
	if (!(early_rearm && qr->prefetch)) qr->inflight = false;
	if (qr->running && buffer->state == QR_BUF_QUEUED) {
		buffer->state = QR_BUF_DONE;

		buffer->timing.sequence = buffer->sequence;
		buffer->timing.ns[QR_TIME_PUBLISH] = ktime_get_ns();
		buffer->monotonic_ns = ktime_get_ns();
		qr->counters.frames_completed++;
	}
	spin_unlock_irqrestore(&qr->lock, flags);
	wake_up_interruptible(&qr->wait);
 if(qr->prefetch&&!READ_ONCE(qr->stopping))
  mod_delayed_work(system_wq,&qr->prefetch_work,0);
}

/* VDMA's frame-count IRQ waits for the following SOF in this configuration.
 * One-shot admission intentionally has no following SOF. Use the QR footer
 * IRQ, then wait for the final DDR word to commit before exposing the slot.
 * The final padding word is poisoned before DMA so stale storage cannot pass.
 */
static irqreturn_t qr_frame_irq(int irq, void *arg)
{
	struct ax7021b_qr *qr = arg;
	struct qr_dma_buffer *buffer;
	u32 *header, *footer, *tail;
	u64 deadline;
	unsigned long flags;
	bool valid = false;

	if (!(ioread32(qr->regs + 0x04) & 2U))
		return IRQ_NONE;
	iowrite32(1, qr->regs + 0x1c);
	if (!READ_ONCE(qr->running) || !READ_ONCE(qr->inflight))
		return IRQ_HANDLED;
	buffer = &qr->buffers[READ_ONCE(qr->active_index)];
	buffer->timing.ns[QR_TIME_IRQ_ENTER] = ktime_get_ns();
	header = buffer->cpu + qr->gray_offset;
	footer = buffer->cpu + qr->stride * (QR_VISIBLE_HEIGHT + 1U) + qr->gray_offset;
	tail = buffer->cpu + qr->frame_bytes - sizeof(u32);
	deadline = ktime_get_ns() + 20000000ULL;
	do {
		dma_rmb();
		valid = READ_ONCE(*tail) == 0 &&
			READ_ONCE(header[0]) == 0x32485251U &&
			READ_ONCE(footer[0]) == 0x32465251U &&
			READ_ONCE(header[3]) == (u32)buffer->sequence + 1U &&
			READ_ONCE(footer[3]) == READ_ONCE(header[3]) &&
			READ_ONCE(footer[4]) == ~READ_ONCE(header[3]);
		if (valid)
			break;
		usleep_range(50, 100);
	} while (ktime_get_ns() < deadline);
 buffer->timing.ns[QR_TIME_DDR_VALID]=ktime_get_ns();
 qr_read_timing(qr,buffer);
 // Read immutable DMA storage BEFORE scheduling re-arm, not live PL counters.
 if(valid&&qr->source_tags){
  valid=READ_ONCE(header[16])==0x34544701U && READ_ONCE(footer[16])==0x34544701U &&
   READ_ONCE(header[17])!=0 && READ_ONCE(header[17])==READ_ONCE(footer[17]) &&
   READ_ONCE(header[18])==READ_ONCE(footer[18]) &&
   READ_ONCE(header[19])==~READ_ONCE(header[18]) && READ_ONCE(footer[19])==READ_ONCE(header[19]);
  if(valid)buffer->source_tag=(struct ax7021b_qr_source_tag){.version=1,.index=buffer->index,
   .sequence=buffer->sequence,.source_epoch=READ_ONCE(header[17]),.source_frame=READ_ONCE(header[18]),.flags=1};
 }

 if(valid&&early_rearm&&qr->prefetch){
  spin_lock_irqsave(&qr->lock,flags);qr->inflight=false;spin_unlock_irqrestore(&qr->lock,flags);
  if(!READ_ONCE(qr->stopping))mod_delayed_work(system_wq,&qr->prefetch_work,0);
  wake_up_interruptible(&qr->wait);
 }
 if(valid&&qr->prefetch)valid=qr_cache_snapshot(qr,buffer);
 buffer->timing.ns[QR_TIME_SNAPSHOT_DONE]=ktime_get_ns();
	if (valid) {
		qr_publish_buffer(buffer);
	} else if (!READ_ONCE(qr->stopping)) {
		spin_lock_irqsave(&qr->lock, flags);
		qr->failed = true;
		qr->inflight = false;
		qr->counters.dma_errors++;
		spin_unlock_irqrestore(&qr->lock, flags);
		wake_up_interruptible(&qr->wait);
	}
	return IRQ_HANDLED;
}

static int qr_submit_buffer(struct ax7021b_qr *qr, struct qr_dma_buffer *buffer)
{
	struct dma_interleaved_template *xt;
	struct dma_async_tx_descriptor *desc;
	dma_cookie_t cookie;

	xt = kzalloc(struct_size(xt, sgl, 1), GFP_KERNEL);
	if (!xt)
		return -ENOMEM;
	xt->dir = DMA_DEV_TO_MEM;
	xt->dst_start = buffer->dma;
	xt->dst_inc = true;
	xt->dst_sgl = true;
	xt->numf = QR_STORAGE_HEIGHT;
	xt->frame_size = 1;
	xt->sgl[0].size = qr->stride;
	xt->sgl[0].icg = 0;

	desc = dmaengine_prep_interleaved_dma(qr->capture, xt,
					       DMA_PREP_INTERRUPT | DMA_CTRL_ACK);
	kfree(xt);
	if (!desc)
		return -EIO;
	/* Completion comes from the QR footer IRQ plus DDR-commit validation. */
	cookie = dmaengine_submit(desc);
	return dma_submit_error(cookie);
}

static void qr_stop_locked(struct ax7021b_qr *qr)
{
	unsigned long flags;
	u32 i;

	if (!qr->running)
		return;
 WRITE_ONCE(qr->stopping,true);
 cancel_delayed_work_sync(&qr->prefetch_work);
	gpiod_set_value_cansleep(qr->arm_gpio, 0);
	/* An armed descriptor is not necessarily an admitted camera frame. Once
	 * the low level crosses the gate, WAIT_SOF means it was cancelled before
	 * admission; there will be no footer IRQ to wait for. */
	usleep_range(1000, 2000);
	if (!(ioread32(qr->regs + 0x04) & 1U))
		WRITE_ONCE(qr->inflight, false);
	/* Finish an already admitted frame before disabling the QR consumer.
	 * Otherwise the DVP gate can remain FORWARD across STOP/START and the
	 * next session starts with a truncated frame. Never wait indefinitely. */
	if (!wait_event_timeout(qr->wait, !READ_ONCE(qr->inflight),
				msecs_to_jiffies(150)))
		qr_record_dma_error(qr);
	iowrite32(0, qr->regs);
	synchronize_irq(qr->irq);
	dmaengine_terminate_sync(qr->capture);
	spin_lock_irqsave(&qr->lock, flags);
	qr->running = false;
	qr->inflight = false;
	for (i = 0; i < AX7021B_QR_BUFFER_COUNT; ++i)
		qr->buffers[i].state = QR_BUF_FREE;
	qr->counters.stop_count++;
	spin_unlock_irqrestore(&qr->lock, flags);
	wake_up_interruptible(&qr->wait);
}

/* Prepare one reserved slot and admit one complete frame with an arm edge.
 * Paced users serialize requests; prefetch selects FREE slots independently.
 * Reset only DMA, preserving the QR core Otsu history. DONE/USER slots cannot
 * reach this function through the ring policy. */
static int qr_arm_frame(struct ax7021b_qr *qr, u32 index)
{
	struct xilinx_vdma_config config = {
		.park = 1, .frm_cnt_en = 0, .coalesc = 1,
	};
	int ret;
	bool first = !qr->next_sequence;

	memset(&qr->buffers[index].timing,0,sizeof(qr->buffers[index].timing));
	qr->buffers[index].timing.version=1;
	qr->buffers[index].timing.index=index;
	qr->buffers[index].timing.flags=1;
	qr->buffers[index].timing.ns[QR_TIME_ARM_START]=ktime_get_ns();
	gpiod_set_value_cansleep(qr->arm_gpio, 0);
	/* Allow the low level to cross the camera-clock synchronizer. */
	usleep_range(50, 100);
	dmaengine_terminate_sync(qr->capture);
	qr->buffers[index].timing.ns[QR_TIME_TERMINATE_DONE]=ktime_get_ns();
	/* One completed descriptor owns one stable frame. Circular defaults
	 * otherwise overwrite a dequeued slot before userspace can inspect it. */
	ret = xilinx_vdma_channel_set_config(qr->capture, &config);
	if (ret)
		return ret;
	if (first) {
		/* Configure once per session; register writes invalidate Otsu history. */
		iowrite32(0x02, qr->regs + 0x00);
		iowrite32(QR_WIDTH, qr->regs + 0x08);
		iowrite32(QR_VISIBLE_HEIGHT, qr->regs + 0x0c);
		iowrite32(200, qr->regs + 0x10);
		iowrite32(1, qr->regs + 0x18);
		iowrite32(2, qr->regs + 0x2c);
		iowrite32(96, qr->regs + 0x30);
		iowrite32(128, qr->regs + 0x34);
		/* Otsu enabled, Gray8 image transport retained. */
		iowrite32(1, qr->regs + 0x40);
		iowrite32((u32)ktime_get_ns() | 1U, qr->regs + 0x44);
		iowrite32(1, qr->regs + 0x48);
		iowrite32(0, qr->regs + 0x4c);
		iowrite32(0, qr->regs + 0x50);
		iowrite32(QR_WIDTH, qr->regs + 0x54);
		iowrite32(QR_VISIBLE_HEIGHT, qr->regs + 0x58);
	}

	memset(qr->buffers[index].cpu + qr->gray_offset, 0, 64);
	memset(qr->buffers[index].cpu + qr->stride * (QR_VISIBLE_HEIGHT + 1U) + qr->gray_offset, 0, 64);
	memset(qr->buffers[index].cpu + qr->frame_bytes - sizeof(u32), 0xa5, sizeof(u32));
	dma_wmb();
	WRITE_ONCE(qr->active_index, index);
	qr->buffers[index].timing.ns[QR_TIME_CONFIG_DONE]=ktime_get_ns();
	ret = qr_submit_buffer(qr, &qr->buffers[index]);
	if (ret)
		return ret;
	qr->buffers[index].sequence=qr->next_sequence++;
	WRITE_ONCE(qr->inflight, true);
	qr->buffers[index].timing.ns[QR_TIME_SUBMIT_DONE]=ktime_get_ns();
	dma_async_issue_pending(qr->capture);
	qr->buffers[index].timing.ns[QR_TIME_ISSUE_DONE]=ktime_get_ns();
	if (first)
		iowrite32(0x11, qr->regs);
	gpiod_set_value_cansleep(qr->arm_gpio, 1);
	qr->buffers[index].timing.ns[QR_TIME_ARM_HIGH]=ktime_get_ns();
	return 0;
}

static int qr_start_locked(struct ax7021b_qr *qr)
{
	unsigned long flags;
	u32 i;
	int ret;

	if (qr->running)
		return -EBUSY;
	spin_lock_irqsave(&qr->lock, flags);
	qr->next_sequence = 0;
	qr->failed = false;
	qr->stopping = false;
	for (i = 0; i < AX7021B_QR_BUFFER_COUNT; ++i)
		qr->buffers[i].state = qr->prefetch ? QR_BUF_FREE : QR_BUF_QUEUED;
	qr->running = true;
	spin_unlock_irqrestore(&qr->lock, flags);
	qr->buffers[0].state = QR_BUF_QUEUED;
	ret = qr_arm_frame(qr, 0);
	if (ret) {
		qr_record_dma_error(qr);
		qr_stop_locked(qr);
	}
	return ret;
}

static int qr_open(struct inode *inode, struct file *file)
{
	struct miscdevice *misc = file->private_data;
	struct ax7021b_qr *qr = container_of(misc, struct ax7021b_qr, misc);

	if (atomic_cmpxchg(&qr->opened, 0, 1))
		return -EBUSY;
	qr->prefetch = false; /* Every new owner starts with legacy paced semantics. */
	file->private_data = qr;
	return nonseekable_open(inode, file);
}

static int qr_release(struct inode *inode, struct file *file)
{
	struct ax7021b_qr *qr = file->private_data;

	mutex_lock(&qr->control_lock);
	qr_stop_locked(qr);
	mutex_unlock(&qr->control_lock);
	atomic_set(&qr->opened, 0);
	return 0;
}

static long qr_ioctl(struct file *file, unsigned int cmd, unsigned long arg)
{
	struct ax7021b_qr *qr = file->private_data;
	void __user *user = (void __user *)arg;
	struct ax7021b_qr_buffer request;
	struct ax7021b_qr_counters counters;
	struct ax7021b_qr_roi_bank *bank;
	struct ax7021b_qr_frame_snapshot *snapshot;
	struct ax7021b_qr_timing timing;
	u32 mode;
	struct ax7021b_qr_info info = {
		.abi_version = qr->color_layout ? AX7021B_QR_COLOR_ABI_VERSION : AX7021B_QR_ABI_VERSION,
		.pl_abi_version = AX7021B_QR_PL_ABI_VERSION,
		.width = QR_WIDTH,
		.visible_height = QR_VISIBLE_HEIGHT,
		.storage_height = QR_STORAGE_HEIGHT,
		.stride = qr->stride,
		.buffer_count = AX7021B_QR_BUFFER_COUNT,
		.frame_bytes = qr->frame_bytes,
		.mmap_slot_bytes = qr->slot_bytes,
		.reserved = {AX7021B_QR_CAP_PREFETCH|AX7021B_QR_CAP_TIMING|AX7021B_QR_CAP_LAYOUT|(qr->source_tags?AX7021B_QR_CAP_SOURCE_TAG:0), READ_ONCE(qr->prefetch)},
	};
	unsigned long flags;
	u64 sequence;
	u32 i, selected;
	int ret = 0;

	switch (cmd) {
 case AX7021B_QR_IOC_GET_SOURCE_TAG: {
  struct ax7021b_qr_source_tag t;
  if(!qr->source_tags)return -EOPNOTSUPP;
  if(copy_from_user(&t,user,sizeof(t)))return -EFAULT;
  if(t.version!=1||t.flags||t.reserved)return -EINVAL;
  spin_lock_irqsave(&qr->lock,flags);i=t.index;
  if(i>=AX7021B_QR_BUFFER_COUNT||!qr_ring_release_valid(qr->buffers[i].state,qr->buffers[i].sequence,t.sequence))ret=-ESTALE;
  else t=qr->buffers[i].source_tag;
  spin_unlock_irqrestore(&qr->lock,flags);
  if(!ret&&copy_to_user(user,&t,sizeof(t)))ret=-EFAULT;
  return ret;
 }

 case AX7021B_QR_IOC_GET_LAYOUT_DIAGNOSTICS: {
  struct ax7021b_qr_layout_diagnostics d={.version=1,.capabilities=qr->layout_caps};
  if(!qr->layout_caps)return -EOPNOTSUPP;
  d.peak_rows=ioread32(qr->regs+0x228);
  d.format_errors=ioread32(qr->regs+0x22c);
  d.input_stall_cycles=ioread32(qr->regs+0x230);
  return copy_to_user(user,&d,sizeof(d)) ? -EFAULT : 0;
 }
 case AX7021B_QR_IOC_GET_LAYOUT: {
  struct ax7021b_qr_layout layout={.version=AX7021B_QR_LAYOUT_ABI,
   .capabilities=qr->layout_caps,.format=qr->color_layout ? AX7021B_QR_LAYOUT_RGB565_GRAY8_ROWS : AX7021B_QR_LAYOUT_GRAY8,
   .width=QR_WIDTH,.height=QR_VISIBLE_HEIGHT,.storage_height=QR_STORAGE_HEIGHT,
   .row_stride=qr->stride,.rgb_offset=0,.rgb_bytes=qr->color_layout ? QR_WIDTH*2 : 0,
   .gray_offset=qr->gray_offset,.gray_bytes=QR_WIDTH,.header_rows=1,.footer_rows=1,
   .frame_bytes=qr->frame_bytes,.mmap_slot_bytes=qr->slot_bytes};
  return copy_to_user(user,&layout,sizeof(layout)) ? -EFAULT : 0;
 }
 case AX7021B_QR_IOC_GET_TIMING:
  if(copy_from_user(&timing,user,sizeof(timing)))return -EFAULT;
  spin_lock_irqsave(&qr->lock,flags);
  i=timing.index;
  if(i>=AX7021B_QR_BUFFER_COUNT||!qr_ring_release_valid(qr->buffers[i].state,qr->buffers[i].sequence,timing.sequence))ret=-ESTALE;
  else timing=qr->buffers[i].timing;
  spin_unlock_irqrestore(&qr->lock,flags);
  if(!ret&&copy_to_user(user,&timing,sizeof(timing)))ret=-EFAULT;
  return ret;
 case AX7021B_QR_IOC_SET_MODE:
  if(copy_from_user(&mode,user,sizeof(mode)))return -EFAULT;
  if(mode>1)return -EINVAL;
  mutex_lock(&qr->control_lock);
  if(qr->running)ret=-EBUSY;else qr->prefetch=mode;
  mutex_unlock(&qr->control_lock);return ret;
 case AX7021B_QR_IOC_GET_FRAME_SNAPSHOT:
  snapshot=memdup_user(user,sizeof(*snapshot));if(IS_ERR(snapshot))return PTR_ERR(snapshot);
  spin_lock_irqsave(&qr->lock,flags);
  i=snapshot->index;
  if(!qr->prefetch||i>=AX7021B_QR_BUFFER_COUNT||
    !qr_ring_release_valid(qr->buffers[i].state,qr->buffers[i].sequence,snapshot->sequence)||
    !(qr->buffers[i].snapshot.flags&1))ret=-ESTALE;
  else *snapshot=qr->buffers[i].snapshot;
  spin_unlock_irqrestore(&qr->lock,flags);
  if(!ret&&copy_to_user(user,snapshot,sizeof(*snapshot)))ret=-EFAULT;
  kfree(snapshot);return ret;
	case AX7021B_QR_IOC_RESET_SENSOR:
		mutex_lock(&qr->control_lock);
		if (qr->running) {
			ret = -EBUSY;
		} else {
			gpiod_set_value_cansleep(qr->arm_gpio, 0);
			gpiod_set_value_cansleep(qr->reset_gpio, 1);
			msleep(5);
			gpiod_set_value_cansleep(qr->reset_gpio, 0);
			msleep(20);
		}
		mutex_unlock(&qr->control_lock);
		return ret;
	case AX7021B_QR_IOC_GET_INFO:
		return copy_to_user(user, &info, sizeof(info)) ? -EFAULT : 0;
	case AX7021B_QR_IOC_GET_COUNTERS:
		spin_lock_irqsave(&qr->lock, flags);
		counters = qr->counters;
		spin_unlock_irqrestore(&qr->lock, flags);
		return copy_to_user(user, &counters, sizeof(counters)) ? -EFAULT : 0;
	case AX7021B_QR_IOC_GET_ROI_BANK:
		bank = memdup_user(user, sizeof(*bank));
		if (IS_ERR(bank))
			return PTR_ERR(bank);
		if (bank->bank >= AX7021B_QR_ROI_BANK_COUNT) {
			kfree(bank);
			return -EINVAL;
		}
		bank->words = AX7021B_QR_ROI_BANK_WORDS;
		memcpy_fromio(bank->data,
			      qr->regs + QR_PL_BANK_BASE + bank->bank * QR_PL_BANK_STRIDE,
			      sizeof(bank->data));
		ret = copy_to_user(user, bank, sizeof(*bank)) ? -EFAULT : 0;
		kfree(bank);
		return ret;
	case AX7021B_QR_IOC_START:
		mutex_lock(&qr->control_lock);
		ret = qr_start_locked(qr);
		mutex_unlock(&qr->control_lock);
		return ret;
	case AX7021B_QR_IOC_STOP:
		mutex_lock(&qr->control_lock);
		qr_stop_locked(qr);
		mutex_unlock(&qr->control_lock);
		return 0;
	case AX7021B_QR_IOC_DEQUEUE:
		if (!qr->running)
			return -EPIPE;
		if ((file->f_flags & O_NONBLOCK) && !qr_has_done(qr))
			return -EAGAIN;
		ret = wait_event_interruptible(qr->wait, qr_has_done(qr) || !qr->running || qr->failed);
		if (ret)
			return ret;
		if (!qr->running)
			return -EPIPE;
		if (qr->failed)
			return -EIO;
		selected = AX7021B_QR_BUFFER_COUNT;
		sequence = U64_MAX;
		spin_lock_irqsave(&qr->lock, flags);
		for (i = 0; i < AX7021B_QR_BUFFER_COUNT; ++i) {
			if (qr->buffers[i].state == QR_BUF_DONE &&
			    qr->buffers[i].sequence < sequence) {
				selected = i;
				sequence = qr->buffers[i].sequence;
			}
		}
		if (selected < AX7021B_QR_BUFFER_COUNT) {
			qr->buffers[selected].state = QR_BUF_USER;
			qr->counters.dequeue_count++;
			request.index = selected;
			request.bytes_used = qr->frame_bytes;
			request.sequence = qr->buffers[selected].sequence;
			request.monotonic_ns = qr->buffers[selected].monotonic_ns;
		}
		spin_unlock_irqrestore(&qr->lock, flags);
		if (selected == AX7021B_QR_BUFFER_COUNT)
			return -EAGAIN;
		if (copy_to_user(user, &request, sizeof(request))) {
			spin_lock_irqsave(&qr->lock, flags);
			if (qr->buffers[selected].state == QR_BUF_USER) {
				qr->buffers[selected].state = QR_BUF_DONE;
				qr->counters.dequeue_count--;
			}
			spin_unlock_irqrestore(&qr->lock, flags);
			return -EFAULT;
		}
		return 0;
	case AX7021B_QR_IOC_QUEUE:
		if (copy_from_user(&request, user, sizeof(request)))
			return -EFAULT;
		if (request.index >= AX7021B_QR_BUFFER_COUNT)
			return -EINVAL;
		mutex_lock(&qr->control_lock);
		if (!qr->running) {
			ret = -EPIPE;
			goto queue_unlock;
		}
		spin_lock_irqsave(&qr->lock, flags);
		if (qr->buffers[request.index].state != QR_BUF_USER ||
                    (qr->prefetch && qr->buffers[request.index].sequence != request.sequence)) {
			spin_unlock_irqrestore(&qr->lock, flags);
			ret = -EINVAL;
			goto queue_unlock;
		}
		qr->buffers[request.index].state = qr->prefetch ? QR_BUF_FREE : QR_BUF_QUEUED;
		spin_unlock_irqrestore(&qr->lock, flags);
  if(qr->prefetch){
   mod_delayed_work(system_wq,&qr->prefetch_work,0);
   spin_lock_irqsave(&qr->lock,flags);qr->counters.queue_count++;
   spin_unlock_irqrestore(&qr->lock,flags);goto queue_unlock;
  }
		ret = qr_arm_frame(qr, (request.index + 1U) % AX7021B_QR_BUFFER_COUNT);
		if (ret) {
			qr_record_dma_error(qr);
			qr_stop_locked(qr);
			goto queue_unlock;
		}
		spin_lock_irqsave(&qr->lock, flags);
		qr->counters.queue_count++;
		spin_unlock_irqrestore(&qr->lock, flags);
queue_unlock:
		mutex_unlock(&qr->control_lock);
		return ret;
	default:
		return -ENOTTY;
	}
}

static __poll_t qr_poll(struct file *file, poll_table *wait)
{
	struct ax7021b_qr *qr = file->private_data;
	__poll_t mask = 0;

	poll_wait(file, &qr->wait, wait);
	if (qr_has_done(qr))
		mask |= EPOLLIN | EPOLLRDNORM;
	if (!qr->running)
		mask |= EPOLLHUP;
	if (READ_ONCE(qr->failed))
		mask |= EPOLLERR;
	return mask;
}

static int qr_mmap(struct file *file, struct vm_area_struct *vma)
{
	struct ax7021b_qr *qr = file->private_data;
	unsigned long slot_bytes = qr->slot_bytes;
	unsigned long requested = vma->vm_end - vma->vm_start;
	unsigned long offset = vma->vm_pgoff << PAGE_SHIFT;
	u32 index = offset / slot_bytes;

	if ((vma->vm_flags & VM_WRITE) || requested > slot_bytes ||
	    offset % slot_bytes || index >= AX7021B_QR_BUFFER_COUNT)
		return -EINVAL;
	vm_flags_clear(vma, VM_MAYWRITE);
	vma->vm_pgoff = 0;
	return dma_mmap_coherent(qr->capture->device->dev, vma,
				 qr->buffers[index].cpu, qr->buffers[index].dma,
				 slot_bytes);
}

static const struct file_operations qr_fops = {
	.owner = THIS_MODULE,
	.open = qr_open,
	.release = qr_release,
	.unlocked_ioctl = qr_ioctl,
#ifdef CONFIG_COMPAT
	.compat_ioctl = qr_ioctl,
#endif
	.poll = qr_poll,
	.mmap = qr_mmap,
	.llseek = noop_llseek,
};

static int ax7021b_qr_probe(struct platform_device *pdev)
{
	struct ax7021b_qr *qr;
	u32 pl_abi;
	u32 i;
	int ret;

	qr = devm_kzalloc(&pdev->dev, sizeof(*qr), GFP_KERNEL);
	if (!qr)
		return -ENOMEM;
	qr->dev = &pdev->dev;
	/*
	 * FCLK1 is not a critical clock.  The common-clock framework disables it
	 * before rootfs modules are loaded unless this driver claims and enables
	 * the DT clock first.  Accessing the QR AXI slave while FCLK1 is gated
	 * leaves the GP0 transaction waiting forever and stalls systemd-modules-load.
	 */
	qr->core_clk = devm_clk_get_enabled(&pdev->dev, "s_axi_aclk");
	if (IS_ERR(qr->core_clk))
		return dev_err_probe(&pdev->dev, PTR_ERR(qr->core_clk),
				     "QR AXI clock unavailable\n");
	qr->regs = devm_platform_ioremap_resource(pdev, 0);
	if (IS_ERR(qr->regs))
		return PTR_ERR(qr->regs);
	if (platform_get_resource(pdev, IORESOURCE_MEM, 1)) {
		qr->timing_regs=devm_platform_ioremap_resource(pdev,1);
		if (IS_ERR(qr->timing_regs)) return PTR_ERR(qr->timing_regs);
		if (ioread32(qr->timing_regs)!=0xAC040001U ||
		    ioread32(qr->timing_regs+4)!=1) return -ENODEV;
	}
	qr->source_tags=of_device_is_compatible(pdev->dev.of_node,"xiwei,c04-qr-capture-r4");
 if(qr->source_tags&&ioread32(qr->regs+0x234)!=0xAC040401U)return -ENODEV;
 pl_abi = ioread32(qr->regs + QR_PL_ABI_REGISTER);
	if (pl_abi != AX7021B_QR_PL_ABI_VERSION)
		return dev_err_probe(&pdev->dev, -ENODEV,
			"PL ABI mismatch: got %#08x expected %#08x\n",
			pl_abi, AX7021B_QR_PL_ABI_VERSION);

	if (ioread32(qr->regs + 0x80) != AX7021B_QR_DIAG45_CAPABILITY)
		return dev_err_probe(&pdev->dev, -ENODEV, "diag45 capability mismatch\n");

 /* Old Gray8 firmware has no layout block. New color DT must never bind
  * silently to it, and old applications reject COLOR_ABI before START. */
 qr->stride=QR_WIDTH;qr->gray_offset=0;
 if(ioread32(qr->regs+0x210)==0x00010000U){
  u32 format=ioread32(qr->regs+0x218);
  qr->layout_caps=ioread32(qr->regs+0x214);
  if(format>1)return -ENODEV;
  qr->color_layout=format==1;
  qr->stride=ioread32(qr->regs+0x21c);
  qr->gray_offset=ioread32(qr->regs+0x224);
  if(qr->stride!=QR_WIDTH*(qr->color_layout?3U:1U)||
     qr->gray_offset!=(qr->color_layout?QR_WIDTH*2U:0U)||
     ioread32(qr->regs+0x220)!=0)return -ENODEV;
 }
 if(of_device_is_compatible(pdev->dev.of_node,"xiwei,c04-qr-capture-r3") &&
    (!qr->color_layout || !(qr->layout_caps&2)))return -ENODEV;
 qr->frame_bytes=qr->stride*QR_STORAGE_HEIGHT;
 qr->slot_bytes=PAGE_ALIGN(qr->frame_bytes);

	qr->capture = dma_request_chan(&pdev->dev, "capture");
	if (IS_ERR(qr->capture))
		return dev_err_probe(&pdev->dev, PTR_ERR(qr->capture),
				     "capture DMA channel unavailable\n");
	qr->reset_gpio = devm_gpiod_get(&pdev->dev, "reset", GPIOD_OUT_LOW);
	if (IS_ERR(qr->reset_gpio)) {
		ret = dev_err_probe(&pdev->dev, PTR_ERR(qr->reset_gpio),
				    "camera reset GPIO unavailable\n");
		goto release_dma;
	}
	qr->arm_gpio = devm_gpiod_get(&pdev->dev, "arm", GPIOD_OUT_LOW);
	if (IS_ERR(qr->arm_gpio)) {
		ret = dev_err_probe(&pdev->dev, PTR_ERR(qr->arm_gpio),
				    "capture arm GPIO unavailable\n");
		goto release_dma;
	}

	spin_lock_init(&qr->lock);
	mutex_init(&qr->control_lock);
	INIT_DELAYED_WORK(&qr->prefetch_work,qr_prefetch_work);
	init_waitqueue_head(&qr->wait);
	atomic_set(&qr->opened, 0);
	for (i = 0; i < AX7021B_QR_BUFFER_COUNT; ++i) {
		qr->buffers[i].qr = qr;
		qr->buffers[i].index = i;
		qr->buffers[i].cpu = dma_alloc_coherent(qr->capture->device->dev,
			qr->slot_bytes, &qr->buffers[i].dma, GFP_KERNEL);
		if (!qr->buffers[i].cpu) {
			ret = -ENOMEM;
			goto free_buffers;
		}
	}

	/* Assert then release the active-low sensor reset; capture remains gated. */
	gpiod_set_value_cansleep(qr->reset_gpio, 1);
	msleep(2);
	gpiod_set_value_cansleep(qr->reset_gpio, 0);
	msleep(20);
	iowrite32(0, qr->regs);
	iowrite32(1, qr->regs + 0x1c);
	qr->irq = platform_get_irq(pdev, 0);
	if (qr->irq < 0) {
		ret = qr->irq;
		goto free_buffers;
	}
	ret = devm_request_threaded_irq(&pdev->dev, qr->irq, NULL, qr_frame_irq,
					IRQF_ONESHOT, dev_name(&pdev->dev), qr);
	if (ret)
		goto free_buffers;

	qr->misc.minor = MISC_DYNAMIC_MINOR;
	qr->misc.name = AX7021B_QR_DEVICE_NAME;
	qr->misc.fops = &qr_fops;
	qr->misc.parent = &pdev->dev;
	ret = misc_register(&qr->misc);
	if (ret)
		goto free_buffers;
	platform_set_drvdata(pdev, qr);
	dev_info(&pdev->dev,
		 "%s %ux%u+2 capture ready, PL ABI %#08x, AXI clock %lu Hz\n",
         qr->color_layout ? "RGB565+Gray8" : "Gray8", QR_WIDTH, QR_VISIBLE_HEIGHT, pl_abi,
		 clk_get_rate(qr->core_clk));
	return 0;

free_buffers:
	while (i--)
		dma_free_coherent(qr->capture->device->dev, qr->slot_bytes,
				  qr->buffers[i].cpu, qr->buffers[i].dma);
release_dma:
	dma_release_channel(qr->capture);
	return ret;
}

static void ax7021b_qr_remove(struct platform_device *pdev)
{
	struct ax7021b_qr *qr = platform_get_drvdata(pdev);
	u32 i;

	misc_deregister(&qr->misc);
	mutex_lock(&qr->control_lock);
	qr_stop_locked(qr);
	mutex_unlock(&qr->control_lock);
	for (i = 0; i < AX7021B_QR_BUFFER_COUNT; ++i)
		dma_free_coherent(qr->capture->device->dev, qr->slot_bytes,
				  qr->buffers[i].cpu, qr->buffers[i].dma);
	dma_release_channel(qr->capture);
}

static const struct of_device_id ax7021b_qr_of_match[] = {
 {.compatible = "xiwei,c04-qr-capture-r4"},
 {.compatible = "xiwei,c04-qr-capture-r3"},
	{ .compatible = "alinx,ax7021b-qr-capture" },
	{ }
};
MODULE_DEVICE_TABLE(of, ax7021b_qr_of_match);

static struct platform_driver ax7021b_qr_driver = {
	.probe = ax7021b_qr_probe,
	.remove_new = ax7021b_qr_remove,
	.driver = {
		.name = "ax7021b-qr-capture",
		.of_match_table = ax7021b_qr_of_match,
	},
};
module_platform_driver(ax7021b_qr_driver);

MODULE_AUTHOR("Linux-PYNQ QR integration");
MODULE_DESCRIPTION("AX7021B static QR Gray8 capture driver");
MODULE_LICENSE("GPL");
