/* OV5640 初始化（SCCB over AXI IIC）。 */
#ifndef CAMERA_H
#define CAMERA_H

/* 初始化 AXI IIC、读传感器 ID、下发 ov5640_config.h 里的寄存器表。
 * 返回 XST_FAILURE 表示某一步失败；调用方只打 WARNING，不中断启动。 */
int camera_init(void);

#endif
