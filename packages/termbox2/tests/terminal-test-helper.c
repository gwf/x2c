/* terminal-test-helper.c -- deterministic tty and signal test support. */

#include "terminal-test-helper.h"

#include <fcntl.h>
#include <signal.h>
#include <string.h>
#include <sys/time.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

static struct sigaction saved_winch;
static struct sigaction installed_winch;
static int have_saved_winch;
static int tty_fd = -1;
static struct termios saved_tty;
static volatile sig_atomic_t interrupt_fired;
static volatile sig_atomic_t interrupt_count;

static void test_winch_handler(int signal_number) {
  (void) signal_number;
}

static void test_alarm_handler(int signal_number) {
  (void) signal_number;
  interrupt_fired = 1;
  interrupt_count++;
}

int termbox_test_install_winch(void) {
  if (sigaction(SIGWINCH, NULL, &saved_winch) != 0) return -1;
  have_saved_winch = 1;
  memset(&installed_winch, 0, sizeof(installed_winch));
  installed_winch.sa_handler = test_winch_handler;
  installed_winch.sa_flags = SA_RESTART;
  sigemptyset(&installed_winch.sa_mask);
  sigaddset(&installed_winch.sa_mask, SIGUSR1);
  return sigaction(SIGWINCH, &installed_winch, NULL);
}

int termbox_test_winch_restored(void) {
  struct sigaction current;
  if (sigaction(SIGWINCH, NULL, &current) != 0) return 0;
  if (current.sa_handler != installed_winch.sa_handler) return 0;
  if ((current.sa_flags & SA_RESTART) !=
      (installed_winch.sa_flags & SA_RESTART)) return 0;
  return sigismember(&current.sa_mask, SIGUSR1) == 1;
}

int termbox_test_restore_winch(void) {
  if (!have_saved_winch) return 0;
  have_saved_winch = 0;
  return sigaction(SIGWINCH, &saved_winch, NULL);
}

int termbox_test_snapshot_tty(void) {
  if (tty_fd >= 0) close(tty_fd);
  tty_fd = open("/dev/tty", O_RDWR);
  if (tty_fd < 0) return -1;
  return tcgetattr(tty_fd, &saved_tty);
}

int termbox_test_tty_restored(void) {
  struct termios current;
  if (tty_fd < 0 || tcgetattr(tty_fd, &current) != 0) return 0;
  int restored = current.c_iflag == saved_tty.c_iflag &&
    current.c_oflag == saved_tty.c_oflag &&
    current.c_cflag == saved_tty.c_cflag &&
    current.c_lflag == saved_tty.c_lflag &&
    cfgetispeed(&current) == cfgetispeed(&saved_tty) &&
    cfgetospeed(&current) == cfgetospeed(&saved_tty) &&
    !memcmp(current.c_cc, saved_tty.c_cc, sizeof(current.c_cc));
  close(tty_fd);
  tty_fd = -1;
  return restored;
}

int termbox_test_arm_interrupt(int milliseconds) {
  struct sigaction action;
  memset(&action, 0, sizeof(action));
  action.sa_handler = test_alarm_handler;
  sigemptyset(&action.sa_mask);
  if (sigaction(SIGALRM, &action, NULL) != 0) return -1;

  interrupt_fired = 0;
  interrupt_count = 0;
  struct itimerval timer;
  memset(&timer, 0, sizeof(timer));
  timer.it_value.tv_sec = milliseconds / 1000;
  timer.it_value.tv_usec = (milliseconds % 1000) * 1000;
  return setitimer(ITIMER_REAL, &timer, NULL);
}

int termbox_test_interrupt_fired(void) {
  return interrupt_fired != 0;
}

int termbox_test_arm_repeating_interrupt(int milliseconds) {
  if (termbox_test_arm_interrupt(milliseconds) != 0) return -1;
  struct itimerval timer;
  memset(&timer, 0, sizeof(timer));
  timer.it_value.tv_sec = milliseconds / 1000;
  timer.it_value.tv_usec = (milliseconds % 1000) * 1000;
  timer.it_interval = timer.it_value;
  return setitimer(ITIMER_REAL, &timer, NULL);
}

int termbox_test_stop_interrupts(void) {
  struct itimerval timer;
  memset(&timer, 0, sizeof(timer));
  return setitimer(ITIMER_REAL, &timer, NULL);
}

int termbox_test_interrupt_count(void) {
  return interrupt_count;
}

long long termbox_test_monotonic_ms(void) {
  struct timespec now;
  if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) return -1;
  return (long long) now.tv_sec * 1000LL + now.tv_nsec / 1000000LL;
}
