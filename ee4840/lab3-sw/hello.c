/*
 * Userspace program for VGA Air Hockey
 * Controls puck position using mouse input (evdev interface)
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <linux/input.h>
#include "vga_ball.h"

/* Ice area bounds (wall + puck radius = 10+4+10 = 24) */
#define X_MIN 24
#define X_MAX 615
#define Y_MIN 24
#define Y_MAX 455

static int vga_ball_fd;

static void set_puck_pos(unsigned short x, unsigned short y)
{
    vga_ball_arg_t vla;
    vla.pos.x = x;
    vla.pos.y = y;
    if (ioctl(vga_ball_fd, VGA_BALL_WRITE_PUCK, &vla))
        perror("ioctl(VGA_BALL_WRITE_PUCK) failed");
}

static int clamp(int val, int lo, int hi)
{
    if (val < lo) return lo;
    if (val > hi) return hi;
    return val;
}

int main(int argc, char *argv[])
{
    static const char dev_vga[] = "/dev/vga_ball";
    const char *dev_mouse = (argc > 1) ? argv[1] : "/dev/input/event0";
    struct input_event ev;
    int mouse_fd;
    int x = 320, y = 240;

    vga_ball_fd = open(dev_vga, O_RDWR);
    if (vga_ball_fd == -1) {
        fprintf(stderr, "could not open %s\n", dev_vga);
        return -1;
    }

    mouse_fd = open(dev_mouse, O_RDONLY);
    if (mouse_fd == -1) {
        fprintf(stderr, "could not open %s\n", dev_mouse);
        return -1;
    }

    printf("Air Hockey started — move mouse to control puck\n");
    printf("Using mouse device: %s\n", dev_mouse);
    set_puck_pos(x, y);

    while (read(mouse_fd, &ev, sizeof(ev)) == sizeof(ev)) {
        if (ev.type == EV_REL) {
            if (ev.code == REL_X)
                x = clamp(x + ev.value, X_MIN, X_MAX);
            else if (ev.code == REL_Y)
                y = clamp(y + ev.value, Y_MIN, Y_MAX);
            set_puck_pos(x, y);
        }
    }

    close(mouse_fd);
    close(vga_ball_fd);
    return 0;
}
