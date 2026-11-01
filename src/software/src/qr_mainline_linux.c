#define _POSIX_C_SOURCE 200809L
#include "qr_mainline_linux.h"
#include "qr_profile.h"
#include "qr_fitness_backend.h"

#include <errno.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>

#include "qr_pipeline.h"
#include "qr_pl_roi_protocol.h"
#include "qr_publication.h"
#include "qr_quirc_fallback.h"
#include "qr_tracker.h"
#include "qr_decode_scheduler.h"
#include "qr_candidate_trace.h"
#include "qr_candidate_schedule.h"

#define QR_WIDTH 1280U
#define QR_HEIGHT 720U
#define QR_STRIDE 1280U
#define QR_STORAGE_BYTES (QR_STRIDE * (QR_HEIGHT + 2U))
#define QR_SOFT_BUDGET_US QR_DECODE_BUDGET_US

struct qr_mainline_context {
 struct qr_mainline_symbol_geometry geometry[QR_MAINLINE_MAX_RESULTS];
 uint32_t display_roi_min,display_roi_max;
	qr_tracker_t tracker;
	qr_publication_t publication;
	qr_decode_scheduler_t scheduler;
	uint32_t last_roi_decode_calls;
	uint32_t last_pl_epoch;
	uint32_t trace_count;
	struct qr_roi_trace trace[QR_PL_ROI_LIMIT];
	struct qr_roi_priority priority;
	uint32_t decode_budget_us;
	const struct ax7021b_qr_frame_snapshot *snapshot;
};

int qr_mainline_set_decode_budget_us(struct qr_mainline_context *c,uint32_t budget){
 if(!c||budget<5000U||budget>60000U){errno=EINVAL;return -1;}
 c->decode_budget_us=budget;return 0;
}

uint32_t qr_mainline_trace_count(const struct qr_mainline_context *c){return c?c->trace_count:0;}
uint32_t qr_mainline_trace_size(void){return sizeof(struct qr_roi_trace);}
int qr_mainline_get_roi_trace(const struct qr_mainline_context *c,uint32_t i,struct qr_roi_trace *out,size_t bytes){
 if(!c||!out||i>=c->trace_count||bytes!=sizeof(*out)){errno=EINVAL;return -1;}
 *out=c->trace[i];return 0;
}

uint32_t qr_mainline_last_roi_decode_calls(const struct qr_mainline_context *context)
{
	return context ? context->last_roi_decode_calls : 0;
}

uint32_t qr_mainline_last_pl_epoch(const struct qr_mainline_context *context)
{
	return context ? context->last_pl_epoch : 0;
}

int qr_mainline_get_symbol_geometry(const struct qr_mainline_context *c,uint32_t i,
 struct qr_mainline_symbol_geometry *out,size_t bytes) {
 if(!c||!out||i>=QR_MAINLINE_MAX_RESULTS||bytes!=sizeof(*out)){errno=EINVAL;return -1;}
 *out=c->geometry[i];return 0;
}

static uint64_t monotonic_us(void)
{
	struct timespec value;
	clock_gettime(CLOCK_MONOTONIC, &value);
	return (uint64_t)value.tv_sec * 1000000ULL + (uint64_t)value.tv_nsec / 1000ULL;
}

struct qr_mainline_context *qr_mainline_create(void)
{
	struct qr_mainline_context *context = calloc(1, sizeof(*context));
	if (context) {
		qr_tracker_init(&context->tracker);
		qr_publication_init(&context->publication);
		qr_decode_scheduler_reset(&context->scheduler);
		context->decode_budget_us=QR_SOFT_BUDGET_US;
	}
	return context;
}

void qr_mainline_destroy(struct qr_mainline_context *context)
{
	if (context) {
		qr_tracker_finish(&context->tracker, "shutdown");
		free(context);
	}
}

