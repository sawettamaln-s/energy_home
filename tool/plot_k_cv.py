# plot_k_cv.py
#
# วาดกราฟผลทดสอบค่า k (EnergyForecaster.priorWeightDays) จากไฟล์ CSV ที่
# tool/backtest_cycle_k_cv.dart --csv เขียนไว้ (base/bkk/upc × seed 1-5)
#   รูปที่ 1 k_cv_mape_curve.png  : MAPE ตามค่า k เฉลี่ย 5 seed
#   รูปที่ 2 k_cv_diff_vs_k5.png  : MAPE(k) - MAPE(5) พร้อมช่วง 95% (bootstrap) ช่วง k = 2-10
#   รูปที่ 3 k_cv_mape_by_day.png : MAPE แยกตามวันที่จด (ข้อมูลเดิม) ของ k = 0, 5, 21 และการทาย
#                                  เท่ารอบก่อน จาก *_days_seed*.csv (--days-csv)
# ใช้ฟอนต์ IBM Plex Sans Thai จาก assets/fonts ต้องมี matplotlib
#
# วิธีใช้: python tool/plot_k_cv.py <โฟลเดอร์ผล> <assets/fonts> <โฟลเดอร์ปลายทาง>
#   เช่น  python tool/plot_k_cv.py docs/k_cv assets/fonts docs/k_cv

import csv
import os
import sys

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib import font_manager

RES = sys.argv[1]      # โฟลเดอร์ผล (docs/k_cv)
FONTS = sys.argv[2]    # assets/fonts
OUT = sys.argv[3]      # โฟลเดอร์ปลายทาง

for f in ('IBMPlexSansThai-Regular.ttf', 'IBMPlexSansThai-SemiBold.ttf'):
    font_manager.fontManager.addfont(os.path.join(FONTS, f))
plt.rcParams['font.family'] = 'IBM Plex Sans Thai'

INK, INK2, MUTED, GRID, SURF = '#0b0b0b', '#52514e', '#8a8984', '#e6e5e1', '#ffffff'
SETS = [
    ('base', 'ข้อมูลเดิม (RECON-SL)', '#2a78d6', 'o', '-'),
    ('bkk', 'ปรับฤดูกาลไทย กรุงเทพ', '#eb6834', 's', '--'),
    ('upc', 'ปรับฤดูกาลไทย ต่างจังหวัด', '#1baf7a', '^', ':'),
]
SEEDS = [1, 2, 3, 4, 5]


def load(key):
    rows = {s: list(csv.DictReader(open(os.path.join(RES, f'{key}_seed{s}.csv'), encoding='utf-8'))) for s in SEEDS}
    ks = [float(r['k']) for r in rows[1]]
    avg = lambda col: [sum(float(rows[s][i][col]) for s in SEEDS) / len(SEEDS) for i in range(len(ks))]
    return ks, avg('mape'), avg('diff_mean'), avg('diff_lo'), avg('diff_hi')


data = {key: load(key) for key, *_ in SETS}


def style(ax):
    ax.set_facecolor(SURF)
    for side in ('top', 'right'):
        ax.spines[side].set_visible(False)
    for side in ('left', 'bottom'):
        ax.spines[side].set_color(GRID)
    ax.tick_params(colors=INK2, labelsize=10, length=0, pad=6)
    ax.grid(axis='y', color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)


