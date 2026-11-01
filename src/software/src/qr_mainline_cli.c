#define _POSIX_C_SOURCE 200809L
#include "qr_mainline_linux.h"

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

static volatile sig_atomic_t interrupted;
static void handle_signal(int signal_number) { (void)signal_number; interrupted = 1; }

static void json_string(const char *value)
{
	const unsigned char *p = (const unsigned char *)value;
	putchar('"');
	while (*p) {
		switch (*p) {
		case '"': fputs("\\\"", stdout); break;
		case '\\': fputs("\\\\", stdout); break;
		case '\n': fputs("\\n", stdout); break;
		case '\r': fputs("\\r", stdout); break;
		case '\t': fputs("\\t", stdout); break;
		default:
			if (*p < 0x20) printf("\\u%04x", *p); else putchar(*p);
		}
		++p;
	}
	putchar('"');
}

static void emit_result(const struct qr_mainline_context *context,
			const struct qr_mainline_result *result)
{
	unsigned i;
	printf("{\"capture_sequence\":%llu,\"pl_frame_sequence\":%u,"
	       "\"metadata_valid\":%u,\"threshold\":%u,\"roi_count\":%u,"
	       "\"decoded_count\":%u,\"elapsed_us\":%u,\"soft_budget_exceeded\":%u,"
	       "\"roi_decode_calls\":%u,\"pl_epoch\":%u,\"symbols\":[",
	       (unsigned long long)result->capture_sequence, result->pl_frame_sequence,
	       result->metadata_valid, result->threshold, result->roi_count,
	       result->decoded_count, result->elapsed_us, result->soft_budget_exceeded,
	       qr_mainline_last_roi_decode_calls(context),qr_mainline_last_pl_epoch(context));
	for (i = 0; i < result->decoded_count; ++i) {
		const struct qr_mainline_symbol *symbol = &result->symbols[i];
		if (i) putchar(',');
		printf("{\"track_id\":%u,\"publication_id\":%u,\"x\":%.2f,"
		       "\"y\":%.2f,\"size\":%.2f,\"payload\":",
		       symbol->track_id, symbol->publication_id,
		       symbol->x, symbol->y, symbol->size);
		json_string(symbol->payload);
		putchar('}');
	}
	puts("]}");
	fflush(stdout);
}

static int process_file(const char *path, unsigned width, unsigned height)
{
	struct qr_mainline_context *context;
	struct qr_mainline_result result;
	uint8_t *data;
	size_t bytes = (size_t)width * height;
	FILE *stream;
	int rc = 1;

	stream = fopen(path, "rb");
	if (!stream) return -1;
	data = malloc(bytes);
	if (!data) goto out;
	if (fread(data, 1, bytes, stream) != bytes || fgetc(stream) != EOF) {
		errno = EINVAL;
		goto free_data;
	}
	context = qr_mainline_create();
	if (!context) goto free_data;
	if (!qr_mainline_process_file(context, data, width, height, width, &result)) {
		emit_result(context, &result);
		rc = 0;
	}
	qr_mainline_destroy(context);
free_data:
	free(data);
out:
	fclose(stream);
	return rc;
}

static int capture_frames(const char *device, unsigned count)
{
	struct qr_mainline_context *context = NULL;
	struct ax7021b_qr_info info;
	struct ax7021b_qr_buffer buffer;
	struct qr_mainline_result result;
	void *mapped[AX7021B_QR_BUFFER_COUNT] = { };
	unsigned i, captured = 0, rejected = 0;
	int fd = -1, rc = 1, started = 0;

	fd = ax7021b_qr_open(device);
	if (fd < 0 || ax7021b_qr_get_info(fd, &info)) goto out;
	if (info.abi_version != AX7021B_QR_ABI_VERSION ||
	    info.pl_abi_version != AX7021B_QR_PL_ABI_VERSION ||
	    info.buffer_count != AX7021B_QR_BUFFER_COUNT) {
		errno = EPROTO;
		goto out;
	}
	for (i = 0; i < info.buffer_count; ++i) {
		mapped[i] = ax7021b_qr_map_buffer(fd, &info, i);
		if (mapped[i] == MAP_FAILED) goto out;
	}
	context = qr_mainline_create();
	if (!context || ax7021b_qr_start(fd)) goto out;
	started = 1;
	while (!interrupted && (!count || captured < count)) {
		int process_rc;
		if (ax7021b_qr_dequeue(fd, &buffer)) {
			if (errno == EINTR && interrupted) break;
			goto out;
		}
		process_rc = qr_mainline_process(context, fd, mapped[buffer.index],
						info.frame_bytes, buffer.sequence, &result);
		if (!process_rc)
			emit_result(context, &result);
		else {
			++rejected;
			fprintf(stderr, "frame %llu rejected: %s\n",
				(unsigned long long)buffer.sequence, strerror(errno));
		}
		if (ax7021b_qr_queue(fd, buffer.index)) goto out;
		++captured;
	}
	rc = rejected ? 1 : 0;
	if (rejected) errno = EBADMSG;
out:
	if (started) ax7021b_qr_stop(fd);
	qr_mainline_destroy(context);
	for (i = 0; i < AX7021B_QR_BUFFER_COUNT; ++i)
		if (mapped[i] && mapped[i] != MAP_FAILED)
			munmap(mapped[i], info.mmap_slot_bytes);
	if (fd >= 0) close(fd);
	return rc;
}

static void usage(const char *program)
{
	fprintf(stderr, "usage: %s --capture [count] [--device path]\n"
			"       %s --file gray8.raw [--width 1280 --height 720]\n"
			"       %s --init-camera [--trace-camera]\n", program, program, program);
}

int main(int argc, char **argv)
{
	const char *device = NULL, *file = NULL;
	unsigned capture = 0, width = 1280, height = 720;
	int do_capture = 0, init_camera = 0, trace = 0, i, rc;

	for (i = 1; i < argc; ++i) {
		if (!strcmp(argv[i], "--capture")) {
			do_capture = 1;
			if (i + 1 < argc && argv[i + 1][0] != '-') capture = strtoul(argv[++i], NULL, 0);
		} else if (!strcmp(argv[i], "--device") && i + 1 < argc) device = argv[++i];
		else if (!strcmp(argv[i], "--file") && i + 1 < argc) file = argv[++i];
		else if (!strcmp(argv[i], "--width") && i + 1 < argc) width = strtoul(argv[++i], NULL, 0);
		else if (!strcmp(argv[i], "--height") && i + 1 < argc) height = strtoul(argv[++i], NULL, 0);
		else if (!strcmp(argv[i], "--init-camera")) init_camera = 1;
		else if (!strcmp(argv[i], "--trace-camera")) trace = 1;
		else { usage(argv[0]); return 2; }
	}
	if (init_camera) {
		rc = ax7021b_qr_camera_init(NULL, NULL, trace);
		if (rc) perror("OV5640 initialization");
		if (!do_capture && !file) return rc ? 1 : 0;
	}
	signal(SIGINT, handle_signal);
	signal(SIGTERM, handle_signal);
	if (file) rc = process_file(file, width, height);
	else if (do_capture) rc = capture_frames(device, capture);
	else { usage(argv[0]); return 2; }
	if (rc) perror("qr-mainline");
	return rc ? 1 : 0;
}
