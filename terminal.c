#include <pty.h>
#include <unistd.h>
#include <poll.h>
#include <stdlib.h>
#include <errno.h>

#define BUFFER_SIZE 256

int main(int argc, char **argv) {
    int master;

    if (forkpty(&master, NULL, NULL, NULL)) {
        struct pollfd fds[2] = {
            { .fd = master, .events = POLLIN },
            { .fd = STDIN_FILENO, .events = POLLIN },
        };

        char buffer[BUFFER_SIZE];
        size_t length;

        while (1) {
            poll(&fds[0], 2, -1);
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
        setenv("TERM", "xterm-256color", 1);
        execvp(argv[1], &argv[1]);
        return errno;
    }
}