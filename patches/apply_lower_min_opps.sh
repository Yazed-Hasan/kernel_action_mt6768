#!/usr/bin/env bash
# Apply lower min OPPs for G75 (lancelot) during GitHub Actions build.
# Little (LL): 500 -> 450 MHz
# Big (L):    850 -> 500 MHz (no-op if already 500, as on mt6768-s/shockwave)
set -euo pipefail

ROOT="${1:-.}"
OPP="$ROOT/drivers/misc/mediatek/base/power/cpufreq_v1/src/mach/mt6768/mtk_cpufreq_opp_table.h"
PV="$ROOT/drivers/misc/mediatek/base/power/cpufreq_v1/src/mach/mt6768/mtk_cpufreq_opp_pv_table.h"

if [[ ! -f "$OPP" || ! -f "$PV" ]]; then
  echo "ERROR: mt6768 OPP headers not found under $ROOT"
  exit 1
fi

echo "Patching G75 min OPPs: LL 500->450 MHz, L 850->500 MHz (if needed)"

python3 - "$OPP" "$PV" <<'PY'
import pathlib, re, sys

opp = pathlib.Path(sys.argv[1])
pv = pathlib.Path(sys.argv[2])

ot = opp.read_text()

# --- Little (LL) min: 500000 -> 450000 ---
ot2, n_ll = re.subn(
    r'(#define\s+CPU_DVFS_FREQ15_LL_G75\s+)500000(\s*/\*\s*KHz\s*\*/)',
    r'\g<1>450000\2',
    ot,
    count=1,
)
if n_ll == 0 and re.search(r'#define\s+CPU_DVFS_FREQ15_LL_G75\s+450000\b', ot):
    print('LL FREQ15 already 450000')
    ot2 = ot
elif n_ll != 1:
    raise SystemExit(f'LL FREQ15 replace failed (n={n_ll})')
else:
    print('LL FREQ15: 500000 -> 450000')

# --- Big (L) min: 850000 -> 500000 (optional / already done on -s/shockwave) ---
ot3, n_l = re.subn(
    r'(#define\s+CPU_DVFS_FREQ15_L_G75\s+)850000(\s*/\*\s*KHz\s*\*/)',
    r'\g<1>500000\2',
    ot2,
    count=1,
)
if n_l == 1:
    print('L FREQ15: 850000 -> 500000')
    ot2 = ot3
elif re.search(r'#define\s+CPU_DVFS_FREQ15_L_G75\s+500000\b', ot2):
    print('L FREQ15 already 500000 (skip)')
else:
    raise SystemExit('L FREQ15: expected 850000 or 500000, found neither')

# --- Method table: ensure last FP for L_G75 is FP(4,1) when at 500 MHz ---
m2 = re.search(r'(static struct mt_cpu_freq_method opp_tbl_method_L_G75\[\] = \{[\s\S]*?\};)', ot2)
if not m2:
    raise SystemExit('opp_tbl_method_L_G75 not found')
blk = m2.group(1)
# If last entry is still FP(2,...), bump to FP(4,...) for 500 MHz VCO
if re.search(r'FP\(2,\s*1\),\s*\};', blk):
    idx = blk.rfind('FP(2,')
    end = blk.find('),', idx)
    if idx < 0 or end < 0:
        raise SystemExit('Could not update last FP in L_G75 method table')
    blk2 = blk[:idx] + 'FP(4,\t1),' + blk[end + 2:]
    ot2 = ot2[:m2.start(1)] + blk2 + ot2[m2.end(1):]
    print('L method table: last FP(2) -> FP(4)')
else:
    print('L method table already ends with FP(4) (skip)')

opp.write_text(ot2)
print('Updated', opp)

# --- FY_G75Tbl ---
text = pv.read_text()
m = re.search(r'(static unsigned int FY_G75Tbl\[[\s\S]*?\};)', text)
if not m:
    raise SystemExit('FY_G75Tbl not found')
block = m.group(1)
parts = block.split('/* B */', 1)
if len(parts) != 2:
    raise SystemExit('FY_G75Tbl B marker missing')
ll, rest = parts

ll2, n1 = re.subn(r'\{ 500, 24, 4, 1 \}', '{ 450, 24, 4, 1 }', ll, count=1)
if n1 == 1:
    print('FY LL row: 500 -> 450')
elif '{ 450, 24, 4, 1 }' in ll:
    print('FY LL row already 450 (skip)')
    ll2 = ll
else:
    raise SystemExit(f'FY LL 500/450 row not found (n={n1})')

b_parts = rest.split('/* CCI */', 1)
if len(b_parts) != 2:
    raise SystemExit('FY_G75Tbl CCI marker missing')
b, cci = b_parts

# Old tree: last big row { 850, 28, 2, 1 } -> { 500, 28, 4, 1 }
# New tree (-s/shockwave): already { 500, 24, 4, 1 } or similar
b2, n2 = re.subn(r'\{ 850, 28, 2, 1 \}', '{ 500, 28, 4, 1 }', b, count=1)
if n2 == 1:
    print('FY B row: 850 -> 500')
elif re.search(r'\{ 500, \d+, \d+, 1 \}', b):
    print('FY B row already 500 (skip)')
    b2 = b
else:
    raise SystemExit(f'FY B 850/500 row not found (n={n2})')

new_block = ll2 + '/* B */' + b2 + '/* CCI */' + cci
text = text[:m.start(1)] + new_block + text[m.end(1):]
pv.write_text(text)
print('Updated', pv)

otv = opp.read_text()
pvv = pv.read_text()
assert re.search(r'CPU_DVFS_FREQ15_LL_G75\s+450000', otv)
assert re.search(r'CPU_DVFS_FREQ15_L_G75\s+500000', otv)
assert '{ 450, 24, 4, 1 }' in pvv
print('OK: G75 min OPPs patched')
PY

echo "Done."
