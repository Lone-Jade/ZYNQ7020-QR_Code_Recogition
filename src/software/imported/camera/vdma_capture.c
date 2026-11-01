/* VDMA S2MM 采集通道 + 三帧缓冲管理。
 *
 * 这里每一处"反直觉"的写法都有上板实测的原因，注释是从调试过程里留下的，
 * 改之前请先读完。核心结论：
 *   * S2MM 是动态 Genlock **主**通道，不能开帧计数器，也不能指望 CurrFrameStore；
 *   * 帧完成用 SR bit12（IOC）判断，只能轮询（中断被证明会带来问题）；
 *   * "正在写哪一帧"靠实测特征值 + 多行采样推断，不靠寄存器。
 */
#include "vdma_capture.h"
#include "board.h"
#include "ethernet_config.h"

#include "xaxivdma.h"
#include "xil_cache.h"
#include "xil_exception.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xscugic.h"
#include "xstatus.h"
#include "sleep.h"

#include <string.h>

static XAxiVdma vdma;
static XScuGic gic;
static XAxiVdma_DmaSetup s2mm_setup;

static UINTPTR frames[3] = {FRAME0, FRAME1, FRAME2};

static volatile int frame_ready;
static volatile int vdma_irq_enabled;
static u32 fallback_ticks;
static u32 s2mm_dead_ticks;

/* 位流能力探测结果（capture_init 里填）。 */
static int genlock_ok;
static int mm2s_ready;

/* 本轮看门狗周期内是否见到过帧完成；以及"重启后先丢几帧"。 */
static volatile int saw_completion;
static u32 skip_frames;

static u32 active_frame_index;
/* 当前认为"正在被写"的缓冲（探针实测）。上板实测：SVGA 位流**只写 FRAME0**，
 * HD 位流会轮转，所以这个索引必须由探针实测，不能靠计数器推。 */
static u32 safe_frame_index;
static int have_safe;
/* 只写不读：留给在线调试时直接看"最近一次已知完成的缓冲索引"。 */
static volatile u32 completed_frame_index;

static void s2mm_recover(void);

/* ---- S2MM 通道配置 ---------------------------------------------------------
 * 与 ov5640_1 已上板验证的版本保持一致：
 *  - EnableSync=0：S2MM 是动态 Genlock **主**通道，EnableSync 是给从通道用的；
 *  - EnableFrameCounter=0 且**不调用** XAxiVdma_SetFrameCounter()：帧计数器会让通道
 *    传完 N 帧后自行 halt —— 这正是"只采到最初几帧就不动了"的直接原因；
 *  - GenLockRepeat=1 + EnableCircularBuf=1：三帧循环。
 * 帧完成中断用的是 SR bit12（IOC_Irq，宏名恰好叫 XAXIVDMA_IXR_FRMCNT_MASK），
 * 与帧计数器无关，所以关掉帧计数器不影响中断判断。 */
static void fill_s2mm_setup(void) {
    memset(&s2mm_setup, 0, sizeof(s2mm_setup));
    s2mm_setup.VertSizeInput = VIDEO_HEIGHT;
    s2mm_setup.HoriSizeInput = VIDEO_STRIDE;
    s2mm_setup.Stride = VIDEO_STRIDE;
    s2mm_setup.EnableCircularBuf = 1;
    s2mm_setup.EnableSync = 0;
    s2mm_setup.EnableFrameCounter = 0;
    s2mm_setup.GenLockRepeat = 1;
}

static int s2mm_config_and_start(void) {
    int st = XAxiVdma_DmaConfig(&vdma, XAXIVDMA_WRITE, &s2mm_setup);
    if (st != XST_SUCCESS) return st;
    st = XAxiVdma_DmaSetBufferAddr(&vdma, XAXIVDMA_WRITE, frames);
    if (st != XST_SUCCESS) return st;
    return XAxiVdma_DmaStart(&vdma, XAXIVDMA_WRITE);
}

