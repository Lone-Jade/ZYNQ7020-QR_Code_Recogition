// SPDX-License-Identifier: GPL-2.0-only
/* R4 exclusive camera display owner: VDMA, coherent triple buffers, PL OSD,
 * SIL9134. No fbdev, mmap, userspace physical addresses or generic DMA channel.
 * Closing an OSD client does not stop video. Only explicit STOP stops display. */
#include <linux/clk.h>
#include <linux/delay.h>
#include <linux/dma-mapping.h>
#include <linux/fs.h>
#include <linux/gpio/consumer.h>
#include <linux/i2c.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/iopoll.h>
#include <linux/miscdevice.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/random.h>
#include <linux/uaccess.h>
#include <linux/workqueue.h>
#include "ax7021b_display.h"

#define FRAME_BYTES (1280U*720U*2U)
#define RUN BIT(0)
#define CIRC BIT(1)
#define RESET BIT(2)
#define GENLOCK BIT(3)
#define INTERNAL BIT(7)
#define FRAME_IRQ BIT(12)
#define ERR_IRQ BIT(14)
#define ERRORS 0x8ff0U
#define IRQ_BITS 0x7000U
#define R4_MAGIC 0x52344401U

struct r4_display {
 struct device *dev;
 void __iomem *vdma,*osd;
 struct clk *clock;
 struct gpio_desc *reset;
 struct i2c_client *hdmi,*ddc;
 struct miscdevice misc;
 struct mutex lock;
 struct delayed_work health;
 void *cpu[3];dma_addr_t dma[3];
 bool running,read_started,quarantine,removing,ready;
 int irqs[2];
 u32 epoch,requested;
 atomic64_t read_irqs,write_irqs,dma_errors;
 u64 recoveries,submissions;
};
static inline void wr(struct r4_display *d,u32 off,u32 val){writel(val,d->vdma+off);}
static inline void ow(struct r4_display *d,u32 off,u32 val){writel(val,d->osd+off);}
static inline u32 rd(struct r4_display *d,u32 off){return readl(d->vdma+off);}
static inline u32 ore(struct r4_display *d,u32 off){return readl(d->osd+off);}

/* Core reset is waited to completion after RUN=0. A timeout is NOT permission
 * to free DMA storage. The coherent allocations remain quarantined to reboot. */
