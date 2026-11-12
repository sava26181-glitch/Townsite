import sys, math
sys.path.insert(0, __file__.rsplit('/', 1)[0])
from preview import *

def human(sc, x, z, skin, shirt, pants, hair, cop=False, yaw=0.0):
    R = rot('y', yaw)
    def add(mesh, col, p, **k):
        p = np.array(p, float)
        sc.add(mesh, col, pos=R @ p + np.array([x, 0, z]), R=R @ k.pop('Rl', np.eye(3)), **k)
    shoe = (0.08, 0.08, 0.09)
    for s in (-1, 1):
        add(capsule(0.085, 0.52), pants, (s*0.1, 0.70, 0), rough=0.85)
        add(capsule(0.072, 0.50), pants, (s*0.1, 0.30, 0), rough=0.85)
        add(box(0.12, 0.09, 0.27), shoe, (s*0.1, 0.045, 0.04), rough=0.4)
        add(capsule(0.062, 0.36), shirt, (s*0.255, 1.30, 0), rough=0.85, Rl=rot('z', s*0.08))
        add(capsule(0.05, 0.32), shirt if cop else skin, (s*0.275, 1.01, 0.01), rough=0.7 if not cop else 0.85)
        add(sphere(0.05), skin, (s*0.28, 0.83, 0.015), rough=0.6)
    add(box(0.34, 0.2, 0.21), pants, (0, 0.98, 0), rough=0.85)
    add(frustum(0.21, 0.34, 0.25, 0.46, 0.52), shirt, (0, 1.02, 0), rough=0.85)
    add(cylinder(0.055, 0.12), skin, (0, 1.58, 0), rough=0.6)
    add(sphere(0.115), skin, (0, 1.72, 0.005), scale=(0.88, 1.1, 1.0), rough=0.55)
    if cop:
        add(cylinder(0.122, 0.08), (0.06, 0.08, 0.16), (0, 1.83, 0), rough=0.6)
        add(box(0.2, 0.02, 0.1), (0.03, 0.03, 0.05), (0, 1.79, 0.11), rough=0.3)
        add(box(0.36, 0.06, 0.23), (0.05, 0.05, 0.05), (0, 1.06, 0), rough=0.4)
        add(box(0.06, 0.07, 0.02), (0.9, 0.72, 0.25), (0.11, 1.38, 0.125), rough=0.2, metal=1.0)
    else:
        add(sphere(0.126, hemi=True), hair, (0, 1.715, -0.012), scale=(0.93, 1.05, 1.06), rough=0.75)
        add(box(0.2, 0.1, 0.06), hair, (0, 1.68, -0.1), rough=0.75)

