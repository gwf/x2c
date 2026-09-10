/*  membytes.c -- Implementation of the benchmark memory samples.

    task_info is the only interface reporting the physical footprint, and
    it is cheap enough to call between training steps. A failing call
    returns 0 so the sample records as missing instead of wrong.
*/
#include "membytes.h"

#include <mach/mach.h>
#include <mach/mach_init.h>
#include <mach/task_info.h>

static int xb_vm_info(task_vm_info_data_t *info) {
  mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
  return task_info(mach_task_self(), TASK_VM_INFO, (task_info_t) info,
                   &count) == KERN_SUCCESS;
}

static int xb_basic_info(mach_task_basic_info_data_t *info) {
  mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
  return task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t) info,
                   &count) == KERN_SUCCESS;
}

uint64_t xb_footprint(void) {
  task_vm_info_data_t info;
  return xb_vm_info(&info) ? (uint64_t) info.phys_footprint : 0;
}

uint64_t xb_footprint_peak(void) {
  task_vm_info_data_t info;
  return xb_vm_info(&info) ? (uint64_t) info.ledger_phys_footprint_peak : 0;
}

uint64_t xb_resident(void) {
  mach_task_basic_info_data_t info;
  return xb_basic_info(&info) ? (uint64_t) info.resident_size : 0;
}

uint64_t xb_resident_peak(void) {
  mach_task_basic_info_data_t info;
  return xb_basic_info(&info) ? (uint64_t) info.resident_size_max : 0;
}