static int drain(struct r4_display *d)
{
 u32 value;int i,ret;
 ow(d,0x10,4); /* capture off, video black, transparent OSD bank retained */
 for(i=0;i<2;i++)wr(d,i?0x30:0,0);
 for(i=0;i<2;i++){
  u32 off=i?0x30:0;
  ret=readl_poll_timeout(d->vdma+off+4,value,value&1,20,100000);
  if(ret)goto unsafe;
  wr(d,off,RESET);
  ret=readl_poll_timeout(d->vdma+off,value,!(value&RESET),20,100000);
  if(ret)goto unsafe;
  if(!(rd(d,off+4)&1)){ret=-EIO;goto unsafe;}
 }
 d->read_started=false;return 0;
unsafe:
 d->quarantine=true;d->running=false;
 dev_err(d->dev,"DMA did not drain: quarantining all three allocations until reboot\n");
 return ret;
}
static void addresses(struct r4_display *d,u32 offset)
{
 unsigned i;
 for(i=0;i<3;i++)wr(d,offset+4*i,lower_32_bits(d->dma[i]));
}
static int start_locked(struct r4_display *d)
{
 unsigned i;int ret;u32 old_epoch=d->epoch;
 if(d->quarantine)return -EIO;
 if(d->running)return 0;
 ret=drain(d);if(ret)return ret;
 /* Preview-service restart may reinitialize the sensor and reset the fork's
  * frame counter. Every new DMA lifetime therefore gets a distinct epoch. */
 do get_random_bytes(&d->epoch,sizeof(d->epoch));while(!d->epoch||d->epoch==old_epoch);
 for(i=0;i<3;i++)ow(d,0x50+4*i,lower_32_bits(d->dma[i]));
 ow(d,0x14,d->epoch);ow(d,0x18,1); /* edge clears guard; epoch only while stopped */
 wr(d,4,IRQ_BITS|ERRORS);wr(d,0x34,IRQ_BITS|ERRORS);
 addresses(d,0xac);wr(d,0xa8,2560);wr(d,0xa4,2560);
 /* Dynamic master, internal Genlock. Frame-count interrupt every frame.
  * Bit15=0: retry errored store instead of advancing. Fatal faults blank in PL
  * and are recovered before another source SOF can be admitted. */
 wr(d,0x30,RUN|CIRC|GENLOCK|INTERNAL|FRAME_IRQ|ERR_IRQ|BIT(16));
 wr(d,0xa0,720); /* VSIZE last starts the write channel */
 /* Drain the GP write, wait until RUN is active, and allow the VDMA's
  * frame parameters to cross its internal clock domains before first SOF.
  * The actual vendor simulation rejects an immediate SOF at cold startup. */
 {u32 value;ret=readl_poll_timeout(d->vdma+0x34,value,!(value&1),1,100000);
  if(ret){drain(d);return ret;}}
 udelay(20);
 d->running=true;d->read_started=false;
 ow(d,0x10,5); /* camera admission, OSD; video remains black until full DDR frame */
 return 0;
}
static void start_reader(struct r4_display *d)
{
 addresses(d,0x5c);wr(d,0x58,2560);wr(d,0x54,2560);
 wr(d,0,RUN|CIRC|GENLOCK|INTERNAL|FRAME_IRQ|ERR_IRQ|BIT(16));
 wr(d,0x50,720);d->read_started=true;ow(d,0x10,7);
}
static irqreturn_t display_irq(int irq,void *arg)
{
 struct r4_display *d=arg;u32 r=rd(d,4),w=rd(d,0x34);
 if(!((r|w)&IRQ_BITS))return IRQ_NONE;
 if(r&IRQ_BITS){wr(d,4,r&IRQ_BITS);if(r&FRAME_IRQ)atomic64_inc(&d->read_irqs);}
 if(w&IRQ_BITS){wr(d,0x34,w&IRQ_BITS);if(w&FRAME_IRQ)atomic64_inc(&d->write_irqs);}
 if((r|w)&(ERRORS|ERR_IRQ))atomic64_inc(&d->dma_errors);
 if(READ_ONCE(d->ready)&&!READ_ONCE(d->removing))mod_delayed_work(system_wq,&d->health,0);
 return IRQ_HANDLED;
}
static void health(struct work_struct *work)
{
 struct r4_display *d=container_of(to_delayed_work(work),struct r4_display,health);
 mutex_lock(&d->lock);
 if(!d->removing&&d->running){
  if((ore(d,0x28)&6)||((rd(d,4)|rd(d,0x34))&ERRORS)){
   atomic64_inc(&d->dma_errors);d->recoveries++;
   if(!drain(d)){
    d->running=false;
    if(d->recoveries<=3)start_locked(d);
   }
  } else if(!d->read_started && ore(d,0x4c))start_reader(d);
 }
 if(!d->removing)mod_delayed_work(system_wq,&d->health,msecs_to_jiffies(20));
 mutex_unlock(&d->lock);
}
static int display_open(struct inode *inode,struct file *file)
{
 struct r4_display *d=container_of(file->private_data,struct r4_display,misc);
 file->private_data=d;return nonseekable_open(inode,file);
}
static long display_ioctl(struct file *file,unsigned int cmd,unsigned long arg)
{
 struct r4_display *d=file->private_data;void __user *u=(void __user *)arg;
 struct ax7021b_display_text text;
 struct ax7021b_display_scene scene;
 struct ax7021b_display_info info={.version=2,.capabilities=11,.width=1280,.height=720,
  .stride=2560,.slots=3,.columns=32,.rows=4,.cell_width=12,.cell_height=16,.color565=0x07e0,.text_bytes=128};
 struct ax7021b_display_status s={.version=2};
 int ret=0;unsigned i;u32 tag1,tag2,frame;
 if(cmd==AX7021B_DISPLAY_GET_INFO)return copy_to_user(u,&info,sizeof(info))?-EFAULT:0;
 if(cmd==AX7021B_DISPLAY_SUBMIT){
  if(copy_from_user(&text,u,sizeof(text)))return -EFAULT;
  if(text.version!=2||!text.sequence||text.flags||text.reserved)return -EINVAL;
  for(i=0;i<128;i++)if(text.text[i]<32||text.text[i]>126)return -EINVAL;
 }
 if(cmd==AX7021B_DISPLAY_SUBMIT_SCENE){
  if(copy_from_user(&scene,u,sizeof(scene)))return -EFAULT;
  if(scene.version!=2||!scene.sequence||scene.count>8||scene.reserved)return -EINVAL;
  for(i=0;i<128;i++)if(scene.hud[i]<32||scene.hud[i]>126)return -EINVAL;
  for(i=0;i<scene.count;i++){
   struct ax7021b_display_annotation *a=&scene.annotation[i];unsigned j;
   if(a->x0>=a->x1||a->y0>=a->y1||a->x1>1280||a->y1>720||
      a->label_x>896||a->label_y>688)return -EINVAL;
   for(j=0;j<64;j++)if(a->label[j]<32||a->label[j]>126)return -EINVAL;
  }
 }
 mutex_lock(&d->lock);
 if(d->removing){ret=-ENODEV;goto end;}
 switch(cmd){
 case AX7021B_DISPLAY_START:ret=start_locked(d);break;
 case AX7021B_DISPLAY_STOP:ret=drain(d);d->running=false;break;
 case AX7021B_DISPLAY_SUBMIT:
  if(ore(d,0x28)&1){ret=-EBUSY;break;}
  if((s32)(text.sequence-d->requested)<=0){ret=-ESTALE;break;}
  for(i=0;i<32;i++)ow(d,0x100+4*i,(u32)text.text[4*i]|((u32)text.text[4*i+1]<<8)|((u32)text.text[4*i+2]<<16)|((u32)text.text[4*i+3]<<24));
  wmb();ow(d,0x20,text.sequence);
  if(ore(d,0x20)!=text.sequence){ret=-EIO;break;}
  d->requested=text.sequence;d->submissions++;break;
 case AX7021B_DISPLAY_SUBMIT_SCENE:
  if(ore(d,0x28)&1){ret=-EBUSY;break;}
  if((s32)(scene.sequence-d->requested)<=0){ret=-ESTALE;break;}
  for(i=0;i<scene.count;i++)if(scene.annotation[i].source_epoch!=d->epoch){ret=-ESTALE;break;}
  if(ret)break;
  for(i=0;i<160;i++){
   const u8 *bytes=i<32?scene.hud+4*i:scene.annotation[(i-32)/16].label+4*((i-32)%16);
   u32 word=(i<32||((i-32)/16)<scene.count)?(u32)bytes[0]|((u32)bytes[1]<<8)|((u32)bytes[2]<<16)|((u32)bytes[3]<<24):0x20202020;
   ow(d,0x1000+4*i,word);
  }
  for(i=0;i<8;i++){
   struct ax7021b_display_annotation *a=&scene.annotation[i];
   ow(d,0x200+16*i,i<scene.count?a->x0|(a->y0<<16):0);
   ow(d,0x204+16*i,i<scene.count?a->x1|(a->y1<<16):0);
   ow(d,0x208+16*i,i<scene.count?a->label_x|(a->label_y<<16):0);
   ow(d,0x20c+16*i,i<scene.count?1:0);
  }
  wmb();ow(d,0x20,scene.sequence);
  if(ore(d,0x20)!=scene.sequence){ret=-EIO;break;}
  d->requested=scene.sequence;d->submissions++;break;
 case AX7021B_DISPLAY_STATUS:
  s.running=d->running;s.requested=ore(d,0x20);s.applied=ore(d,0x24);s.flags=ore(d,0x28);s.source_epoch=d->epoch;
  s.source_frames=ore(d,0x30);s.branch_frames=ore(d,0x34);s.display_drops=ore(d,0x38);s.qr_drops=ore(d,0x3c);
  s.unique_frames=ore(d,0x40);s.committed_frames=ore(d,0x44);s.monitor_errors=ore(d,0x48);s.valid_slots=ore(d,0x4c);
  // Retry torn high/low tag reads instead of attributing a newer source ID.
  for(i=0;i<8;i++){tag1=ore(d,0x78);frame=ore(d,0x7c);tag2=ore(d,0x78);if(tag1==tag2)break;}
  if(i==8){ret=-EAGAIN;break;}
  s.scan_epoch=tag1;s.scan_frame=frame;s.read_dma_status=rd(d,4);s.write_dma_status=rd(d,0x34);
  s.read_irqs=atomic64_read(&d->read_irqs);s.write_irqs=atomic64_read(&d->write_irqs);s.dma_errors=atomic64_read(&d->dma_errors);
  s.recoveries=d->recoveries;s.quarantined=d->quarantine;s.submissions=d->submissions;
  if(copy_to_user(u,&s,sizeof(s)))ret=-EFAULT;
  break;
 default:ret=-ENOTTY;
 }
end:mutex_unlock(&d->lock);return ret;
}
static const struct file_operations display_fops={.owner=THIS_MODULE,.open=display_open,.unlocked_ioctl=display_ioctl,.compat_ioctl=display_ioctl,.llseek=noop_llseek};
static void release_clients(struct r4_display *d)
{
 if(d->ddc)i2c_unregister_device(d->ddc);
 if(d->hdmi)i2c_unregister_device(d->hdmi);
}
static int init_hdmi(struct r4_display *d)
{
 struct device_node *node;struct i2c_adapter *bus;int ret;
 node=of_parse_phandle(d->dev->of_node,"hdmi-i2c",0);if(!node)return -EINVAL;
 bus=of_find_i2c_adapter_by_node(node);of_node_put(node);if(!bus)return -EPROBE_DEFER;
 d->hdmi=i2c_new_dummy_device(bus,0x39);
 if(IS_ERR(d->hdmi)){ret=PTR_ERR(d->hdmi);d->hdmi=NULL;goto put;}
 d->ddc=i2c_new_dummy_device(bus,0x3d);
 if(IS_ERR(d->ddc)){ret=PTR_ERR(d->ddc);d->ddc=NULL;goto put;}
 gpiod_set_value_cansleep(d->reset,1);msleep(500);gpiod_set_value_cansleep(d->reset,0);msleep(500);
 ret=i2c_smbus_write_byte_data(d->hdmi,0x08,0x35);
 if(!ret)ret=i2c_smbus_write_byte_data(d->ddc,0x2f,0);
put:i2c_put_adapter(bus);return ret;
}
static int display_probe(struct platform_device *pdev)
{
 struct r4_display *d;u32 magic;int ret,i,irq;
 d=devm_kzalloc(&pdev->dev,sizeof(*d),GFP_KERNEL);if(!d)return -ENOMEM;
 d->dev=&pdev->dev;mutex_init(&d->lock);INIT_DELAYED_WORK(&d->health,health);
 d->vdma=devm_platform_ioremap_resource(pdev,0);if(IS_ERR(d->vdma))return PTR_ERR(d->vdma);
 d->osd=devm_platform_ioremap_resource(pdev,1);if(IS_ERR(d->osd))return PTR_ERR(d->osd);
 d->clock=devm_clk_get(d->dev,"video");if(IS_ERR(d->clock))return PTR_ERR(d->clock);
 ret=clk_prepare_enable(d->clock);if(ret)return ret;
 magic=ore(d,0);if(magic!=R4_MAGIC||ore(d,4)!=2||ore(d,8)!=11){ret=-ENODEV;goto clock;}
 d->reset=devm_gpiod_get(d->dev,"hdmi-reset",GPIOD_OUT_HIGH);if(IS_ERR(d->reset)){ret=PTR_ERR(d->reset);goto clock;}
 ret=init_hdmi(d);if(ret)goto clients;
 ret=dma_set_mask_and_coherent(d->dev,DMA_BIT_MASK(32));if(ret)goto clients;
 get_random_bytes(&d->epoch,sizeof(d->epoch));if(!d->epoch)d->epoch=1;
 for(i=0;i<3;i++){
  d->cpu[i]=dma_alloc_coherent(d->dev,FRAME_BYTES,&d->dma[i],GFP_KERNEL);
  if(!d->cpu[i]){ret=-ENOMEM;goto buffers;}
  memset(d->cpu[i],0,FRAME_BYTES);
 }
 ret=drain(d);if(ret)goto buffers;
 for(i=0;i<2;i++){
  irq=platform_get_irq(pdev,i);if(irq<0){ret=irq;goto buffers;}
  ret=devm_request_irq(d->dev,irq,display_irq,0,dev_name(d->dev),d);if(ret)goto buffers;d->irqs[i]=irq;
 }
 d->misc=(struct miscdevice){.minor=MISC_DYNAMIC_MINOR,.name="ax7021b-display0",.fops=&display_fops,.parent=d->dev,.mode=0600};
 ret=misc_register(&d->misc);if(ret)goto buffers;
 platform_set_drvdata(pdev,d);WRITE_ONCE(d->ready,true);
 schedule_delayed_work(&d->health,msecs_to_jiffies(20));
 dev_info(d->dev,"R4 RGB565 triple-buffer display ready; no fbdev/mmap, rectangle renderer disabled\n");
 return 0;
buffers:
 if(d->quarantine)get_device(d->dev);
 else for(i=0;i<3;i++)if(d->cpu[i])dma_free_coherent(d->dev,FRAME_BYTES,d->cpu[i],d->dma[i]);
clients:release_clients(d);
clock:if(!d->quarantine)clk_disable_unprepare(d->clock);return ret;
}
static void display_remove(struct platform_device *pdev)
{
 struct r4_display *d=platform_get_drvdata(pdev);int i;
 misc_deregister(&d->misc);mutex_lock(&d->lock);d->removing=true;mutex_unlock(&d->lock);
 for(i=0;i<2;i++)disable_irq(d->irqs[i]);
 cancel_delayed_work_sync(&d->health);mutex_lock(&d->lock);drain(d);
 if(d->quarantine)get_device(d->dev);
 else{
  for(i=0;i<3;i++)dma_free_coherent(d->dev,FRAME_BYTES,d->cpu[i],d->dma[i]);
  clk_disable_unprepare(d->clock);
 }
 release_clients(d);mutex_unlock(&d->lock);
}
static const struct of_device_id display_match[]={{.compatible="xiwei,c04-camera-display-r4"},{}};
MODULE_DEVICE_TABLE(of,display_match);
static struct platform_driver display_driver={.probe=display_probe,.remove_new=display_remove,.driver={.name="ax7021b-camera-display",.of_match_table=display_match}};
module_platform_driver(display_driver);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("C04 R4 camera-only VDMA and transparent PL OSD owner");
