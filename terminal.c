#include <pty.h>
#include <termios.h>
#include <unistd.h>
#include <poll.h>
#include <stdio.h>

#define BUFFER_SIZE 256

int main() {
    int master;

    if (forkpty(&master, NULL, NULL, NULL)) {
        struct pollfd fds[2] = {
            { .fd = master, .events = POLLIN },
            { .fd = STDIN_FILENO, .events = POLLIN },
        };

        char buffer[BUFFER_SIZE];
        size_t length;

        while (1) {
            poll(&fds[0], 2, 0);
            if (fds[1].revents & POLLIN != 0) {
                length = read(STDIN_FILENO, &buffer[0], BUFFER_SIZE);
                write(master, &buffer[0], length);
            }
            if (fds[0].revents & POLLIN != 0) {
                length = read(master, &buffer[0], BUFFER_SIZE);
                write(STDOUT_FILENO, &buffer[0], length);
            }
        }
    } else {
        execl("/usr/bin/python3", "python3", NULL);
        // execl("/bin/bash", "bash", NULL);
    }
}