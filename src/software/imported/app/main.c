/* QR video replay application: UDP RGB565 input -> DDR -> QR V1.2 pipeline -> UDP result. */
#include "qr_replay_protocol.h"
#include "net_replay.h"
#include "xaxivdma.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xtime_l.h"

#include <string.h>
#include <stdio.h>

/* Stage A acceptance runs the receive/DDR path without touching the QR PL.
 * Build with -DQR_REPLAY_TRANSPORT_ONLY=1 to enable it. */
#ifndef QR_REPLAY_TRANSPORT_ONLY
#define QR_REPLAY_TRANSPORT_ONLY 0
#endif

#if !QR_REPLAY_TRANSPORT_ONLY
#include "qr_pipeline.h"
#include "qr_quirc_fallback.h"
#endif

#if QR_REPLAY_TRANSPORT_ONLY
static void transport_report(uint32_t frame_id) {
    static char payload[96];
    sprintf(payload, "transport fps_milli=%u dup=%u overflow=%u",
            (unsigned)qr_replay_receive_fps_milli(),
            (unsigned)qr_replay_packets_duplicate(),
            (unsigned)qr_replay_ring_overflow());
    qr_replay_publish_result(frame_id, 0, 0U, 0U, payload, 0U, 0U);
}
#else
static XAxiVdma g_vdma;
static qr_candidate_t g_candidates[QR_MAX_CANDIDATES];
static qr_pipeline_result_t g_result;
static qr_pipeline_profile_t g_profile;
static qr_quirc_fallback_profile_t g_fallback_profile;
static qr_detector_config_t g_config;

static uint32_t qr_read(uint32_t offset) { return Xil_In32(QR_REPLAY_QR_CORE_BASE + offset); }
static void qr_write(uint32_t offset, uint32_t value) { Xil_Out32(QR_REPLAY_QR_CORE_BASE + offset, value); }

static uint32_t elapsed_us(XTime start, XTime end) { return (uint32_t)(((uint64_t)(end - start) * 1000000ULL) / COUNTS_PER_SECOND); }
static uint64_t profile_clock(void *context) {
    XTime now;
    (void)context;
    /* V1.2 calls the profiling clock between its major PS stages and for each
     * sampled hypothesis. Use those natural yield points to drain GEM RX. */
    qr_replay_net_service();
    XTime_GetTime(&now);
    return (uint64_t)now;
}

void qr_pipeline_cooperate(void) {
    qr_replay_net_service();
}

static int configure_vdma(void) {
#ifdef SDT
    XAxiVdma_Config *config = XAxiVdma_LookupConfig(XPAR_AXI_VDMA_0_BASEADDR);
#else
    XAxiVdma_Config *config = XAxiVdma_LookupConfig(XPAR_AXI_VDMA_0_DEVICE_ID);
#endif
    if (!config) return XST_FAILURE;
    return XAxiVdma_CfgInitialize(&g_vdma, config, config->BaseAddress);
}