static void publish_result(struct qr_mainline_context *context,
			   const qr_instance_t *instance, uint32_t frame,
			   uint64_t now_us, struct qr_mainline_result *output)
{
	qr_track_observation_t observation = { };
	qr_track_decision_t decision = { };
	qr_publication_observation_t pub = { };
	struct qr_mainline_symbol *symbol;
	float dx, dy;
	unsigned slot = 0;
	int action;

	if (!instance->payload[0] || output->decoded_count >= QR_MAINLINE_MAX_RESULTS)
		return;
	observation.finder_x[0] = instance->finder_tl_x;
	observation.finder_y[0] = instance->finder_tl_y;
	observation.finder_x[1] = instance->finder_tr_x;
	observation.finder_y[1] = instance->finder_tr_y;
	observation.finder_x[2] = instance->finder_bl_x;
	observation.finder_y[2] = instance->finder_bl_y;
	observation.finder_valid = 1;
	observation.geometry_reliable = 1;
	observation.frame_id = frame;
	observation.x = (instance->finder_tl_x + instance->finder_tr_x +
			 instance->finder_bl_x) / 3.0f;
	observation.y = (instance->finder_tl_y + instance->finder_tr_y +
			 instance->finder_bl_y) / 3.0f;
	dx = instance->finder_tr_x - instance->finder_tl_x;
	dy = instance->finder_tr_y - instance->finder_tl_y;
	observation.size = sqrtf(dx * dx + dy * dy);
	observation.module_size = observation.size / 22.0f;
	observation.sharpness = 1.0f;
	if (observation.size <= 0.0f ||
	    qr_tracker_observe_success(&context->tracker, &observation, now_us,
				       instance->payload, &decision))
		return;

	pub.x = observation.x;
	pub.y = observation.y;
	pub.size = observation.size;
	pub.frame = frame;
	pub.sample_us = now_us;
	pub.now_us = now_us;
	action = qr_publication_prepare(&context->publication, instance->payload,
				strlen(instance->payload), &pub, &slot);
	if (action == QR_PUB_NEW || action == QR_PUB_RETRY)
		qr_publication_commit(&context->publication, slot,
				      context->publication.entries[slot].id);
	if (action >= QR_PUB_DUPLICATE &&
	    context->publication.entries[slot].state != QR_PUB_UNUSED)
		qr_tracker_bind_publication(&context->tracker, decision.track_id,
			context->publication.entries[slot].id);

	struct qr_mainline_symbol_geometry *geometry=&context->geometry[output->decoded_count];
 geometry->version=1;geometry->frame=frame;geometry->epoch=context->last_pl_epoch;
 geometry->valid=instance->outer_corners_valid;
 memcpy(geometry->corners,instance->outer_corners,sizeof(geometry->corners));
 geometry->roi_min_xy=context->display_roi_min;geometry->roi_max_xy=context->display_roi_max;
 symbol = &output->symbols[output->decoded_count++];
	symbol->track_id = decision.track_id;
	if (action >= QR_PUB_DUPLICATE)
		symbol->publication_id = context->publication.entries[slot].id;
	symbol->x = observation.x;
	symbol->y = observation.y;
	symbol->size = observation.size;
	snprintf(symbol->payload, sizeof(symbol->payload), "%s", instance->payload);
}

static int read_matching_bank(struct qr_mainline_context *c,int fd, const qr_pl_guard_t *header,
			      struct ax7021b_qr_roi_bank *raw)
{
	struct timespec retry = { .tv_nsec = 1000000L };
	uint64_t deadline = monotonic_us() + QR_SOFT_BUDGET_US;
	unsigned bank;
 if(c->snapshot){
  memcpy(raw->data,c->snapshot->data,sizeof(raw->data));raw->words=496;raw->bank=0;
  if(qr_pl_bank_matches((qr_pl_bank_t *)raw->data,header))return 0;
  errno=EBADMSG;return -1;
 }

	do {
		for (bank = 0; bank < QR_PL_ROI_BANKS; ++bank) {
			qr_pl_bank_t *descriptor;
			memset(raw, 0, sizeof(*raw));
			raw->bank = bank;
			if (ioctl(fd, AX7021B_QR_IOC_GET_ROI_BANK, raw))
				return -1;
			descriptor = (qr_pl_bank_t *)raw->data;
			if (qr_pl_bank_matches(descriptor, header))
				return 0;
		}
		nanosleep(&retry, NULL);
	} while (monotonic_us() < deadline);
	errno = ETIMEDOUT;
	return -1;
}