def car(sc, x, z, kind, paint, yaw=0.0):
    R = rot('y', yaw)
    spec = {
        'sedan': dict(L=4.5, W=1.82, bh=0.62, cl=0.30, cb=(2.55, 1.72), ct=(1.5, 1.36), ch=0.52, coff=-0.15, wr=0.34),
        'sport': dict(L=4.4, W=1.96, bh=0.50, cl=0.22, cb=(2.2, 1.74), ct=(1.1, 1.30), ch=0.40, coff=-0.30, wr=0.35),
        'suv':   dict(L=4.8, W=2.00, bh=0.80, cl=0.42, cb=(2.95, 1.86), ct=(2.45, 1.66), ch=0.64, coff=-0.30, wr=0.42),
        'van':   dict(L=5.3, W=2.05, bh=0.90, cl=0.36, cb=(4.3, 1.98), ct=(3.9, 1.9), ch=1.15, coff=-0.45, wr=0.38),
    }
    base = 'sedan' if kind in ('police', 'taxi') else kind
    s = spec[base]
    L, W, bh, cl = s['L'], s['W'], s['bh'], s['cl']
    def add(mesh, col, p, **k):
        p = np.array(p, float)
        sc.add(mesh, col, pos=R @ p + np.array([x, 0, z]), R=R @ k.pop('Rl', np.eye(3)), **k)
    paint_kw = dict(rough=0.22, metal=0.55)
    dark = (0.04, 0.04, 0.045)
    body_col = paint
    add(frustum(L, W, L-0.25, W-0.08, bh), body_col, (0, cl, 0), **paint_kw)
    if kind == 'police':
        # бело-чёрная ливрея: белые двери
        add(box(W+0.005, bh*0.55, L*0.42), (0.92, 0.92, 0.94), (0, cl+bh*0.42, -0.1), rough=0.25, metal=0.3)
    cab_y = cl + bh
    cz = s['coff']
    add(frustum(s['cb'][0], s['cb'][1], s['ct'][0], s['ct'][1], s['ch'], top_off=-0.08), (0.08, 0.1, 0.12), (0, cab_y, cz), rough=0.05, metal=0.0, glass=True)
    add(box(s['ct'][1]+0.02, 0.05, s['ct'][0]+0.02), body_col if kind != 'police' else (0.92, 0.92, 0.94), (0, cab_y+s['ch']+0.02, cz-0.08), **paint_kw)
    if base == 'van':
        add(box(W-0.04, s['ch']-0.05, s['cb'][0]-1.1), body_col, (0, cab_y+s['ch']/2-0.03, cz-0.6), **paint_kw)
    # бамперы, решётка, фары
    add(box(W-0.02, 0.22, 0.14), dark, (0, cl+0.12, L/2-0.04), rough=0.5)
    add(box(W-0.02, 0.22, 0.14), dark, (0, cl+0.12, -L/2+0.04), rough=0.5)
    add(box(W*0.42, 0.13, 0.04), (0.02, 0.02, 0.02), (0, cl+bh*0.5, L/2-0.0), rough=0.3, metal=0.5)
    for sd in (-1, 1):
        add(box(0.36, 0.11, 0.05), (1.0, 0.98, 0.9), (sd*(W/2-0.3), cl+bh*0.6, L/2+0.0), rough=0.05, emit=0.8)
        add(box(0.34, 0.12, 0.05), (0.75, 0.04, 0.03), (sd*(W/2-0.28), cl+bh*0.6, -L/2-0.0), rough=0.1, emit=0.5)
        add(box(0.07, 0.09, 0.16), body_col, (sd*(s['cb'][1]/2+0.06), cab_y+0.08, cz+s['cb'][0]/2-0.25), **paint_kw)
        add(box(0.02, bh*0.5, 0.012), (0.1, 0.1, 0.1), (sd*(W/2-0.01), cl+bh*0.5, cz+0.15), rough=0.6)
    # колёса
    wr = s['wr']; wx = W/2-0.13; wz = L/2-0.95 if base != 'van' else L/2-0.9
    for sx in (-1, 1):
        for sz in (-1, 1):
            add(cylinder(wr, 0.25), (0.03, 0.03, 0.03), (sx*wx, wr, sz*wz), rough=0.85, Rl=rot('z', math.pi/2))
            add(cylinder(wr*0.62, 0.26), (0.75, 0.76, 0.78), (sx*wx, wr, sz*wz), rough=0.18, metal=1.0, Rl=rot('z', math.pi/2))
            add(cylinder(wr*0.2, 0.27), (0.2, 0.2, 0.22), (sx*wx, wr, sz*wz), rough=0.3, metal=1.0, Rl=rot('z', math.pi/2))
    if kind == 'police':
        add(box(1.1, 0.1, 0.28), (0.1, 0.1, 0.1), (0, cab_y+s['ch']+0.08, cz-0.08), rough=0.4)
        add(box(0.48, 0.1, 0.24), (1.0, 0.1, 0.08), (-0.27, cab_y+s['ch']+0.14, cz-0.08), rough=0.1, emit=1.2)
        add(box(0.48, 0.1, 0.24), (0.1, 0.25, 1.0), (0.27, cab_y+s['ch']+0.14, cz-0.08), rough=0.1, emit=1.2)
    if kind == 'taxi':
        add(box(0.6, 0.16, 0.25), (1.0, 0.95, 0.7), (0, cab_y+s['ch']+0.12, cz-0.08), rough=0.3, emit=0.5)
    if kind == 'sport':
        add(box(W-0.2, 0.04, 0.3), body_col, (0, cl+bh+0.28, -L/2+0.22), **paint_kw)
        for sd in (-1, 1):
            add(box(0.05, 0.28, 0.05), dark, (sd*0.6, cl+bh+0.13, -L/2+0.22), rough=0.4)

if __name__ == '__main__':
    out = sys.argv[1]
    sc = Scene()
    human(sc, -2.0, 0, (0.87, 0.68, 0.55), (0.15, 0.32, 0.55), (0.18, 0.2, 0.26), (0.12, 0.08, 0.05), yaw=0.25)
    human(sc, -1.0, 0, (0.55, 0.38, 0.27), (0.75, 0.75, 0.73), (0.08, 0.08, 0.1), (0.04, 0.03, 0.02), yaw=0.1)
    human(sc, 0.0, 0, (0.06*10, 0.45, 0.33), (0.06, 0.12, 0.25), (0.06, 0.07, 0.12), (0, 0, 0), cop=True)
    human(sc, 1.0, 0, (0.93, 0.76, 0.64), (0.55, 0.12, 0.12), (0.35, 0.3, 0.22), (0.55, 0.4, 0.2), yaw=-0.1)
    human(sc, 2.0, 0, (0.8, 0.6, 0.45), (0.2, 0.2, 0.2), (0.25, 0.32, 0.5), (0.2, 0.15, 0.1), yaw=-0.25)
    render(sc, (0, 1.6, 7.5), (0, 0.95, 0), W=1100, H=650, fov=30, title="Персонажи: прохожие + полицейский").save(out + "/models_people.png")

    sc = Scene()
    car(sc, -4.6, 0, 'sedan', (0.08, 0.18, 0.42), yaw=0.55)
    car(sc, 0, 0.6, 'sport', (0.75, 0.05, 0.05), yaw=0.55)
    car(sc, 4.6, 0, 'suv', (0.12, 0.12, 0.13), yaw=0.55)
    render(sc, (0, 3.2, 13.5), (0, 0.6, 0), W=1200, H=600, fov=36, title="Машины: седан · спорткар · внедорожник").save(out + "/models_cars1.png")

    sc = Scene()
    car(sc, -4.6, 0, 'police', (0.03, 0.03, 0.035), yaw=0.55)
    car(sc, 0, 0.4, 'taxi', (0.95, 0.72, 0.05), yaw=0.55)
    car(sc, 4.8, 0, 'van', (0.85, 0.86, 0.88), yaw=0.55)
    render(sc, (0, 3.4, 14.0), (0, 0.8, 0), W=1200, H=600, fov=36, title="Машины: полиция · такси · фургон").save(out + "/models_cars2.png")