int capture_init(void) {
    XAxiVdma_Config *cfg;
    int st;

    /* 分步打印：capture_init 里任何一次 AXI 访问如果打到"没有译码"或"时钟没起来"
     * 的寄存器上，CPU 会**永久停住**（AXI 事务不返回 -> 读挂死，或者 DECERR ->
     * 数据异常进异常向量），串口上什么都看不到。
     *
     * 注意顺序：先打印再调用 LookupConfig。若 "[ci] lookup" 之后没有 "[ci] tbl"，
     * 说明卡在 LookupConfig 自己的表遍历里 —— 那是纯软件循环，只有一种可能：
     * XAxiVdma_ConfigTable 的结束项（Name == NULL）不对，循环越界了。 */
    xil_printf("[ci] lookup VDMA @%x\r\n", (unsigned)VDMA_BASE);
    {
        extern XAxiVdma_Config XAxiVdma_ConfigTable[];
        xil_printf("[ci] tbl0 name=%x base=%x\r\n",
                   (unsigned)(UINTPTR)XAxiVdma_ConfigTable[0].Name,
                   (unsigned)XAxiVdma_ConfigTable[0].BaseAddress);
        xil_printf("[ci] tbl1 name=%x (0=terminated)\r\n",
                   (unsigned)(UINTPTR)XAxiVdma_ConfigTable[1].Name);
    }
    cfg = XAxiVdma_LookupConfig(VDMA_BASE);
    xil_printf("[ci] cfg=%x\r\n", (unsigned)(UINTPTR)cfg);
    if (!cfg) return XST_FAILURE;

    st = XAxiVdma_CfgInitialize(&vdma, cfg, cfg->BaseAddress);
    xil_printf("[ci] cfginit st=%d\r\n", st);
    if (st != XST_SUCCESS) return st;

    /* BSP 里的 HasMm2S / InternalGenLock 来自位流（XAxiVdma_ConfigTable），
     * 所以这张表就是"这位流到底有什么"的权威描述。 */
    xil_printf("[ci] hw MM2S=%d S2MM=%d genlock=%d\r\n",
               (int)vdma.HasMm2S, (int)vdma.HasS2Mm, (int)vdma.InternalGenLock);

    /* 内部 Genlock 源选择：驱动只在 HasMm2S && HasS2Mm && InternalGenLock 时允许，
     * 否则返回 XST_FAILURE（"This bit is not valid for this configuration"）。
     *
     * **失败不能当致命错误**：位流若是"只有 S2MM 的相机专用设计"，这个调用必然失败，
     * 而 S2MM 自己是 EnableSync=0 的动态主通道，本来就不需要选 genlock 源。
     * 2026-10-03 就是因为这里直接 return st，导致相机专用位流上 capture_init()
     * 一进门就失败：不采帧、不发包，而日志只提示一句 "WARNING: VDMA init failed"。
     */
    genlock_ok = 0;
    if (XAxiVdma_GenLockSourceSelect(&vdma, XAXIVDMA_INTERNAL_GENLOCK,
                                     XAXIVDMA_WRITE) == XST_SUCCESS) {
        genlock_ok = 1;
    } else {
        xil_printf("NOTE: S2MM internal-genlock source not supported by this "
                   "bitstream; running S2MM-only\r\n");
    }
    xil_printf("[ci] genlock_ok=%d\r\n", genlock_ok);

    fill_s2mm_setup();

#if KEEP_HDMI_OUTPUT
    /* MM2S 只在"位流真的有 MM2S"且"内部 Genlock 可用"时才配。
     * 内部 Genlock 下 MM2S 是动态从通道、S2MM 是动态主通道；实测必须让 MM2S
     * 也跑起来，采集才稳定。但相机专用位流没有 MM2S —— 这时绝不能去写 MM2S
     * 的寄存器，否则要么报错、要么在不存在的位置上瞎写。 */
    mm2s_ready = 0;
    if (vdma.HasMm2S && genlock_ok) {
        XAxiVdma_DmaSetup r;
        st = XAxiVdma_GenLockSourceSelect(&vdma, XAXIVDMA_INTERNAL_GENLOCK,
                                          XAXIVDMA_READ);
        xil_printf("[ci] mm2s genlock st=%d\r\n", st);
        if (st == XST_SUCCESS) {
            memset(&r, 0, sizeof(r));
            r.VertSizeInput = VIDEO_HEIGHT;
            r.HoriSizeInput = VIDEO_STRIDE;
            r.Stride = VIDEO_STRIDE;
            /* MM2S 是动态 Genlock 从通道，延迟一帧，避免读到正在写的帧 */
            r.EnableCircularBuf = 1;
            r.EnableSync = 1;
            r.FrameDelay = 1;
            st = XAxiVdma_DmaConfig(&vdma, XAXIVDMA_READ, &r);
            xil_printf("[ci] mm2s dmaConfig st=%d\r\n", st);
            if (st == XST_SUCCESS) {
                st = XAxiVdma_DmaSetBufferAddr(&vdma, XAXIVDMA_READ, frames);
                xil_printf("[ci] mm2s setBufAddr st=%d\r\n", st);
                if (st == XST_SUCCESS) mm2s_ready = 1;
            }
            if (!mm2s_ready) {
                xil_printf("NOTE: MM2S setup failed; running S2MM-only\r\n");
            }
        } else {
            xil_printf("NOTE: MM2S genlock select failed; running S2MM-only\r\n");
        }
    } else {
        xil_printf("NOTE: bitstream has no usable MM2S; running S2MM-only\r\n");
    }
#endif

    completed_frame_index = 0U;
    xil_printf("[ci] s2mm config+start...\r\n");
    st = s2mm_config_and_start();
    xil_printf("[ci] s2mm st=%d\r\n", st);
    if (st != XST_SUCCESS) return st;

#if KEEP_HDMI_OUTPUT
    if (mm2s_ready) {
        st = XAxiVdma_DmaStart(&vdma, XAXIVDMA_READ);
        xil_printf("[ci] mm2s start st=%d\r\n", st);
        if (st != XST_SUCCESS) {
            xil_printf("NOTE: MM2S start failed; running S2MM-only\r\n");
            mm2s_ready = 0;
        }
    }
#endif
    xil_printf("[ci] done\r\n");
    return XST_SUCCESS;
}