# ---------- รูปที่ 1: MAPE ของแต่ละ k ----------
fig, ax = plt.subplots(figsize=(9, 5.2), dpi=200, facecolor=SURF)
style(ax)
ax.axvline(5, color=MUTED, linewidth=1, linestyle=(0, (4, 3)), zorder=1)
ax.text(5.25, 10.66, 'แอปใช้ k = 5', color=INK2, fontsize=10, va='top')
mins = {}
for key, label, color, marker, ls in SETS:
    ks, mape, *_ = data[key]
    ax.plot(ks, mape, color=color, linewidth=2, linestyle=ls, zorder=3)
    ax.plot(ks, mape, linestyle='none', marker=marker, markersize=6, color=color,
            markeredgecolor=SURF, markeredgewidth=1.5, zorder=4, label=label)
    bi = min(range(len(ks)), key=lambda i: mape[i])
    ax.plot(ks[bi], mape[bi], marker=marker, markersize=11, color=color,
            markeredgecolor=SURF, markeredgewidth=2, zorder=5)
    mins[key] = (ks[bi], mape[bi])
    ax.annotate(label, (ks[-1], mape[-1]), xytext=(8, 0), textcoords='offset points',
                va='center', fontsize=9.5, color=INK2)
bk, bm = mins['base']
ax.annotate(f'ต่ำสุด k = {bk:.0f}  ({bm:.2f}%)', (bk, bm), xytext=(0, -18), textcoords='offset points',
            ha='center', fontsize=9.5, color=INK)
(tk, tb), (_, tu) = mins['bkk'], mins['upc']
ax.annotate(f'ต่ำสุด k = {tk:.0f}  (กรุงเทพ {tb:.2f}% · ต่างจังหวัด {tu:.2f}%)', (tk, tb), xytext=(0, -20),
            textcoords='offset points', ha='left', fontsize=9.5, color=INK)
ax.set_xlim(-0.8, 27.5)
ax.set_xticks([0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 14, 21])
ax.set_ylim(8.8, 10.7)
ax.set_xlabel('k (จำนวนวันที่ถ่วงด้วยบิลรอบก่อน)', color=INK2, fontsize=10.5, labelpad=8)
ax.set_ylabel('MAPE (%)  ยิ่งต่ำยิ่งแม่น', color=INK2, fontsize=10.5, labelpad=8)
fig.suptitle('ความคลาดเคลื่อนของยอดคาดการณ์สิ้นรอบบิลตามค่า k', x=0.07, ha='left',
             fontsize=14, fontweight='semibold', color=INK)
ax.set_title('เฉลี่ย 5 seed · มิเตอร์จริงราว 2,100 บ้าน 34,000 รอบบิล (RECON-SL, DOI 10.21227/n1dk-q860)',
             loc='left', fontsize=9.5, color=INK2, pad=10)
ax.legend(loc='upper center', bbox_to_anchor=(0.5, -0.2), ncol=3, frameon=False, fontsize=9.5,
          labelcolor=INK2, handletextpad=0.4, columnspacing=1.6, markerscale=1.4)
fig.tight_layout()
fig.savefig(os.path.join(OUT, 'k_cv_mape_curve.png'), facecolor=SURF)
plt.close(fig)

# ---------- รูปที่ 2: ส่วนต่างเทียบ k = 5 พร้อมช่วง 95% (ซูมช่วง 2-10) ----------
fig, ax = plt.subplots(figsize=(9, 5.2), dpi=200, facecolor=SURF)
style(ax)
ax.axhline(0, color=INK2, linewidth=1, zorder=2)
ax.text(10.35, 0.003, 'เท่ากับ k = 5', color=INK2, fontsize=9, va='bottom', ha='right')
zoom = [2, 3, 4, 5, 6, 7, 8, 10]
offsets = {'base': -0.18, 'bkk': 0, 'upc': 0.18}
for key, label, color, marker, ls in SETS:
    ks, _, mean, lo, hi = data[key]
    idx = [ks.index(float(k)) for k in zoom]
    xs = [ks[i] + offsets[key] for i in idx]
    m = [mean[i] for i in idx]
    ax.errorbar(xs, m, yerr=[[m[j] - lo[i] for j, i in enumerate(idx)], [hi[i] - m[j] for j, i in enumerate(idx)]],
                fmt='none', ecolor=color, elinewidth=1.6, capsize=3, capthick=1.6, zorder=3)
    ax.plot(xs, m, color=color, linewidth=1.4, linestyle=ls, zorder=3, alpha=0.9)
    ax.plot(xs, m, linestyle='none', marker=marker, markersize=6.5, color=color,
            markeredgecolor=SURF, markeredgewidth=1.5, zorder=4, label=label)
