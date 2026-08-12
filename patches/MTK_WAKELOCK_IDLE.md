# MT662x / WMT PSM wakelock deepfix

When `FIX_MTK_WAKELOCK=true`, the build runs `patches/apply_mtk_wakelock_idle.sh` on the cloned kernel.

## What it changes

1. **`MT662x` wakelock** (`psm_core.c`): `osal_wake_lock` → `osal_wake_lock_timeout(..., 500ms)` via `__pm_wakeup_event`.
   - Idle can no longer hold the CPU awake forever if PSM sticks.
   - Active Wi‑Fi/BT traffic re-arms the timeout on each wake path (daily use stays OK).

2. **High-traffic idle→sleep**: `STP_PSM_IDLE_TIME_SLEEP_1000` **1000 → 500** ms (returns to sleep sooner after bursts).

3. Adds `osal_wake_lock_timeout()` in WMT `osal.c` / `osal.h`.

## What it does *not* change

- Normal idle sleep timer stays **30 ms**.
- Does not disable Wi‑Fi/BT or kill apps.
- Does not touch WLAN driver wake locks (already off when `CFG_ENABLE_WAKE_LOCK=0`).

## After flash

Compare kernel wakelock dump: `MT662x` total time / hold duration should drop in quiet idle while streaming/calls still work.
