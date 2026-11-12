import sys, math
sys.path.insert(0, __file__.rsplit('/', 1)[0])
from preview import *

RX = rot('x', -math.pi/2)  # loft (вдоль Z) -> вертикально (вдоль Y)


def human(sc, x, z, skin, shirt, pants, hair, cop=False, yaw=0.0, sleeves=False, jacket=None):
    R = rot('y', yaw)
    def add(mesh, col, p, Rl=None, **k):
        p = np.array(p, float)
        sc.add(mesh, col, pos=R @ p + np.array([x, 0, z]), R=R @ (np.eye(3) if Rl is None else Rl), **k)
    top = jacket if jacket is not None else shirt
    shoe = (0.07, 0.065, 0.07)
    for s in (-1, 1):
        add(limb(0.088, 0.066, 0.45), pants, (s*0.095, 0.93, 0), rough=0.9)
        add(limb(0.064, 0.046, 0.43), pants, (s*0.097, 0.48, 0.005), rough=0.9)
        add(ellipsoid(0.052, 0.045, 0.125), shoe, (s*0.098, 0.045, 0.035), rough=0.35)
        ra = rot('z', s*0.10)
        add(limb(0.056, 0.045, 0.29), top, (s*0.205, 1.47, -0.005), Rl=ra, rough=0.85)
        fore = top if (sleeves or cop or jacket is not None) else skin
        add(limb(0.044, 0.034, 0.26), fore, (s*0.235, 1.18, 0.0), Rl=rot('z', s*0.04), rough=0.85 if fore is not skin else 0.55)
        add(ellipsoid(0.028, 0.06, 0.045), skin, (s*0.245, 0.88, 0.005), rough=0.55)
    # таз и торс — лофт по высоте
    pel = loft([(0.84, -0.10, 0.10, 0.16, 0.16), (0.92, -0.115, 0.115, 0.175, 0.175), (1.02, -0.11, 0.11, 0.165, 0.165)], ring=24, power=2.6)
    add(pel, pants, (0, 0, 0), Rl=RX, rough=0.9)
    tor = loft([(1.0, -0.112, 0.112, 0.168, 0.168), (1.12, -0.10, 0.11, 0.152, 0.152), (1.28, -0.11, 0.125, 0.172, 0.172),
                (1.42, -0.105, 0.115, 0.198, 0.198), (1.50, -0.085, 0.09, 0.19, 0.19), (1.555, -0.05, 0.055, 0.08, 0.08)], ring=28, power=2.6)
    add(tor, top, (0, 0, 0), Rl=RX, rough=0.85)
    if jacket is not None:
        add(box(0.09, 0.40, 0.02), shirt, (0, 1.30, 0.112), rough=0.85)
    add(limb(0.05, 0.055, 0.1), skin, (0, 1.63, -0.005), rough=0.55)
    # голова
    add(ellipsoid(0.093, 0.118, 0.108), skin, (0, 1.715, 0.0), rough=0.5)
    add(ellipsoid(0.07, 0.05, 0.078), skin, (0, 1.655, 0.012), rough=0.5)
    add(ellipsoid(0.017, 0.03, 0.022), skin, (0, 1.69, 0.108), rough=0.5)
    for s in (-1, 1):
        add(ellipsoid(0.015, 0.03, 0.02), skin, (s*0.093, 1.70, -0.005), rough=0.5)
        add(sphere(0.011), (0.05, 0.04, 0.04), (s*0.035, 1.725, 0.094), rough=0.1)
        add(box(0.04, 0.009, 0.01), hair if not cop else (0.1, 0.07, 0.05), (s*0.036, 1.748, 0.1), rough=0.8)
    if cop:
        add(cylinder(0.104, 0.07), (0.05, 0.07, 0.15), (0, 1.81, -0.005), rough=0.6)
        add(cylinder(0.1, 0.015, r2=0.1), (0.02, 0.02, 0.03), (0, 1.778, 0.06), scale=(1, 1, 0.9), rough=0.25)
        add(box(0.04, 0.03, 0.01), (0.9, 0.72, 0.25), (0, 1.81, 0.104), rough=0.2, metal=1.0)
        add(loft([(1.03, -0.118, 0.118, 0.172, 0.172), (1.09, -0.118, 0.118, 0.172, 0.172)], ring=24, power=2.6),
            (0.03, 0.03, 0.03), (0, 0, 0), Rl=RX, rough=0.35)
        add(box(0.05, 0.06, 0.012), (0.9, 0.72, 0.25), (0.09, 1.36, 0.118), rough=0.2, metal=1.0)
        add(box(0.06, 0.14, 0.07), (0.03, 0.03, 0.03), (0.19, 1.0, 0.0), rough=0.4)
    else:
        add(ellipsoid(0.1, 0.085, 0.112), hair, (0, 1.765, -0.012), rough=0.8)
        add(ellipsoid(0.095, 0.08, 0.06), hair, (0, 1.71, -0.06), rough=0.8)


