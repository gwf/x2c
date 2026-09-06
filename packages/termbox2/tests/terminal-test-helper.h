/* terminal-test-helper.h -- deterministic tty and signal test support. */

#pragma once

int termbox_test_install_winch(void);
int termbox_test_winch_restored(void);
int termbox_test_restore_winch(void);
int termbox_test_snapshot_tty(void);
int termbox_test_tty_restored(void);
int termbox_test_arm_interrupt(int milliseconds);
int termbox_test_interrupt_fired(void);
int termbox_test_arm_repeating_interrupt(int milliseconds);
int termbox_test_stop_interrupts(void);
int termbox_test_interrupt_count(void);
long long termbox_test_monotonic_ms(void);
