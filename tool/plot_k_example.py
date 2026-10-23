# plot_k_example.py
#
# วาดรูปตัวอย่างเทียบ k = 0, 3 และ 5 จากผลของ tool/k_example.dart
#   k_example_chart.png : ยอดคาดการณ์สิ้นรอบ (บาท) ตามวันที่จด ไฟฟ้าและน้ำ
#   k_example_table.png : ตารางเดียวกัน ช่องที่ใกล้ยอดจริงที่สุดในแถวมีพื้นฟ้า
# ใช้ฟอนต์ IBM Plex Sans Thai จาก assets/fonts ต้องมี matplotlib
#
# วิธีใช้: python tool/plot_k_example.py docs/k_cv/k_example_data.txt assets/fonts docs/k_cv

import os
import sys

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib import font_manager

SRC, FONTS, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
for f in ('IBMPlexSansThai-Regular.ttf', 'IBMPlexSansThai-SemiBold.ttf'):
    font_manager.fontManager.addfont(os.path.join(FONTS, f))
plt.rcParams['font.family'] = 'IBM Plex Sans Thai'

INK, INK2, MUTED, GRID, SURF, BEST = '#0b0b0b', '#52514e', '#8a8984', '#e6e5e1', '#ffffff', '#eef4fc'
MONTH = {10: 'ต.ค.', 11: 'พ.ย.'}

# อ่านผลจาก k_example.dart
data, cur = {}, None
for line in open(SRC, encoding='utf-8'):
    p = line.strip().split('|')
    if p[0].startswith('#'):
        cur = p[0][1:]
        data[cur] = {'actual_u': float(p[1]), 'actual_b': float(p[2]), 'rows': []}
    elif cur:
        d, m = p[0].split('/')
        data[cur]['rows'].append(dict(label=f'{d} {MONTH[int(m)]}', days=float(p[1]), meter=int(p[2]), used=int(p[3]),
                                      k0=(float(p[4]), float(p[5])), k3=(float(p[6]), float(p[7])),
                                      k5=(float(p[8]), float(p[9]))))

SERIES = [('k0', 'k = 0 (คิดตรงๆ)', '#eb6834', 's', '--'),
          ('k3', 'k = 3', '#1baf7a', '^', ':'),
          ('k5', 'k = 5 (แอปใช้)', '#2a78d6', 'o', '-')]
UNITS = {'ไฟฟ้า': 'หน่วย', 'น้ำ': 'ลบ.ม.'}

# ---------- รูป ก: ยอดคาดการณ์สิ้นรอบตามวันที่จด ----------
fig, axes = plt.subplots(1, 2, figsize=(12, 5.4), dpi=200, facecolor=SURF)
for ax, name in zip(axes, ['ไฟฟ้า', 'น้ำ']):
    dd = data[name]
    rows = dd['rows']
    xs = list(range(len(rows)))  # เว้นระยะเท่ากัน วันที่อยู่ใกล้กันจะได้ไม่ทับ
    ax.set_facecolor(SURF)
    for side in ('top', 'right'):
        ax.spines[side].set_visible(False)
    for side in ('left', 'bottom'):
        ax.spines[side].set_color(GRID)
    ax.tick_params(colors=INK2, labelsize=9.5, length=0, pad=6)
    ax.grid(axis='y', color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)
    ax.axhline(dd['actual_b'], color=INK2, linewidth=1.2, linestyle=(0, (4, 3)), zorder=2)
    ax.text(xs[-1] + 0.25, dd['actual_b'], f'จริง\n{dd["actual_b"]:,.0f} บาท', va='center', fontsize=9.5, color=INK)
    for key, label, color, marker, ls in SERIES:
        ys = [r[key][1] for r in rows]
        lw = 2.6 if key == 'k5' else 1.8
        ax.plot(xs, ys, color=color, linewidth=lw, linestyle=ls, zorder=4 if key == 'k5' else 3)
        ax.plot(xs, ys, linestyle='none', marker=marker, markersize=6.5, color=color,
                markeredgecolor=SURF, markeredgewidth=1.5, zorder=5, label=label)
    ax.set_xticks(xs)
    ax.set_xticklabels([f"{r['label']}" + chr(10) + f"({r['days']:.1f} วัน)" for r in rows], fontsize=9)
    ax.set_xlim(-0.4, xs[-1] + 1.1)
    ax.set_title(f'{name}  ·  จริงทั้งรอบ {dd["actual_u"]:.1f} {UNITS[name]} = {dd["actual_b"]:,.2f} บาท',
                 loc='left', fontsize=11.5, fontweight='semibold', color=INK, pad=10)
    ax.set_xlabel('วันที่จดมิเตอร์ (20:00)', color=INK2, fontsize=10, labelpad=6)
axes[0].set_ylabel('ยอดคาดการณ์สิ้นรอบ (บาท)', color=INK2, fontsize=10, labelpad=8)
handles, labels = axes[0].get_legend_handles_labels()
fig.legend(handles, labels, loc='lower center', ncol=3, frameon=False, fontsize=10, labelcolor=INK2,
           markerscale=1.3, bbox_to_anchor=(0.5, 0.06))