int qr_mainline_process(struct qr_mainline_context *context, int capture_fd,
			const uint8_t *storage, size_t storage_bytes,
			uint64_t capture_sequence, struct qr_mainline_result *output)
{
	const qr_pl_guard_t *header, *footer;
	struct ax7021b_qr_roi_bank raw;
	qr_pl_bank_t *bank;
	qr_pl_roi_t *rois;
	qr_pipeline_result_t decoded = { };
	qr_quirc_fallback_profile_t profile;
	uint64_t started, now;
	unsigned i, before, visited, schedule_start, attempts = 0, roi_count;
	uint32_t order[QR_PL_ROI_LIMIT],history_slots[QR_PL_ROI_LIMIT];
	uint8_t executed[QR_PL_ROI_LIMIT]={0};

	if (!context || capture_fd < 0 || !storage || !output ||
	    storage_bytes < QR_STORAGE_BYTES) {
		errno = EINVAL;
		return -1;
	}
	qr_profile_reset();
	memset(output, 0, sizeof(*output));
 memset(context->geometry,0,sizeof(context->geometry));
	context->last_roi_decode_calls = 0;
	context->trace_count=0;
	memset(context->trace,0,sizeof(context->trace));
	context->last_pl_epoch = 0;
	output->capture_sequence = capture_sequence;
	header = (const qr_pl_guard_t *)storage;
	footer = (const qr_pl_guard_t *)(storage + QR_STRIDE * (QR_HEIGHT + 1U));
	if (!qr_pl_guards_valid(header, footer, QR_WIDTH, QR_HEIGHT,
				QR_PL_FORMAT_GRAY8, header->epoch, header->config_seq)) {
		errno = EBADMSG;
		return -1;
	}
	qr_fitness_set_frame(header->epoch,header->frame_seq,header->config_seq);
	output->metadata_valid = 1;
	context->last_pl_epoch = header->epoch;
	output->pl_frame_sequence = header->frame_seq;
	output->threshold = header->threshold;
	started = monotonic_us();
	if (read_matching_bank(context,capture_fd, header, &raw))
		return -1;
	bank = (qr_pl_bank_t *)raw.data;
	rois = (qr_pl_roi_t *)(raw.data + QR_PL_GUARD_WORDS);
	output->roi_count = bank->roi_count;
	roi_count = bank->roi_count < QR_PL_ROI_LIMIT ? bank->roi_count : QR_PL_ROI_LIMIT;
	context->trace_count=roi_count;
	for(i=0;i<roi_count;i++){
	 struct qr_roi_trace *t=&context->trace[i];
	 t->index=i;t->epoch=header->epoch;t->frame=header->frame_seq;t->config=header->config_seq;
	 t->min_xy=rois[i].min_xy;t->max_xy=rois[i].max_xy;
	 t->module_angle=rois[i].module_angle;t->score_word=rois[i].reserved[0];
	}
	schedule_start = qr_decode_scheduler_begin(&context->scheduler, roi_count);
	qr_roi_priority_begin(&context->priority,header->epoch,header->config_seq,
	    rois,roi_count,schedule_start,order,history_slots);
	for (visited = 0; visited < roi_count; ++visited) {
		qr_frame_view_t view;
		uint16_t x0, y0, x1, y1;
		uint64_t roi_started;
		struct qr_roi_trace *trace;
		if (!qr_roi_budget_allows(attempts, (uint32_t)(monotonic_us() - started),context->decode_budget_us))
			break;
		i = order[visited];
		trace=&context->trace[i];
		if (!qr_pl_roi_valid(&rois[i], QR_WIDTH, QR_HEIGHT)){
			trace->reason=QR_ROI_INVALID;
			continue;
		}
		unsigned duplicate=roi_count;
		for(unsigned j=0;j<roi_count;j++)if(executed[j] && qr_roi_same_crop(&rois[i],&rois[j])){duplicate=j;break;}
		if(duplicate<roi_count){
			trace->reason=QR_ROI_SAME_FRAME_DUPLICATE;trace->flags=(duplicate+1U)<<16;continue;
		}
		x0 = qr_pl_x(rois[i].min_xy); y0 = qr_pl_y(rois[i].min_xy);
		x1 = qr_pl_x(rois[i].max_xy); y1 = qr_pl_y(rois[i].max_xy);
		view.data = storage + QR_STRIDE + (size_t)y0 * QR_STRIDE + x0;
		view.width = x1 - x0;
		view.height = y1 - y0;
		view.stride = QR_STRIDE;
		view.pixel_format = QR_PIXEL_FORMAT_GRAY8;
		before = decoded.instance_count;
		memset(&profile, 0, sizeof(profile));
		roi_started=monotonic_us();
		qr_quirc_gray_roi_run(&view, x0, y0, &decoded, &profile);
		trace->total_us=(uint32_t)(monotonic_us()-roi_started);
		trace->copy_us=profile.copy_us;trace->identify_us=profile.identify_us;
		trace->sample_us=qr_quirc_last_sample_us();trace->ecc_us=qr_quirc_last_ecc_us();
		trace->flags=qr_quirc_last_attempt_flags();
		trace->decode_attempts=profile.decode_attempts;trace->grids_found=profile.grids_found;
		trace->decoded_instances=decoded.instance_count-before;
		trace->otsu_threshold=(uint32_t)qr_quirc_last_otsu_threshold();
		for(unsigned error=0;error<8;error++)trace->errors[error]=qr_quirc_last_error_count(error);
		trace->reason=trace->decoded_instances?QR_ROI_DECODED:
		    before>=QR_MAX_INSTANCES?QR_ROI_RESULT_LIMIT:
		    !trace->grids_found?QR_ROI_NO_GRID:
		    trace->errors[0]?QR_ROI_OUTPUT_FILTERED:QR_ROI_DECODE_FAILED;
		executed[i]=1;
		qr_roi_priority_attempt(&context->priority,history_slots[i],trace->decoded_instances);
		++attempts;
		++context->last_roi_decode_calls;
		now = monotonic_us();
		context->display_roi_min=rois[i].min_xy;context->display_roi_max=rois[i].max_xy;
		while (before < decoded.instance_count) {
			publish_result(context, &decoded.instances[before], header->frame_seq,
				       now, output);
			++before;
		}
	}
	qr_decode_scheduler_finish(&context->scheduler, roi_count, schedule_start, visited);
	for(i=0;i<roi_count;i++)if(context->trace[i].reason==QR_ROI_PENDING)context->trace[i].reason=QR_ROI_BUDGET;
	output->elapsed_us = (uint32_t)(monotonic_us() - started);
	output->soft_budget_exceeded = output->elapsed_us > context->decode_budget_us;
	qr_tracker_retire(&context->tracker, monotonic_us());
	return 0;
}