/* ---- 采集看门狗 ------------------------------------------------------------
 * 启动瞬间 cam1_pclk 与 DVP 时序还没稳，VDMA 可能报 ERR_FSZ_MORE(0x800) /
 * ERR_INTERNAL(0x10) 之类错误，严重时**自行 halt**：通道一停，三个帧缓冲就冻在
 * 最初那几帧上，画面表现为"三张图轮着闪、动摄像头没反应"。
 *
 * 注意：SR 里的错误位是**锁存**的，启动时报过一次就会一直读得到，并不代表现在
 * 有问题。所以"是否健康"只看 bit0 Halted；错误位顺手清掉，让状态寄存器可读。 */
static int s2mm_halted(void) {
    return (XAxiVdma_GetStatus(&vdma, XAXIVDMA_WRITE) & 0x1U) != 0U;
}

static void s2mm_clear_latched_errors(void) {
    if (XAxiVdma_GetStatus(&vdma, XAXIVDMA_WRITE) & XAXIVDMA_SR_ERR_ALL_MASK) {
        XAxiVdma_IntrClear(&vdma, XAXIVDMA_IXR_ALL_MASK | XAXIVDMA_SR_ERR_ALL_MASK,
                           XAXIVDMA_WRITE);
    }
}

void capture_watchdog(void) {
    if (++fallback_ticks < FALLBACK_TICKS) return;
    fallback_ticks = 0U;

    /* 判定"死了"必须**同时**满足两条：
     *   (1) SR bit0 Halted 置位；
     *   (2) 这一整段周期里一帧都没完成（saw_completion == 0）。
     *
     * 只看 Halted 会误杀：通道刚被拉起来、或某些位流在帧边界上会短暂置位，
     * 于是看门狗每隔 ~330 ms 就把健康的通道打断重启一次 —— 每次重启都丢掉
     * 半帧并重置帧指针，表现出来正是**周期性闪烁 + 撕裂**。 */
    if (s2mm_halted() && !saw_completion) {
        if (++s2mm_dead_ticks >= S2MM_DEAD_LIMIT) {
            s2mm_dead_ticks = 0U;
            s2mm_recover();
        }
    } else {
        s2mm_dead_ticks = 0U;
    }
    saw_completion = 0;
}

