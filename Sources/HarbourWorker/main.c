#define _POSIX_C_SOURCE 200809L
#include <sys/types.h>
#include <sys/wait.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static volatile sig_atomic_t stopping = 0;
static void stop_handler(int sig) { (void)sig; stopping = 1; }
int main(int argc, char **argv) {
    if (argc < 2) return 125;
    pid_t parent = getppid();
    (void)setsid();
    (void)setpgid(0, 0);
    if (getpgrp() != getpid()) return 125;
    struct sigaction action = {0};
    action.sa_handler = stop_handler;
    sigemptyset(&action.sa_mask);
    sigaction(SIGTERM, &action, NULL);
    sigaction(SIGINT, &action, NULL);
    pid_t child = fork();
    if (child < 0) return 125;
    if (child == 0) {
        signal(SIGTERM, SIG_DFL); signal(SIGINT, SIG_DFL);
        if (setpgid(0, 0) < 0) _exit(125);
        execv(argv[1], &argv[1]);
        perror("HarbourWorker execv"); _exit(127);
    }
    (void)setpgid(child, child);
    int ticks = 0, sent = 0;
    for (;;) {
        if (getppid() != parent) stopping = 1;
        if (stopping) {
            if (!sent) { kill(-child, SIGTERM); sent = 1; }
            if (++ticks >= 20) kill(-child, SIGKILL);
        }
        siginfo_t info = {0};
        // Keep the child as a zombie until descendants are stopped. Its PID
        // cannot be reused as a different process group during this cleanup.
        if (waitid(P_PID, child, &info, WEXITED | WNOHANG | WNOWAIT) == 0 && info.si_pid == child) {
            kill(-child, SIGKILL);
            int status = 0;
            while (waitpid(child, &status, 0) < 0 && errno == EINTR) {}
            if (stopping) return 130;
            return WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
        }
        struct timespec pause = {0, 100000000};
        nanosleep(&pause, NULL);
    }
}