ax.set_xticks(zoom)
ax.set_xlim(1.4, 10.6)
ax.set_xlabel('k (จำนวนวันที่ถ่วงด้วยบิลรอบก่อน)', color=INK2, fontsize=10.5, labelpad=8)
ax.set_ylabel('MAPE(k) − MAPE(5)  (จุดเปอร์เซ็นต์)', color=INK2, fontsize=10.5, labelpad=8)
fig.suptitle('ถ้าใช้ค่า k อื่นแทน 5 ความคลาดเคลื่อนเปลี่ยนไปเท่าไร', x=0.07, ha='left',
             fontsize=14, fontweight='semibold', color=INK)
ax.set_title('เหนือเส้น 0 = แย่กว่า k = 5 · ใต้เส้น 0 = ดีกว่า · เส้นตั้งคือช่วงความเชื่อมั่น 95% (bootstrap) เฉลี่ย 5 seed',
             loc='left', fontsize=9.5, color=INK2, pad=10)
ax.legend(loc='upper center', bbox_to_anchor=(0.5, -0.2), ncol=3, frameon=False, fontsize=9.5,
          labelcolor=INK2, handletextpad=0.4, columnspacing=1.6, markerscale=1.4)
k0 = [data[key][2][0] for key, *_ in SETS]
fig.text(0.07, 0.015, f'นอกกราฟ: k = 0 (คิดตรงๆ) แย่กว่า k = 5 อยู่ +{min(k0):.2f} ถึง +{max(k0):.2f} จุดเปอร์เซ็นต์ '
         f'และ k = 21 แย่กว่า +{min(data[key][2][-1] for key, *_ in SETS):.2f} ถึง +{max(data[key][2][-1] for key, *_ in SETS):.2f}',
         fontsize=9, color=INK2)
fig.tight_layout(rect=(0, 0.04, 1, 1))
fig.savefig(os.path.join(OUT, 'k_cv_diff_vs_k5.png'), facecolor=SURF)
plt.close(fig)

# ---------- รูปที่ 3: MAPE แยกตามวันที่จด (ข้อมูลเดิม) ----------
def load_days(key):
    acc = {}
    for s in SEEDS:
        for r in csv.DictReader(open(os.path.join(RES, f'{key}_days_seed{s}.csv'), encoding='utf-8')):
            if r['mape']:
                acc.setdefault((r['method'], int(r['day'])), []).append(float(r['mape']))
    return {k: sum(v) / len(v) for k, v in acc.items()}


DAYS = [3, 5, 7, 10, 15, 20, 25]
dd = load_days('base')
REF = '#9a9993'
LINES = [
    ('k5', 'k = 5 (แอปใช้)', '#2a78d6', 'o', '-', 2.6),
    ('k0', 'k = 0 (คิดตรงๆ ไม่ถ่วง)', '#eb6834', 's', '--', 2),
    ('k21', 'k = 21 (พึ่งรอบก่อนมาก)', '#1baf7a', '^', ':', 2),
]
fig, ax = plt.subplots(figsize=(9, 5.2), dpi=200, facecolor=SURF)
style(ax)
prev = [dd[('previous', d)] for d in DAYS]
ax.plot(DAYS, prev, color=REF, linewidth=1.6, linestyle=(0, (2, 2)), zorder=2, label='ทายเท่ารอบก่อน (ไม่ใช้ข้อมูลรอบนี้)')
ax.annotate('ทายเท่ารอบก่อน', (DAYS[-1], prev[-1]), xytext=(8, 0), textcoords='offset points',
            va='center', fontsize=9.5, color=INK2)
