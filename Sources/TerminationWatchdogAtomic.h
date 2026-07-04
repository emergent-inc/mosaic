#ifndef MOSAIC_TERMINATION_WATCHDOG_ATOMIC_H
#define MOSAIC_TERMINATION_WATCHDOG_ATOMIC_H

#include <stdbool.h>
#include <stdatomic.h>

typedef struct {
    atomic_bool isArmed;
} MosaicTerminationWatchdogLatch;

MosaicTerminationWatchdogLatch MosaicTerminationWatchdogLatchMake(void);
bool MosaicTerminationWatchdogLatchClaim(MosaicTerminationWatchdogLatch *latch);

#endif