CAR = {
    # profile: (z_rel, y_bot, y_top, half_w) по длине (1=перед), greenhouse: (z, y_top, half_w_top)
    'sedan': dict(L=4.7, W=1.84, wr=0.33, scale_h=1.0, wb=1.38,
                  body=[(-1.0, .40, .78, .80), (-.985, .30, .92, .88), (-.90, .27, .985, .915), (-.55, .25, .99, .92),
                        (-.45, .25, .985, .92), (0.0, .25, .955, .92), (.42, .25, .93, .92), (.55, .26, .915, .915),
                        (.85, .27, .875, .905), (.96, .31, .82, .88), (1.0, .40, .74, .82)],
                  glass=[(.47, .955, .83), (.42, 1.02, .80), (.16, 1.38, .74), (-.30, 1.40, .73), (-.50, 1.27, .75), (-.58, 1.02, .80), (-.60, .97, .82)]),
    'sport': dict(L=4.45, W=1.96, wr=0.34, scale_h=1.0, wb=1.34,
                  body=[(-1.0, .34, .70, .88), (-.98, .24, .82, .95), (-.85, .21, .86, .98), (-.3, .2, .82, .98), (.2, .2, .76, .97),
                        (.6, .21, .70, .96), (.9, .22, .62, .93), (1.0, .30, .55, .86)],
                  glass=[(.35, .79, .86), (.28, .86, .82), (.02, 1.17, .72), (-.32, 1.16, .70), (-.62, .88, .80), (-.68, .84, .84)]),
    'suv': dict(L=4.85, W=2.0, wr=0.41, scale_h=1.0, wb=1.48,
                body=[(-1.0, .55, 1.0, .88), (-.98, .44, 1.13, .96), (-.9, .42, 1.17, .98), (0, .40, 1.16, .99), (.55, .40, 1.12, .99),
                      (.85, .42, 1.08, .97), (.97, .46, 1.0, .94), (1.0, .55, .92, .88)],
                glass=[(.58, 1.14, .9), (.52, 1.22, .87), (.30, 1.72, .80), (-.8, 1.74, .80), (-.92, 1.64, .82), (-.95, 1.17, .9)]),
    'van': dict(L=5.3, W=2.05, wr=0.37, scale_h=1.0, wb=1.62,
                body=[(-1.0, .42, 2.05, .99), (-.98, .36, 2.12, 1.0), (.55, .36, 2.12, 1.0), (.62, .37, 1.05, 1.0), (.88, .38, 1.0, .98),
                      (.98, .42, .92, .95), (1.0, .5, .82, .9)],
                glass=[(.66, 1.02, .97), (.62, 1.10, .95), (.56, 1.70, .93), (.50, 1.70, .93), (.46, 1.05, .97)]),
}


