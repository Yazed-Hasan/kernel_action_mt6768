#!/usr/bin/env bash
# Apply lower min OPPs for G75 (lancelot) during GitHub Actions build.
# LL min: 500 -> 450 MHz | Big min: 850 -> 500 MHz
set -euo pipefail

ROOT="${1:-.}"
OPP="$ROOT/drivers/misc/mediatek/base/power/cpufreq_v1/src/mach/mt6768/mtk_cpufreq_opp_table.h"
PV="$ROOT/drivers/misc/mediatek/base/power/cpufreq_v1/src/mach/mt6768/mtk_cpufreq_opp_pv_table.h"

if [[ ! -f "$OPP" || ! -f "$PV" ]]; then
  echo "ERROR: mt6768 OPP headers not found under $ROOT"
  exit 1
fi

echo "Patching G75 min OPPs: LL 500->450 MHz, L 850->500 MHz"

python3 - "$OPP" "$PV" <<'PY'
import pathlib, re, sys

opp = pathlib.Path(sys.argv[1])
pv = pathlib.Path(sys.argv[2])

ot = opp.read_text()
ot2, n_ll = re.subn(
    r'(#define\s+CPU_DVFS_FREQ15_LL_G75\s+)500000(\s*/\*\s*KHz\s*\*/)',
    r'\g<1>450000\2',
    ot,
    count=1,
)
ot2, n_l = re.subn(
    r'(#define\s+CPU_DVFS_FREQ15_L_G75\s+)850000(\s*/\*\s*KHz\s*\*/)',
    r'\g<1>500000\2',
    ot2,
    count=1,
)
if n_ll != 1 or n_l != 1:
    raise SystemExit(f'FREQ15 define replace failed (LL={n_ll}, L={n_l})')

m2 = re.search(r'(static struct mt_cpu_freq_method opp_tbl_method_L_G75\[\] = \{[\s\S]*?\};)', ot2)
if not m2:
    raise SystemExit('opp_tbl_method_L_G75 not found')
blk = m2.group(1)
idx = blk.rfind('FP(2,')
if idx < 0:
    raise SystemExit('No FP(2,...) in L_G75 method table')
end = blk.find('),', idx)
if end < 0:
    raise SystemExit('Malformed FP entry')
# replace FP(2,...) including the trailing "),'"
blk2 = blk[:idx] + 'FP(4,\t1),' + blk[end + 2:]
ot2 = ot2[:m2.start(1)] + blk2 + ot2[m2.end(1):]
opp.write_text(ot2)
print('Updated', opp)

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
if n1 != 1:
    raise SystemExit(f'LL 500 row replace failed ({n1})')
b_parts = rest.split('/* CCI */', 1)
if len(b_parts) != 2:
    raise SystemExit('FY_G75Tbl CCI marker missing')
b, cci = b_parts
b2, n2 = re.subn(r'\{ 850, 28, 2, 1 \}', '{ 500, 28, 4, 1 }', b, count=1)
if n2 != 1:
    raise SystemExit(f'B 850 row replace failed ({n2})')
new_block = ll2 + '/* B */' + b2 + '/* CCI */' + cci
text = text[:m.start(1)] + new_block + text[m.end(1):]
pv.write_text(text)
print('Updated', pv)

otv = opp.read_text()
pvv = pv.read_text()
assert re.search(r'CPU_DVFS_FREQ15_LL_G75\s+450000', otv)
assert re.search(r'CPU_DVFS_FREQ15_L_G75\s+500000', otv)
assert '{ 450, 24, 4, 1 }' in pvv
assert '{ 500, 28, 4, 1 }' in pvv
# ensure no double paren on last L_G75 FP
m3 = re.search(r'opp_tbl_method_L_G75\[\] = \{([\s\S]*?)\};', otv)
assert 'FP(4,\t1)),' not in m3.group(1)
assert m3.group(1).rstrip().endswith('FP(4,\t1),') or 'FP(4,\t1),' in m3.group(1)
print('OK: G75 min OPPs patched')
PY

echo "Done."