/* ---- 决定"读哪一个帧缓冲" ------------------------------------------------
 * 这套设计里 VDMA **只往一个 frame store 持续写实时数据**（实测能正常显示的
 * ov5640_1 SVGA 参考版本也一样：三个缓冲只有一个被覆盖）。而且
 * XAxiVdma_CurrFrameStore() 在这个 IP(v6.3) 的寄存器布局下读到的索引**和实际
 * 在写的缓冲对不上** —— 结果就是把参考应用开机写下的彩条当成"画面"发出去。
 *
 * 所以不猜索引，启动时用特征值实测一遍：
 *   1. 三个缓冲各填 0xDEADBEEF
 *   2. 等 VDMA 覆盖掉其中一个
 *   3. 首字不再是特征值的那个，就是在写的缓冲
 */
int capture_pick_active_frame(void) {
    u32 i, j, k, found = 3U;

    for (i = 0U; i < 3U; i++) {
        volatile u32 *p = (volatile u32 *)frames[i];
        for (j = 0U; j < 512U; j++) p[j] = 0xDEADBEEFU;
        Xil_DCacheFlushRange(frames[i], 512U * 4U);
    }

    /* 关键：**等到"某一个缓冲先变"就停**，而不是固定等 400 ms。
     *
     * 原来的写法先 usleep(400000) 再顺序检查三个缓冲。三帧轮转下 400 ms
     * （48fps 时约 19 帧）足以把三个缓冲**全部**写完，于是顺序检查永远在
     * i=0 就命中，active_frame_index 恒为 0 —— 就算实际在写的是别的缓冲也一样。
     * 索引一旦错，后面"选安全帧"的判断基准就全错了。
     *
     * 改成 1 ms 轮询、先变的就是此刻正在被写的缓冲（一帧 20 ms，1 ms 内至少
     * 已经写了一行）。最多等 200 ms，超时才算失败。 */
    for (k = 0U; k < 200U && found == 3U; k++) {
        usleep(1000U);
        for (i = 0U; i < 3U; i++) {
            /* 只关心第 0 个字，所以失效 64 字节（2 条 cache line）就够。 */
            Xil_DCacheInvalidateRange(frames[i], 64U);
            if (((volatile u32 *)frames[i])[0] != 0xDEADBEEFU) {
                found = i;
                break;
            }
        }
    }

    if (found < 3U) {
        active_frame_index = found;
        completed_frame_index = found;
        safe_frame_index = found;
        have_safe = 1;
        xil_printf("capture frame store=%u\r\n", (unsigned)found);
        return 1;
    }
    active_frame_index = 0U;
    completed_frame_index = 0U;
    safe_frame_index = 0U;
    have_safe = 1;
    xil_printf("WARNING: VDMA is not writing any frame store\r\n");
    return 0;
}