static int start_frame(uint32_t frame_id, UINTPTR input_address) {
    XAxiVdma_DmaSetup read_config, write_config;
    UINTPTR read_addresses[XAXIVDMA_MAX_FRAMESTORE] = {0};
    UINTPTR write_addresses[XAXIVDMA_MAX_FRAMESTORE] = {0};
    uint32_t timeout = 1000000U;
    memset(&read_config, 0, sizeof(read_config)); memset(&write_config, 0, sizeof(write_config));
    XAxiVdma_DmaStop(&g_vdma, XAXIVDMA_READ); XAxiVdma_DmaStop(&g_vdma, XAXIVDMA_WRITE);
    XAxiVdma_Reset(&g_vdma, XAXIVDMA_READ); XAxiVdma_Reset(&g_vdma, XAXIVDMA_WRITE);
    while (XAxiVdma_ResetNotDone(&g_vdma, XAXIVDMA_READ) || XAxiVdma_ResetNotDone(&g_vdma, XAXIVDMA_WRITE))
        if (--timeout == 0U) return XST_FAILURE;
    write_config.VertSizeInput = QR_REPLAY_HEIGHT; write_config.HoriSizeInput = QR_REPLAY_WIDTH; write_config.Stride = QR_REPLAY_WIDTH;
    write_config.EnableCircularBuf = 1; write_config.EnableFrameCounter = 1;
    read_config.VertSizeInput = QR_REPLAY_HEIGHT; read_config.HoriSizeInput = QR_REPLAY_WIDTH * 2U; read_config.Stride = QR_REPLAY_WIDTH * 2U;
    read_config.EnableCircularBuf = 1; read_config.EnableFrameCounter = 1;
    read_addresses[0] = input_address; write_addresses[0] = QR_REPLAY_GRAY_ADDR;
    if (XAxiVdma_DmaConfig(&g_vdma, XAXIVDMA_WRITE, &write_config) != XST_SUCCESS ||
        XAxiVdma_DmaSetBufferAddr(&g_vdma, XAXIVDMA_WRITE, write_addresses) != XST_SUCCESS ||
        XAxiVdma_DmaConfig(&g_vdma, XAXIVDMA_READ, &read_config) != XST_SUCCESS ||
        XAxiVdma_DmaSetBufferAddr(&g_vdma, XAXIVDMA_READ, read_addresses) != XST_SUCCESS) return XST_FAILURE;
    Xil_DCacheInvalidateRange(QR_REPLAY_GRAY_ADDR, QR_REPLAY_WIDTH * QR_REPLAY_HEIGHT);
    qr_write(0x18U, frame_id); qr_write(0x00U, 0x03U); qr_write(0x08U, QR_REPLAY_WIDTH); qr_write(0x0CU, QR_REPLAY_HEIGHT); qr_write(0x10U, 128U);
    if (XAxiVdma_DmaStart(&g_vdma, XAXIVDMA_WRITE) != XST_SUCCESS) return XST_FAILURE;
    qr_write(0x00U, 0x11U);
    return XAxiVdma_DmaStart(&g_vdma, XAXIVDMA_READ);
}

static int wait_frame(void) {
    uint32_t timeout = 100000000U;
    while (timeout--) {
        uint32_t status = qr_read(0x04U);
        uint32_t read_irq = XAxiVdma_IntrGetPending(&g_vdma, XAXIVDMA_READ);
        if ((timeout & 0x3FFU) == 0U)
            qr_replay_net_service();
        if ((read_irq & XAXIVDMA_IXR_ERROR_MASK) != 0U) return -2;
        if ((status & 0x12U) == 0x12U && (read_irq & XAXIVDMA_IXR_FRMCNT_MASK) != 0U) {
            XAxiVdma_DmaStop(&g_vdma, XAXIVDMA_WRITE);
            while (XAxiVdma_IsBusy(&g_vdma, XAXIVDMA_WRITE) && timeout--) {}
            XAxiVdma_IntrClear(&g_vdma, read_irq, XAXIVDMA_READ);
            if ((status & 0x0CU) != 0U || qr_read(0x38U) == 0U)
                return -3;
            return 0;
        }
    }
    return -1;
}

static int read_candidates(uint32_t frame_id) {
    uint32_t count = qr_read(0x14U), index; int accepted = 0;
    if (count > QR_MAX_CANDIDATES) count = QR_MAX_CANDIDATES;
    for (index = 0; index < count; ++index) {
        uint32_t base = 0x1000U + index * 16U, xy = qr_read(base + 4U), score_module = qr_read(base + 8U);
        if (qr_read(base) != frame_id) continue;
        g_candidates[accepted].x = (float)(xy & 0xFFFFU); g_candidates[accepted].y = (float)(xy >> 16);
        g_candidates[accepted].module_size = (float)(score_module & 0xFFFFU) / 256.0f;
        g_candidates[accepted].score = (float)(score_module >> 16); ++accepted;
    }
    return accepted;
}