def car(sc, x, z, kind, paint, yaw=0.0):
    R = rot('y', yaw)
    base = 'sedan' if kind in ('police', 'taxi') else kind
    s = CAR[base]
    L, W = s['L'], s['W']
    hl = L/2; hw = W/2
    def add(mesh, col, p, Rl=None, **k):
        p = np.array(p, float)
        sc.add(mesh, col, pos=R @ p + np.array([x, 0, z]), R=R @ (np.eye(3) if Rl is None else Rl), **k)
    paint_kw = dict(rough=0.18, metal=0.6)
    white = (0.93, 0.93, 0.95)
    secs = [(zz*hl, yb, yt, w*hw, w*hw*0.965) for (zz, yb, yt, w) in s['body']]
    add(loft(secs, ring=36, power=5.0), paint, (0, 0, 0), **paint_kw)
    if kind == 'police':
        # белые двери: полоса лофта по середине
        mid = [(zz*hl, yb+0.08, yt-0.06, w*hw+0.014, w*hw*0.965+0.014) for (zz, yb, yt, w) in s['body'] if -0.46 <= zz <= 0.43]
        mid = [(-0.45*hl,) + mid[0][1:]] + mid + [(0.42*hl,) + mid[-1][1:]]
        add(loft(mid, ring=36, power=5.0), white, (0, 0, 0), rough=0.2, metal=0.3)
    g = s['glass']
    belt = None
    gsecs = []
    for (zz, yt, w) in g:
        yb = 0.80 if base != 'van' else 0.95
        gsecs.append((zz*hl, yb, yt, w*hw, w*hw*0.80))
    add(loft(gsecs, ring=36, power=4.0), (0.06, 0.08, 0.10), (0, 0, 0), rough=0.03, glass=True)
    # крыша (окрашенная) — верхушка оранжереи
    roof_col = white if kind == 'police' else paint
    rs = []
    for (zz, yb, yt, wb, wt) in gsecs[1:-1]:
        rs.append((zz, yt-0.05, yt+0.014, wt*0.98, wt*0.93))
    rs = [r for r in rs if r[2] > (max(q[2] for q in gsecs) - 0.08)]
    if len(rs) >= 2:
        add(loft(rs, ring=28, power=6.0), roof_col, (0, 0, 0), **paint_kw)
    # стойки
    zs = sorted([q[0] for q in gsecs])
    top_y = max(q[2] for q in gsecs)
    for sd in (-1, 1):
        # ручки, зеркала, швы дверей
        add(box(0.012, 0.025, 0.12), (0.7, 0.7, 0.72), (sd*(hw*0.925+0.006), 0.78, 0.2), rough=0.15, metal=1.0)
        add(box(0.012, 0.025, 0.12), (0.7, 0.7, 0.72), (sd*(hw*0.925+0.006), 0.78, -0.75), rough=0.15, metal=1.0)
        add(ellipsoid(0.045, 0.05, 0.08), paint, (sd*(hw*0.86+0.04), 0.98 if base == 'sedan' else (0.86 if base == 'sport' else 1.2), zs[-1]-0.2), **paint_kw)
        for dz in (-0.25, 0.68 if base != 'van' else 1.3):
            add(box(0.006, 0.5 if base != 'van' else 0.7, 0.008), (0.05, 0.05, 0.05), (sd*(hw*0.928), 0.62 if base != 'van' else 0.75, dz), rough=0.6)
    # фары / решётка / бампер
    fy = 0.62 if base == 'sedan' else (0.55 if base == 'sport' else 0.82)
    if base == 'van': fy = 0.72
    for sd in (-1, 1):
        add(box(0.36, 0.11, 0.06), (1.0, 0.98, 0.92), (sd*(hw-0.32), fy, hl-0.03), rough=0.03, metal=0.2, emit=0.9)
        add(box(0.30, 0.10, 0.06), (0.8, 0.05, 0.04), (sd*(hw-0.27), fy+0.08, -hl+0.04), rough=0.05, emit=0.6)
    add(box(W*0.36, 0.13, 0.05), (0.03, 0.03, 0.03), (0, fy-0.02, hl-0.005), rough=0.3, metal=0.4)
    add(box(W*0.37, 0.02, 0.055), (0.75, 0.75, 0.78), (0, fy+0.055, hl-0.003), rough=0.1, metal=1.0)
    add(box(W*0.9, 0.17, 0.08), (0.06, 0.06, 0.065), (0, 0.36 if base != 'suv' else 0.5, hl+0.01), rough=0.55)
    add(box(W*0.9, 0.17, 0.08), (0.06, 0.06, 0.065), (0, 0.36 if base != 'suv' else 0.5, -hl-0.01), rough=0.55)
    add(box(0.42, 0.11, 0.012), (0.95, 0.95, 0.93), (0, 0.42 if base != 'suv' else 0.58, hl+0.055), rough=0.4)
    add(box(0.42, 0.11, 0.012), (0.95, 0.95, 0.93), (0, 0.56 if base != 'suv' else 0.72, -hl-0.005), rough=0.4)
    # колёса + арки
    wr = s['wr']; wb = s['wb']
    for sx in (-1, 1):
        for sz in (-1, 1):
            p = (sx*(hw-0.13), wr, sz*wb)
            add(cylinder(wr+0.07, 0.03), (0.015, 0.015, 0.015), (sx*(hw*0.93), wr+0.02, sz*wb), Rl=rot('z', math.pi/2), rough=0.9)
            add(cylinder(wr, 0.23), (0.035, 0.035, 0.035), (sx*(hw-0.08), wr, sz*wb), Rl=rot('z', math.pi/2), rough=0.85)
            add(cylinder(wr*0.66, 0.235), (0.62, 0.63, 0.66), (sx*(hw-0.08), wr, sz*wb), Rl=rot('z', math.pi/2), rough=0.15, metal=1.0)
            for k in range(5):
                a = 2*math.pi*k/5
                add(box(0.02, wr*0.55, 0.06), (0.8, 0.8, 0.83), (sx*(hw-0.08+0.12*sx/1.0*0.0+sx*0.12), wr+math.cos(a)*wr*0.28, sz*wb+math.sin(a)*wr*0.28),
                    Rl=rot('x', -a), rough=0.15, metal=1.0)
            add(cylinder(wr*0.15, 0.25), (0.25, 0.25, 0.27), (sx*(hw-0.08), wr, sz*wb), Rl=rot('z', math.pi/2), rough=0.2, metal=1.0)
    if kind == 'police':
        add(box(1.15, 0.09, 0.30), (0.08, 0.08, 0.08), (0, top_y+0.06, -0.15), rough=0.4)
        add(box(0.5, 0.09, 0.26), (1.0, 0.08, 0.06), (-0.29, top_y+0.11, -0.15), rough=0.05, emit=1.4)
        add(box(0.5, 0.09, 0.26), (0.08, 0.25, 1.0), (0.29, top_y+0.11, -0.15), rough=0.05, emit=1.4)
        add(box(1.1, 0.30, 0.06), (0.05, 0.05, 0.05), (0, 0.55, hl+0.18), rough=0.4)  # кенгурятник
    if kind == 'taxi':
        add(box(0.62, 0.17, 0.26), (1.0, 0.96, 0.75), (0, top_y+0.09, -0.15), rough=0.3, emit=0.6)
    if kind == 'sport':
        add(box(W-0.25, 0.035, 0.28), paint, (0, 0.98, -hl+0.25), **paint_kw)
        for sd in (-1, 1):
            add(box(0.05, 0.2, 0.06), (0.03, 0.03, 0.03), (sd*0.6, 0.88, -hl+0.25), rough=0.4)


