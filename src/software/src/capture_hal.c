#define _GNU_SOURCE
#include "qr_mainline_linux.h"

#include <errno.h>
#include <fcntl.h>
#include <linux/i2c-dev.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#include "ov5640_config.h"

#define OV5640_ADDRESS 0x3c

int ax7021b_qr_open(const char *path)
{
	return open(path ? path : "/dev/" AX7021B_QR_DEVICE_NAME, O_RDWR | O_CLOEXEC);
}

int ax7021b_qr_get_info(int fd, struct ax7021b_qr_info *info)
{
	return ioctl(fd, AX7021B_QR_IOC_GET_INFO, info);
}

void *ax7021b_qr_map_buffer(int fd, const struct ax7021b_qr_info *info, uint32_t index)
{
	off_t offset;
	if (!info || index >= info->buffer_count) {
		errno = EINVAL;
		return MAP_FAILED;
	}
	offset = (off_t)index * info->mmap_slot_bytes;
	return mmap(NULL, info->mmap_slot_bytes, PROT_READ, MAP_SHARED, fd, offset);
}

int ax7021b_qr_start(int fd) { return ioctl(fd, AX7021B_QR_IOC_START); }
int ax7021b_qr_stop(int fd) { return ioctl(fd, AX7021B_QR_IOC_STOP); }
int ax7021b_qr_dequeue(int fd, struct ax7021b_qr_buffer *buffer)
{ return ioctl(fd, AX7021B_QR_IOC_DEQUEUE, buffer); }
int ax7021b_qr_get_counters(int fd, struct ax7021b_qr_counters *counters)
{ return ioctl(fd, AX7021B_QR_IOC_GET_COUNTERS, counters); }

int ax7021b_qr_queue(int fd, uint32_t index)
{
	struct ax7021b_qr_buffer buffer = { .index = index };
	return ioctl(fd, AX7021B_QR_IOC_QUEUE, &buffer);
}

static int camera_adapter(const char *sysfs_root)
{
	char path[PATH_MAX], target[PATH_MAX], name[128];
	int index;
	for (index = 0; index < 128; ++index) {
		FILE *stream;
		/* Recent kernels expose adapters under the I2C bus, not the
		 * removed i2c-adapter class. Match the OF address, never bus order. */
		snprintf(path, sizeof(path), "%s/bus/i2c/devices/i2c-%d/of_node",
			 sysfs_root, index);
		if (realpath(path, target) &&
		    (strstr(target, "camera_iic") || strstr(target, "41600000")))
			return index;
		snprintf(path, sizeof(path), "%s/class/i2c-adapter/i2c-%d/device/of_node",
			 sysfs_root, index);
		if (realpath(path, target) &&
		    (strstr(target, "camera_iic") || strstr(target, "41600000")))
			return index;
		snprintf(path, sizeof(path), "%s/class/i2c-adapter/i2c-%d/name",
			 sysfs_root, index);
		stream = fopen(path, "r");
		if (!stream)
			continue;
		name[0] = '\0';
		if (fgets(name, sizeof(name), stream) &&
		    (strstr(name, "camera") || strstr(name, "41600000"))) {
			fclose(stream);
			return index;
		}
		fclose(stream);
	}
	errno = ENODEV;
	return -1;
}

static int i2c_write_register(int fd, uint16_t reg, uint8_t value)
{
	uint8_t bytes[3] = { (uint8_t)(reg >> 8), (uint8_t)reg, value };
	return write(fd, bytes, sizeof(bytes)) == (ssize_t)sizeof(bytes) ? 0 : -1;
}

static int i2c_read_register(int fd, uint16_t reg, uint8_t *value)
{
	uint8_t address[2] = { (uint8_t)(reg >> 8), (uint8_t)reg };
	if (write(fd, address, sizeof(address)) != (ssize_t)sizeof(address))
		return -1;
	return read(fd, value, 1) == 1 ? 0 : -1;
}

int ax7021b_qr_camera_init(const char *sysfs_root, const char *dev_root, int trace)
{
	char path[PATH_MAX];
	uint8_t high, low;
	int adapter, fd, sensor_fd, i;

	if (!sysfs_root) sysfs_root = "/sys";
	if (!dev_root) dev_root = "/dev";
	adapter = camera_adapter(sysfs_root);
	if (adapter < 0)
		return -1;
	snprintf(path, sizeof(path), "%s/i2c-%d", dev_root, adapter);
	fd = open(path, O_RDWR | O_CLOEXEC);
	if (fd < 0)
		return -1;
	/* Own the capture device during sensor programming. Reinitialization of
	 * an already streaming OV5640 needs a hardware reset before the SCCB table;
	 * otherwise switching its clock source can leave subsequent writes NACKed.
	 */
	snprintf(path, sizeof(path), "%s/" AX7021B_QR_DEVICE_NAME, dev_root);
	sensor_fd = open(path, O_RDWR | O_CLOEXEC);
	if (sensor_fd < 0) {
		close(fd);
		return -1;
	}
	if (ioctl(sensor_fd, AX7021B_QR_IOC_RESET_SENSOR))
		goto fail;
	if (ioctl(fd, I2C_SLAVE, OV5640_ADDRESS) < 0 ||
	    i2c_read_register(fd, 0x300a, &high) ||
	    i2c_read_register(fd, 0x300b, &low))
		goto fail;
	if ((((unsigned)high << 8) | low) != 0x5640) {
		errno = ENODEV;
		goto fail;
	}
	for (i = 0; g_ov5640_rgb565[i].reg != OV5640_REG_END; ++i) {
		if (g_ov5640_rgb565[i].reg == OV5640_REG_DELAY) {
			usleep((useconds_t)g_ov5640_rgb565[i].value * 1000U);
			continue;
		}
		if (trace)
			fprintf(stderr, "camera[%d] %04x=%02x\n", i,
				g_ov5640_rgb565[i].reg, g_ov5640_rgb565[i].value);
		if (i2c_write_register(fd, g_ov5640_rgb565[i].reg,
				       g_ov5640_rgb565[i].value))
			goto fail;
	}
	close(fd);
	close(sensor_fd);
	return 0;
fail:
	close(fd);
	close(sensor_fd);
	return -1;
}