for m, label, color, marker, ls, lw in LINES:
    ys = [dd[(m, d)] for d in DAYS]
    ax.plot(DAYS, ys, color=color, linewidth=lw, linestyle=ls, zorder=3 if m != 'k5' else 4)
    ax.plot(DAYS, ys, linestyle='none', marker=marker, markersize=6.5, color=color,
            markeredgecolor=SURF, markeredgewidth=1.5, zorder=5, label=label)
ax.annotate('k = 0', (DAYS[0], dd[('k0', 3)]), xytext=(-10, 0), textcoords='offset points',
            ha='right', va='center', fontsize=9.5, color=INK2)
ax.annotate('k = 5', (DAYS[0], dd[('k5', 3)]), xytext=(-10, -4), textcoords='offset points',
            ha='right', va='center', fontsize=9.5, color=INK2)
ax.annotate('k = 21', (DAYS[0], dd[('k21', 3)]), xytext=(-10, 4), textcoords='offset points',
            ha='right', va='center', fontsize=9.5, color=INK2)
# ส่วนที่การถ่วงช่วยมากที่สุด: ลูกศรที่วันที่ 3 และ 5 ตัวเลขอยู่ใต้กราฟ
for d in (3, 5):
    a, b = dd[('k0', d)], dd[('k5', d)]
    ax.annotate('', xy=(d, b + 0.15), xytext=(d, a - 0.15),
                arrowprops=dict(arrowstyle='->', color=INK, lw=1.2), zorder=6)
ax.set_xticks(DAYS)
ax.set_xticklabels([f'วันที่ {d}' for d in DAYS])
ax.set_xlim(0.6, 28.2)
ax.set_ylim(0, 18.5)
ax.set_xlabel('วันที่จดมิเตอร์ล่าสุด นับจากต้นรอบบิล', color=INK2, fontsize=10.5, labelpad=8)
ax.set_ylabel('MAPE (%)  ยิ่งต่ำยิ่งแม่น', color=INK2, fontsize=10.5, labelpad=8)
fig.suptitle('การถ่วงด้วยบิลรอบก่อนช่วยมากที่สุดช่วงต้นรอบบิล', x=0.07, ha='left',
             fontsize=14, fontweight='semibold', color=INK)
ax.set_title('ความคลาดเคลื่อนของยอดคาดการณ์สิ้นรอบ แยกตามวันที่จด · ข้อมูลเดิม RECON-SL เฉลี่ย 5 seed',
             loc='left', fontsize=9.5, color=INK2, pad=10)
ax.legend(loc='upper center', bbox_to_anchor=(0.5, -0.24), ncol=2, frameon=False, fontsize=9.5,
          labelcolor=INK2, handletextpad=0.4, columnspacing=1.6, markerscale=1.3)
th = load_days('bkk')
drops = ' · '.join(f'วันที่ {d} {dd[("k0", d)]:.1f}% → {dd[("k5", d)]:.1f}% (ลดลง {dd[("k0", d)] - dd[("k5", d)]:.1f} จุด)'
                   for d in (3, 5, 7))
fig.text(0.07, 0.05, f'k = 5 เทียบกับคิดตรงๆ: {drops}', fontsize=9.5, color=INK)
fig.text(0.07, 0.015, f'ข้อมูลที่ปรับฤดูกาลไทย (กรุงเทพ) ให้ผลแบบเดียวกัน: วันที่ 3 {th[("k0", 3)]:.1f}% → {th[("k5", 3)]:.1f}%, '
         f'วันที่ 5 {th[("k0", 5)]:.1f}% → {th[("k5", 5)]:.1f}% (ดู k_days_summary.txt)', fontsize=9, color=INK2)
fig.tight_layout(rect=(0, 0.08, 1, 1))
fig.savefig(os.path.join(OUT, 'k_cv_mape_by_day.png'), facecolor=SURF)
plt.close(fig)
print('ok')