int qr_mainline_process_snapshot(struct qr_mainline_context *c,const uint8_t *storage,size_t bytes,
 uint64_t sequence,const struct ax7021b_qr_frame_snapshot *snapshot,struct qr_mainline_result *out)
{
 int rc;
 if(!c||!storage||bytes<QR_STORAGE_BYTES||!snapshot||!(snapshot->flags&1)||snapshot->sequence!=sequence||
    ((const qr_pl_guard_t *)storage)->frame_seq!=(uint32_t)(sequence+1)){
  errno=EBADMSG;return -1;
 }
 c->snapshot=snapshot;rc=qr_mainline_process(c,0,storage,bytes,sequence,out);c->snapshot=NULL;return rc;
}

int qr_mainline_process_file(struct qr_mainline_context *context,
			     const uint8_t *gray, uint32_t width, uint32_t height,
			     uint32_t stride, struct qr_mainline_result *output)
{
	qr_frame_view_t view;
	qr_detector_config_t config;
	qr_pipeline_result_t decoded = { };
	qr_quirc_fallback_profile_t profile = { };
	uint64_t started, now;
	unsigned i;
	int rc;

	if (!context || !gray || !output || width == 0 || height == 0 || stride < width) {
		errno = EINVAL;
		return -1;
	}
	qr_profile_reset();
	memset(output, 0, sizeof(*output));
 memset(context->geometry,0,sizeof(context->geometry));
	view.data = gray;
	context->trace_count=0;
	memset(context->trace,0,sizeof(context->trace));
	context->last_roi_decode_calls = 0;
	context->last_pl_epoch = 0;
	view.width = width;
	view.height = height;
	view.stride = stride;
	view.pixel_format = QR_PIXEL_FORMAT_GRAY8;
	qr_detector_config_default(&config);
	started = monotonic_us();
	rc = qr_quirc_fallback_run(&view, NULL, 0, &config, &decoded, &profile);
	now = monotonic_us();
	if (rc < 0)
		return rc;
	for (i = 0; i < decoded.instance_count; ++i)
		publish_result(context, &decoded.instances[i], 0, now, output);
	output->elapsed_us = (uint32_t)(now - started);
	output->soft_budget_exceeded = output->elapsed_us > QR_SOFT_BUDGET_US;
	return 0;
}