fig.suptitle('ตัวอย่าง: ยอดคาดการณ์สิ้นรอบบิลเมื่อใช้ k = 0, 3 และ 5', x=0.06, ha='left', y=0.985,
             fontsize=14, fontweight='semibold', color=INK)
fig.text(0.06, 0.915, 'วันตัดรอบวันที่ 9 (รอบ 9 ต.ค. - 8 พ.ย. 2569) · บิลรอบก่อน ไฟฟ้า 10 หน่วย/วัน น้ำ 0.5 ลบ.ม./วัน · '
         'วันธรรมดาใช้น้อย เสาร์-อาทิตย์ใช้มาก · กทม. มิเตอร์ปกติ Ft 0.1623',
         fontsize=9.5, color=INK2)
fig.text(0.06, 0.015, 'ข้อมูลสมมติเพื่ออธิบายสูตร คำนวณด้วยฟังก์ชันจริงของแอป (EnergyForecaster.projectToCycleEnd, TariffTables) '
         '· หลักฐานความแม่นยำอยู่ที่ docs/k_cv/', fontsize=8.5, color=MUTED)
fig.tight_layout(rect=(0, 0.11, 1, 0.9), h_pad=0)
fig.subplots_adjust(top=0.8)
fig.savefig(os.path.join(OUT, 'k_example_chart.png'), facecolor=SURF)
plt.close(fig)

# ---------- รูป ข: ตาราง ----------
fig = plt.figure(figsize=(12, 7.6), dpi=200, facecolor=SURF)
fig.suptitle('ตัวอย่างเทียบ k = 0, 3 และ 5 (บิลต้นรอบเดียวกัน จดมิเตอร์เท่ากัน)', x=0.04, ha='left', y=0.975,
             fontsize=14, fontweight='semibold', color=INK)
fig.text(0.04, 0.925, 'วันตัดรอบวันที่ 9 · เลขมิเตอร์ต้นรอบ ไฟฟ้า 12,345 น้ำ 1,234 · บิลรอบก่อน ไฟฟ้า 300 หน่วย/30 วัน '
         'น้ำ 15 ลบ.ม./30 วัน · ช่องพื้นฟ้า = ใกล้ยอดจริงที่สุดในแถว', fontsize=9.5, color=INK2)
cols = ['จดเมื่อ', 'ผ่านไป', 'เลขมิเตอร์', 'ใช้ไปแล้ว', 'k = 0 (คิดตรงๆ)', 'k = 3', 'k = 5 (แอปใช้)']
for i, name in enumerate(['ไฟฟ้า', 'น้ำ']):
    dd = data[name]
    u = UNITS[name]
    top = 0.86 - i * 0.43
    fig.text(0.04, top, f'{name}  ·  จริงทั้งรอบ {dd["actual_u"]:.1f} {u} = {dd["actual_b"]:,.2f} บาท',
             fontsize=11.5, fontweight='semibold', color=INK)
    ax = fig.add_axes([0.04, top - 0.375, 0.92, 0.35])
    ax.axis('off')
    cells, best = [], []
    for r in dd['rows']:
        fmt = (lambda v: f'{v[0]:,.1f} {u} · {v[1]:,.2f} ฿')
        cells.append([r['label'], f'{r["days"]:.1f} วัน', f'{r["meter"]:,}', f'{r["used"]} {u}',
                      fmt(r['k0']), fmt(r['k3']), fmt(r['k5'])])
        errs = [abs(r[k][1] - dd['actual_b']) for k in ('k0', 'k3', 'k5')]
        best.append(4 + errs.index(min(errs)))
    t = ax.table(cellText=cells, colLabels=cols, loc='upper center', cellLoc='center',
                 colWidths=[0.09, 0.09, 0.11, 0.11, 0.2, 0.2, 0.2])
    t.auto_set_font_size(False)
    t.set_fontsize(10)
    t.scale(1, 1.75)
    for (row, col), c in t.get_celld().items():
        c.set_edgecolor(GRID)
        c.set_linewidth(0.8)
        c.get_text().set_color(INK)
        if row == 0:
            c.set_facecolor('#f4f4f2')
            c.get_text().set_fontweight('semibold')
            c.get_text().set_color(INK2)
        elif col == best[row - 1]:
            c.set_facecolor(BEST)
            c.get_text().set_fontweight('semibold')
        else:
            c.set_facecolor(SURF)
fig.text(0.04, 0.012, 'ข้อมูลสมมติเพื่ออธิบายสูตร คำนวณด้วยฟังก์ชันจริงของแอป · มิเตอร์อ่านได้เป็นจำนวนเต็ม '
         '(น้ำวันที่ 28 และ 29 ต.ค. หน้าปัดยังไม่ขึ้นเลขใหม่) · หลักฐานความแม่นยำอยู่ที่ docs/k_cv/',
         fontsize=8.5, color=MUTED)
fig.savefig(os.path.join(OUT, 'k_example_table.png'), facecolor=SURF)
plt.close(fig)
print('ok')