static int process_frame(uint32_t frame_id, UINTPTR input_address) {
    XTime total_start, pipeline_start, pipeline_end; qr_frame_view_t frame; int candidate_count, pipeline_status; uint32_t i;
    XTime_GetTime(&total_start);
    if (start_frame(frame_id, input_address) != XST_SUCCESS) return -10;
    pipeline_status = wait_frame(); if (pipeline_status != 0) return pipeline_status;
    Xil_DCacheInvalidateRange(QR_REPLAY_GRAY_ADDR, QR_REPLAY_WIDTH * QR_REPLAY_HEIGHT);
    candidate_count = read_candidates(frame_id); XTime_GetTime(&pipeline_start);
    frame.data = (const uint8_t *)QR_REPLAY_GRAY_ADDR; frame.width = QR_REPLAY_WIDTH; frame.height = QR_REPLAY_HEIGHT; frame.stride = QR_REPLAY_WIDTH; frame.pixel_format = QR_PIXEL_FORMAT_GRAY8;
    pipeline_status = qr_pipeline_run_v1_2(&frame, &g_config, g_candidates,
                                           candidate_count, &g_result,
                                           &g_profile, profile_clock, 0);
    if (pipeline_status != 0 || g_result.instance_count == 0U) {
        int fallback_count = qr_quirc_fallback_run(&frame, g_candidates,
                                                   candidate_count, &g_config,
                                                   &g_result,
                                                   &g_fallback_profile);
        if (fallback_count > 0) {
            pipeline_status = 0;
            g_profile.fallback_used = 1U;
            g_profile.instances_found = g_result.instance_count;
        }
    }
    XTime_GetTime(&pipeline_end);
    {
        static char payload[QR_MAX_INSTANCES * QR_MAX_PAYLOAD]; uint32_t length = 0U;
        payload[0] = 0;
        for (i = 0; i < g_result.instance_count; ++i) {
            uint32_t n = (uint32_t)strlen(g_result.instances[i].payload);
            if (length + n + (i ? 1U : 0U) >= sizeof(payload)) break;
            if (i) payload[length++] = '\n';
            memcpy(payload + length, g_result.instances[i].payload, n);
            length += n;
            payload[length] = 0;
        }
        /* QRS2 status reports execution health, not whether this frame
         * contained a decodable QR.  A normal zero-instance/negative result
         * is status=0 and is described by stage/instances/payload. */
        qr_replay_publish_result(frame_id, 0, (uint32_t)g_result.stage, g_result.instance_count, payload,
                                 elapsed_us(pipeline_start, pipeline_end), elapsed_us(total_start, pipeline_end));
    }
    (void)pipeline_status;
    return 0;
}
#endif

int main(void) {
    uint32_t frame_id; UINTPTR input_address;
    Xil_ICacheEnable(); Xil_DCacheEnable();
#if QR_REPLAY_TRANSPORT_ONLY
    if (qr_replay_net_init() != XST_SUCCESS) {
        xil_printf("QR replay network initialization failed\r\n"); return XST_FAILURE;
    }
    xil_printf("QR replay TRANSPORT-ONLY READY UDP input=%u result=%u\r\n", QR_REPLAY_INPUT_PORT, QR_REPLAY_RESULT_PORT);
    for (;;) {
        qr_replay_net_service();
        if (qr_replay_take_ready_frame(&frame_id, &input_address)) {
            transport_report(frame_id);
            qr_replay_release_frame(frame_id);
        }
    }
#else
    qr_detector_config_default(&g_config);
    xil_printf("QR video replay boot core=0x%08x\r\n", (unsigned)qr_read(0x20U));
    if (qr_read(0x20U) != 0x00010100U || configure_vdma() != XST_SUCCESS || qr_replay_net_init() != XST_SUCCESS) {
        xil_printf("QR replay hardware/network initialization failed\r\n"); return XST_FAILURE;
    }
    xil_printf("QR replay READY profile=%s geometry=%ux%u UDP input=%u result=%u drop_old=1\r\n",
               QR_REPLAY_PROFILE_NAME, (unsigned)QR_REPLAY_WIDTH, (unsigned)QR_REPLAY_HEIGHT,
               QR_REPLAY_INPUT_PORT, QR_REPLAY_RESULT_PORT);
    xil_printf("QR engine fast=V1.2/version3 fallback=perspective/version1-40\r\n");
    for (;;) {
        qr_replay_net_service();
        if (qr_replay_take_ready_frame(&frame_id, &input_address)) {
            int status = process_frame(frame_id, input_address);
            qr_replay_release_frame(frame_id);
            if (status != 0) xil_printf("QR replay frame=%u status=%d\r\n", (unsigned)frame_id, status);
        }
    }
#endif
}
