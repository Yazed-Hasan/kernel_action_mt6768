#!/usr/bin/env bash
# Deep kernel fix: MT662x (WMT PSM) wakelock idle drain.
# - Keep normal behavior under traffic (daily use)
# - Prevent indefinite MT662x hold when the chip should sleep
# - Shorten high-traffic idle→sleep from 1000ms → 500ms
set -euo pipefail

ROOT="${1:-.}"
PSM_H="$ROOT/drivers/misc/mediatek/connectivity/wmt_drv/common_main/core/include/psm_core.h"
PSM_C="$ROOT/drivers/misc/mediatek/connectivity/wmt_drv/common_main/core/psm_core.c"
OSAL_H="$ROOT/drivers/misc/mediatek/connectivity/wmt_drv/common_main/linux/include/osal.h"
OSAL_C="$ROOT/drivers/misc/mediatek/connectivity/wmt_drv/common_main/linux/osal.c"

for f in "$PSM_H" "$PSM_C" "$OSAL_H" "$OSAL_C"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: missing $f"
    exit 1
  fi
done

echo "Patching MTK WMT PSM MT662x wakelock (idle-friendly, traffic-safe)"

python3 - "$PSM_H" "$PSM_C" "$OSAL_H" "$OSAL_C" <<'PY'
import pathlib, re, sys

psm_h, psm_c, osal_h, osal_c = map(pathlib.Path, sys.argv[1:])

# --- psm_core.h: faster return-to-sleep after bursts + wakelock timeout ---
h = psm_h.read_text()
orig_h = h

if 'STP_PSM_WAKELOCK_TIMEOUT_MS' not in h:
    h = h.replace(
        '#define STP_PSM_IDLE_TIME_SLEEP_1000           1000	/* for high speed transmission e.g. BT OPP*/',
        '#define STP_PSM_IDLE_TIME_SLEEP_1000           500	/* was 1000: faster idle after bursts */\n'
        '#define STP_PSM_WAKELOCK_TIMEOUT_MS            500	/* MT662x: auto-relax; traffic refreshes */',
    )
else:
    h = re.sub(
        r'#define\s+STP_PSM_IDLE_TIME_SLEEP_1000\s+\d+',
        '#define STP_PSM_IDLE_TIME_SLEEP_1000           500',
        h,
        count=1,
    )
    h = re.sub(
        r'#define\s+STP_PSM_WAKELOCK_TIMEOUT_MS\s+\d+',
        '#define STP_PSM_WAKELOCK_TIMEOUT_MS            500',
        h,
        count=1,
    )

if 'STP_PSM_WAKELOCK_TIMEOUT_MS' not in h:
    raise SystemExit('Failed to add STP_PSM_WAKELOCK_TIMEOUT_MS')
if h != orig_h:
    psm_h.write_text(h)
    print('Updated', psm_h)
else:
    print('psm_core.h already patched (or matched)')

# --- osal.h: declare timeout API ---
oh = osal_h.read_text()
if 'osal_wake_lock_timeout' not in oh:
    oh = oh.replace(
        'INT32 osal_wake_lock(P_OSAL_WAKE_LOCK plock);',
        'INT32 osal_wake_lock(P_OSAL_WAKE_LOCK plock);\n'
        'INT32 osal_wake_lock_timeout(P_OSAL_WAKE_LOCK plock, UINT32 msec);',
    )
    if 'osal_wake_lock_timeout' not in oh:
        raise SystemExit('Failed to patch osal.h')
    osal_h.write_text(oh)
    print('Updated', osal_h)
else:
    print('osal.h already has osal_wake_lock_timeout')

# --- osal.c: implement via __pm_wakeup_event ---
oc = osal_c.read_text()
if 'osal_wake_lock_timeout' not in oc:
    marker = 'INT32 osal_wake_unlock(P_OSAL_WAKE_LOCK pLock)\n{'
    if marker not in oc:
        raise SystemExit('osal_wake_unlock marker not found')
    impl = '''INT32 osal_wake_lock_timeout(P_OSAL_WAKE_LOCK pLock, UINT32 msec)
{
	if (!pLock)
		return -1;

	/* Timed wake: idle cannot hold MT662x forever; active traffic re-arms. */
	if (pLock->init_flag == 1)
		__pm_wakeup_event(pLock->wake_lock, msec);
	else
		pr_info("%s: wake_lock is not initialized!\\n", __func__);

	return 0;
}

'''
    oc = oc.replace(marker, impl + marker, 1)
    osal_c.write_text(oc)
    print('Updated', osal_c)
else:
    print('osal.c already has osal_wake_lock_timeout')

# --- psm_core.c: use timed lock for MT662x only ---
pc = psm_c.read_text()
orig = pc

# Replace osal_wake_lock(&stp_psm->wake_lock) with timeout variant
pc2, n = re.subn(
    r'osal_wake_lock\(\s*&stp_psm->wake_lock\s*\)',
    'osal_wake_lock_timeout(&stp_psm->wake_lock, STP_PSM_WAKELOCK_TIMEOUT_MS)',
    pc,
)
if n < 1 and 'osal_wake_lock_timeout(&stp_psm->wake_lock' not in pc:
    raise SystemExit(f'psm_core.c: expected osal_wake_lock(&stp_psm->wake_lock) replacements, got {n}')
print(f'psm_core.c: wake_lock → timeout replacements: {n}')

if pc2 != pc:
    psm_c.write_text(pc2)
    print('Updated', psm_c)
else:
    print('psm_core.c already using timeout API')

# Verify
pcv = psm_c.read_text()
assert 'osal_wake_lock_timeout(&stp_psm->wake_lock, STP_PSM_WAKELOCK_TIMEOUT_MS)' in pcv
assert 'STP_PSM_WAKELOCK_TIMEOUT_MS' in psm_h.read_text()
assert 'osal_wake_lock_timeout' in osal_c.read_text()
print('OK: MT662x timed wakelock + faster post-burst sleep')
PY

echo "Done."