/* ---- 选"可以安全读"的帧缓冲 + 发送快照（消除上半部横向错位）----------------
 *
 * 【2026-10-03 第三次修复 —— 前两次都错了，这里是实测结论】
 *
 * 前两版都在"怎么判断哪一个缓冲刚写完"上打转，方向就错了。上板诊断
 * （每 100 帧一行 DBG100）给出了三个硬事实：
 *
 *   1. done ≈ frame：IOC 一个没漏（发送循环里的高频 capture_poll 有效）；
 *   2. n=a,b,c 这一列**始终是 16,0,0 / 15,0,0 / 13,0,0 …** ——
 *      **只有 FRAME0 在变，FRAME1/FRAME2 从头到尾一次都没被写过**；
 *   3. 所以 VDMA **根本没有在三个缓冲间轮转**（代码最早的注释其实就写过这一点），
 *      任何"按 0→1→2 推进索引"的推导都是错的（那会把两个死缓冲当活图发出去）。
 *
 * 真正的根因和"选哪个缓冲"无关：
 *   **发送一帧要 ~28 ms（实测只有 34~38 fps），而 VDMA 每 20.8 ms 就把
 *     FRAME0 整个重写一遍 —— 读的过程中必定被覆盖。**
 *   先读到的前半帧是旧内容、后读到的后半帧是新内容
 *   → 画面表现为上半部一条横向区域上下错位（分界线位置固定）。
 *
 * 因此修法是**隔离**，不是"挑时机"：
 *   - 用探针实测出"正在被写"的那个缓冲（SVGA 恒为 0，HD 会轮转，都覆盖）；
 *   - **整帧先 memcpy 到 FRAME_SNAPSHOT，再从快照发送** —— 快照不参与 VDMA 写，
 *     发送读多久都不会被改。
 *   - 拷贝紧跟"帧完成"做：下一次写入还要 ~14 ms 才开始，来得及；
 *     DBG100 里的 copy_us 就是这个拷贝的耗时，用来确认它确实远小于 14 ms。
 *
 * 代价：每帧多一次全帧拷贝（DBG100 的 copy_us 可见），帧率会掉一些。
 * 若要把帧率找回来，方向是**让发送变快**（现在 1 MB 要 28 ms，链路明明能跑
 * 800 Mbit/s），那样读的窗口短于写入周期，连快照都可以不要。
 */
#define PROBE_COUNT 16U
#define PROBE_WORD(row) (((u32)(row) * VIDEO_HEIGHT / 600U) * (VIDEO_STRIDE / 4U))

static const u32 probe_words[PROBE_COUNT] = {
    PROBE_WORD(20U),  PROBE_WORD(58U),  PROBE_WORD(96U),  PROBE_WORD(134U),
    PROBE_WORD(172U), PROBE_WORD(210U), PROBE_WORD(248U), PROBE_WORD(286U),
    PROBE_WORD(324U), PROBE_WORD(362U), PROBE_WORD(400U), PROBE_WORD(438U),
    PROBE_WORD(476U), PROBE_WORD(514U), PROBE_WORD(552U), PROBE_WORD(590U)
};
#define PROBE_LATE_FROM (PROBE_COUNT * 2U / 3U)

static u32 probe_prev[3][PROBE_COUNT];
static int have_probe;
static u32 dbg_n[3];
static u32 dbg_late[3];
static u32 dbg_copy_us;

/* Cortex-A9 全局定时器（Zynq 的 XTime 就是读它）：0xF8F00200，CPU/2 = 333 MHz。
 * 直接用寄存器而不是 xtime_l.h —— 那个头文件不在应用侧的 include 路径里。
 * 若定时器没跑，读回来是常数，copy_us 会显示 0，只影响诊断显示。 */
#define GTIMER_LO (*(volatile u32 *)0xF8F00200U)
#define GTIMER_HI (*(volatile u32 *)0xF8F00204U)
static u32 gtimer_us(void) {
    u32 hi1, hi2, lo;
    do {
        hi1 = GTIMER_HI;
        lo  = GTIMER_LO;
        hi2 = GTIMER_HI;
    } while (hi1 != hi2);
    return (u32)((((u64)hi2 << 32) | lo) / 333U);
}