if __name__ == '__main__':
    out = sys.argv[1]
    sc = Scene()
    human(sc, -2.0, 0, (0.86, 0.66, 0.53), (0.85, 0.85, 0.83), (0.16, 0.22, 0.36), (0.13, 0.09, 0.06), yaw=0.25, jacket=(0.10, 0.10, 0.11))
    human(sc, -1.0, 0, (0.50, 0.35, 0.25), (0.70, 0.18, 0.15), (0.08, 0.08, 0.09), (0.04, 0.03, 0.02), yaw=0.1)
    human(sc, 0.0, 0, (0.80, 0.60, 0.46), (0.07, 0.11, 0.24), (0.05, 0.06, 0.11), (0.1, 0.07, 0.05), cop=True)
    human(sc, 1.0, 0, (0.93, 0.76, 0.64), (0.26, 0.38, 0.30), (0.45, 0.39, 0.28), (0.55, 0.40, 0.20), yaw=-0.1, sleeves=True)
    human(sc, 2.0, 0, (0.76, 0.56, 0.42), (0.18, 0.18, 0.19), (0.30, 0.36, 0.52), (0.18, 0.13, 0.09), yaw=-0.25)
    render(sc, (0, 1.55, 6.8), (0, 0.98, 0), W=1100, H=650, fov=30, title="Персонажи v2").save(out + "/v2_people.png")

    sc = Scene(); human(sc, 0, 0, (0.86, 0.66, 0.53), (0.85, 0.85, 0.83), (0.16, 0.22, 0.36), (0.13, 0.09, 0.06), yaw=0.45, jacket=(0.10, 0.10, 0.11))
    render(sc, (0.3, 1.65, 2.4), (0, 1.35, 0), W=700, H=700, fov=34, title="Крупно").save(out + "/v2_closeup.png")

    sc = Scene()
    car(sc, -4.7, 0, 'sedan', (0.10, 0.20, 0.40), yaw=0.6)
    car(sc, 0, 0.6, 'sport', (0.72, 0.04, 0.04), yaw=0.6)
    car(sc, 4.8, 0, 'suv', (0.12, 0.12, 0.13), yaw=0.6)
    render(sc, (0, 3.0, 13.5), (0, 0.65, 0), W=1200, H=600, fov=36, title="Машины v2: седан · спорткар · внедорожник").save(out + "/v2_cars1.png")

    sc = Scene()
    car(sc, -4.7, 0, 'police', (0.03, 0.03, 0.035), yaw=0.6)
    car(sc, 0, 0.5, 'taxi', (0.95, 0.70, 0.05), yaw=0.6)
    car(sc, 5.0, 0, 'van', (0.86, 0.87, 0.89), yaw=0.6)
    render(sc, (0, 3.3, 14.0), (0, 0.85, 0), W=1200, H=600, fov=36, title="Машины v2: полиция · такси · фургон").save(out + "/v2_cars2.png")
