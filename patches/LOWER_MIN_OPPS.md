# Lower G75 min OPPs

When `LOWER_MIN_OPPS=true` in `config.env`, the build applies `patches/apply_lower_min_opps.sh` to the cloned kernel.

## What it changes (CPU_LEVEL_6 / G75 — matches your lancelot ShockwaveKernel)

| Cluster | Old min | New min |
|---------|---------|---------|
| Little (cpu0–5) | 500 MHz | **450 MHz** |
| Big (cpu6–7) | 850 MHz | **500 MHz** |

Files touched in kernel source:
- `drivers/misc/mediatek/base/power/cpufreq_v1/src/mach/mt6768/mtk_cpufreq_opp_table.h`
- `drivers/misc/mediatek/base/power/cpufreq_v1/src/mach/mt6768/mtk_cpufreq_opp_pv_table.h`

## After flash

Confirm:
```sh
cat /sys/devices/system/cpu/cpufreq/policy0/scaling_available_frequencies
cat /sys/devices/system/cpu/cpufreq/policy6/scaling_available_frequencies
```

You should see `450000` on policy0 and `500000` on policy6. Then set mins (or use the Magisk MinFreq module):
```sh
echo 450000 > /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq
echo 500000 > /sys/devices/system/cpu/cpufreq/policy6/scaling_min_freq
```

## Risk

Untested PLL/voltage corner for these new steps. Keep a stock AnyKernel3 zip handy. If soft-brick: flash previous kernel from recovery/fastboot.