static void probe_sample(void) {
    u32 cur[3][PROBE_COUNT];
    u32 i, k;

    for (i = 0U; i < 3U; i++) {
        for (k = 0U; k < PROBE_COUNT; k++) {
            volatile u32 *p = ((volatile u32 *)frames[i]) + probe_words[k];
            Xil_DCacheInvalidateRange((UINTPTR)p, 4U);
            cur[i][k] = *p;
        }
    }
    if (!have_probe) {
        for (i = 0U; i < 3U; i++) {
            for (k = 0U; k < PROBE_COUNT; k++) probe_prev[i][k] = cur[i][k];
        }
        have_probe = 1;
        return;
    }
    for (i = 0U; i < 3U; i++) {
        dbg_n[i] = 0U;
        dbg_late[i] = 0U;
        for (k = 0U; k < PROBE_COUNT; k++) {
            if (cur[i][k] != probe_prev[i][k]) {
                dbg_n[i]++;
                if (k >= PROBE_LATE_FROM) dbg_late[i] = 1U;
            }
        }
    }
    for (i = 0U; i < 3U; i++) {
        for (k = 0U; k < PROBE_COUNT; k++) probe_prev[i][k] = cur[i][k];
    }
}

const void *capture_begin_read(void) {
    const void *src;

    probe_sample();

    /* 选出"刚被写过的那一个"（变化行最多、且靠后的行也变过）。找不到就沿用上次。 */
    {
        u32 i, best = 3U, bestn = 0U, second = 0U;
        for (i = 0U; i < 3U; i++) {
            if (dbg_n[i] > bestn) { second = bestn; bestn = dbg_n[i]; best = i; }
            else if (dbg_n[i] > second) { second = dbg_n[i]; }
        }
        if (best < 3U && dbg_late[best] && bestn >= 2U && bestn > second) {
            safe_frame_index = best;
        }
    }

    src = (const void *)frames[safe_frame_index % 3U];
    Xil_DCacheInvalidateRange((UINTPTR)src, VIDEO_BYTES);

    /* **关键：先快照再发。**
     *
     * 上板实测（DBG100 的 n=a,b,c 一列）显示：SVGA 位流的 VDMA **只写 FRAME0**，
     * 1/2 号缓冲从头到尾一次都没变过。而发送一帧要 ~28 ms，VDMA 每 20.8 ms 就把
     * FRAME0 整个重写一遍 —— **读的过程中必定被覆盖**：先读到的前半帧是旧内容、
     * 后读到的后半帧是新内容，画面表现为上半部一条横向区域上下错位。
     *
     * 整帧先拷到 FRAME_SNAPSHOT 再发，就与 VDMA 的后续写入彻底隔离。
     * 拷贝紧跟"帧完成"做，下一次写入还要 ~14 ms 才开始，来得及。 */
    {
        u32 t0 = gtimer_us();
        memcpy((void *)FRAME_SNAPSHOT, src, VIDEO_BYTES);
        dbg_copy_us = gtimer_us() - t0;
    }
    return (const void *)FRAME_SNAPSHOT;
}

u32 capture_safe_index(void) {
    return safe_frame_index;
}

void capture_debug(u32 *pick, u32 *copy_us, const u32 **n, const u32 **late) {
    if (pick)    *pick    = safe_frame_index;
    if (copy_us) *copy_us = dbg_copy_us;
    if (n)       *n       = dbg_n;
    if (late)    *late    = dbg_late;
}

void capture_poll(void) {
    u32 sr = XAxiVdma_GetStatus(&vdma, XAXIVDMA_WRITE);

    if ((sr & XAXIVDMA_IXR_FRMCNT_MASK) == 0U) return;   /* SR bit12 = IOC_Irq */
    XAxiVdma_IntrClear(&vdma, XAXIVDMA_IXR_FRMCNT_MASK, XAXIVDMA_WRITE);
    completed_frame_index = safe_frame_index;
    frame_ready = 1;
    saw_completion = 1;
}

int capture_take_frame_ready(void) {
    if (!frame_ready) return 0;
    frame_ready = 0;
    /* 通道刚重启时，最早的几帧横跨"重启前 / 重启后"两组数据，天然是撕裂的。
     * 直接丢掉不往外发，避免接收端看到花屏闪一下。 */
    if (skip_frames != 0U) {
        skip_frames--;
        return 0;
    }
    return 1;
}

static void s2mm_recover(void) {
    xil_printf("VDMA S2MM halted (SR=0x%08x); restarting\r\n",
               (unsigned)XAxiVdma_GetStatus(&vdma, XAXIVDMA_WRITE));
    XAxiVdma_DmaStop(&vdma, XAXIVDMA_WRITE);       /* 停机 + 软复位，顺带清错误位 */
    usleep(2000);
    s2mm_clear_latched_errors();
    if (s2mm_config_and_start() != XST_SUCCESS) {
        xil_printf("VDMA S2MM restart failed\r\n");
    } else {
        completed_frame_index = 0U;
        frame_ready = 0;
        s2mm_dead_ticks = 0U;
        /* 重启后帧缓冲内容是"两段拼接"的，先丢几帧；同时让"选安全帧"重新学一遍
         * 三帧的基线（have_probe=0），否则会拿重启前的采样去比对。 */
        skip_frames = POST_RECOVER_SKIP_FRAMES;
        have_probe = 0;     /* 探针基线作废，重新学"在写哪一个缓冲" */
        saw_completion = 0;
        xil_printf("VDMA S2MM restarted\r\n");
    }
}

static void vdma_s2mm_isr(void *ref) {
    XAxiVdma *v = (XAxiVdma *)ref;
    u32 st = XAxiVdma_IntrGetPending(v, XAXIVDMA_WRITE);

    XAxiVdma_IntrClear(v, st, XAXIVDMA_WRITE);
    /* 这里**绝对不要**再动 completed_frame_index。
     * 原来写的是 (CurrFrameStore+2)%3，而 CurrFrameStore 在本 IP 布局下不可靠，
     * 固定算成 2 —— 于是它和主循环里的轮询抢着写这个变量：轮询写 0（正在写的
     * F0，真实图像），中断写 2（参考应用留下的彩条 F2）。结果就是接收端大部分
     * 时间看到彩条。帧的选择统一由 capture_pick_active_frame()/轮询负责。 */
    if (st & XAXIVDMA_IXR_FRMCNT_MASK) {
        frame_ready = 1;
        fallback_ticks = 0;
    }
}

int capture_irq_init(void) {
    XScuGic_Config *gc = XScuGic_LookupConfig(XPAR_SCUGIC_SINGLE_DEVICE_ID);

    if (!gc || XScuGic_CfgInitialize(&gic, gc, gc->CpuBaseAddress) != XST_SUCCESS) {
        return XST_FAILURE;
    }
    Xil_ExceptionInit();
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT,
                                (Xil_ExceptionHandler)XScuGic_InterruptHandler, &gic);
    Xil_ExceptionEnable();
    if (XScuGic_Connect(&gic, XPAR_FABRIC_AXI_VDMA_0_INTR,
                        (Xil_InterruptHandler)vdma_s2mm_isr, &vdma) != XST_SUCCESS) {
        return XST_FAILURE;
    }
    /* 不要 enable VDMA 的中断。
     * 交叉实验证明：同一份位流配 ov5640_1 的参考应用时采集完全正常，
     * 所以差异在应用侧。参考应用不用 VDMA 中断、只轮询，这里也照做，
     * 把中断彻底排除掉。 */
    (void)vdma_s2mm_isr;
    vdma_irq_enabled = 0;
    return XST_SUCCESS;
}
