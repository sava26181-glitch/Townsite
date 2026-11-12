"""Мини-рендерер превью моделей (numpy, z-буфер, PBR-подобное затенение).
Модели строятся из тех же примитивов и размеров, что и в scripts/models.gd."""
import numpy as np
from PIL import Image, ImageDraw, ImageFont
import sys, math

# ---------- примитивы: возвращают (verts Nx3, normals Nx3, tris Mx3) ----------
def frustum(lb, wb, lt, wt, h, top_off=0.0):
    """Коробка-трапеция: низ lb x wb, верх lt x wt (по Z длина, по X ширина), высота h, центр низа в 0."""
    b = [(-wb/2, 0, -lb/2), (wb/2, 0, -lb/2), (wb/2, 0, lb/2), (-wb/2, 0, lb/2)]
    t = [(-wt/2, h, -lt/2+top_off), (wt/2, h, -lt/2+top_off), (wt/2, h, lt/2+top_off), (-wt/2, h, lt/2+top_off)]
    P = b + t
    faces = [(0,1,2,3)[::-1], (4,5,6,7), (0,1,5,4), (1,2,6,5), (2,3,7,6), (3,0,4,7)]
    V, N, T = [], [], []
    for f in faces:
        q = [np.array(P[i], float) for i in f]
        n = np.cross(q[1]-q[0], q[2]-q[0]); n /= (np.linalg.norm(n)+1e-9)
        c = np.mean(q, 0)
        # ориентируем нормаль наружу
        if np.dot(n, c - np.array([0, h/2, top_off/2])) < 0: n = -n
        base = len(V)
        V += q; N += [n]*4
        T += [(base, base+1, base+2), (base, base+2, base+3)]
    return np.array(V), np.array(N), np.array(T)

def box(sx, sy, sz):
    v, n, t = frustum(sz, sx, sz, sx, sy)
    v[:, 1] -= sy/2
    return v, n, t

def cylinder(r, h, seg=28, r2=None):
    r2 = r if r2 is None else r2
    V, N, T = [], [], []
    for i in range(seg):
        a0, a1 = 2*math.pi*i/seg, 2*math.pi*(i+1)/seg
        p = [(r*math.cos(a0), -h/2, r*math.sin(a0)), (r*math.cos(a1), -h/2, r*math.sin(a1)),
             (r2*math.cos(a1), h/2, r2*math.sin(a1)), (r2*math.cos(a0), h/2, r2*math.sin(a0))]
        n = [(math.cos(a0), 0, math.sin(a0)), (math.cos(a1), 0, math.sin(a1))]
        b = len(V); V += p; N += [n[0], n[1], n[1], n[0]]
        T += [(b, b+2, b+1), (b, b+3, b+2)]
        for y, sgn, rr in ((h/2, 1, r2), (-h/2, -1, r)):
            b = len(V)
            V += [(0, y, 0), (rr*math.cos(a0), y, rr*math.sin(a0)), (rr*math.cos(a1), y, rr*math.sin(a1))]
            N += [(0, sgn, 0)]*3
            T += [(b, b+2, b+1)] if sgn > 0 else [(b, b+1, b+2)]
    return np.array(V, float), np.array(N, float), np.array(T)

def sphere(r, seg=24, ring=16, hemi=False):
    V, N, T = [], [], []
    rings = ring
    for j in range(rings+1):
        th = math.pi*j/rings
        if hemi: th = (math.pi/2)*j/rings
        for i in range(seg+1):
            ph = 2*math.pi*i/seg
            n = (math.sin(th)*math.cos(ph), math.cos(th), math.sin(th)*math.sin(ph))
            V.append((n[0]*r, n[1]*r, n[2]*r)); N.append(n)
    for j in range(rings):
        for i in range(seg):
            a = j*(seg+1)+i; b = a+seg+1
            T += [(a, a+1, b), (a+1, b+1, b)]
    return np.array(V, float), np.array(N, float), np.array(T)

def capsule(r, h, seg=20):
    # h — полная высота
    cyl_h = max(h - 2*r, 0.001)
    parts = [cylinder(r, cyl_h, seg)]
    top = sphere(r, seg, 8, hemi=True); top[0][:, 1] += cyl_h/2
    bot = sphere(r, seg, 8, hemi=True); bot[0][:, 1] *= -1; bot[1][:, 1] *= -1; bot[0][:, 1] -= cyl_h/2
    bot = (bot[0], bot[1], bot[2][:, ::-1])
    return merge(parts + [top, bot])

def merge(parts):
    V, N, T, o = [], [], [], 0
    for v, n, t in parts:
        V.append(v); N.append(n); T.append(t+o); o += len(v)
    return np.vstack(V), np.vstack(N), np.vstack(T)

def rot(ax, a):
    c, s = math.cos(a), math.sin(a)
    if ax == 'x': return np.array([[1,0,0],[0,c,-s],[0,s,c]])
    if ax == 'y': return np.array([[c,0,s],[0,1,0],[-s,0,c]])
    return np.array([[c,-s,0],[s,c,0],[0,0,1]])

class Scene:
    def __init__(self): self.objs = []
    def add(self, mesh, color, pos=(0,0,0), R=None, scale=(1,1,1), rough=0.6, metal=0.0, emit=0.0, glass=False):
        v, n, t = mesh
        S = np.diag(scale)
        R = np.eye(3) if R is None else R
        v2 = (R @ (S @ v.T)).T + np.array(pos)
        n2 = (R @ (np.linalg.inv(S).T @ n.T)).T
        n2 /= np.linalg.norm(n2, axis=1, keepdims=True)+1e-9
        self.objs.append((v2, n2, t, np.array(color, float), rough, metal, emit, glass))

# ---------- рендер ----------
def sky(d):
    y = np.clip(d[..., 1], -1, 1)
    top = np.array([0.32, 0.52, 0.85]); hor = np.array([0.85, 0.88, 0.92]); gnd = np.array([0.25, 0.24, 0.23])
    t = np.clip(y, 0, 1)[..., None]
    up = hor*(1-t)**3 + top*(1-(1-t)**3)
    return np.where(y[..., None] >= 0, up, gnd*0.8 + hor*0.2*np.clip(1+y, 0, 1)[..., None])

def render(scene, cam_pos, target, W=1000, H=640, fov=32, ss=2, title=""):
    W2, H2 = W*ss, H*ss
    cam_pos = np.array(cam_pos, float); target = np.array(target, float)
    f = target - cam_pos; f /= np.linalg.norm(f)
    r = np.cross(f, [0,1,0]); r /= np.linalg.norm(r); u = np.cross(r, f)
    focal = (H2/2)/math.tan(math.radians(fov)/2)
    img = np.zeros((H2, W2, 3))
    # фон: студийный градиент
    yy = np.linspace(0, 1, H2)[:, None, None]
    img[:] = np.array([0.80, 0.82, 0.86])*(1-yy) + np.array([0.55, 0.56, 0.6])*yy
    zbuf = np.full((H2, W2), np.inf)
    sun = np.array([-0.5, 0.8, 0.35]); sun /= np.linalg.norm(sun)
    # пол с мягкой тенью
    def project(p):
        d = p - cam_pos
        x = d @ r; y = d @ u; z = d @ f
        return np.stack([W2/2 + focal*x/z, H2/2 - focal*y/z, z], -1)
    # тени: проекция объектов на пол вдоль sun → маска
    shadow = Image.new('L', (W2, H2), 0); sd = ImageDraw.Draw(shadow)
    floor_pts = []
    for v, n, t, col, rough, metal, emit, glass in scene.objs:
        sp = v - np.outer(v[:, 1]/sun[1], sun)
        sp[:, 1] = 0.0
        pr = project(sp)
        for tri in t:
            pts = [tuple(pr[i][:2]) for i in tri]
            sd.polygon(pts, fill=255)
    from PIL import ImageFilter
    shadow = shadow.filter(ImageFilter.GaussianBlur(6*ss))
    sh = np.asarray(shadow, float)/255.0
    # пол — бесконечная плоскость: затемняем фон ниже горизонта
    jj, ii = np.mgrid[0:H2, 0:W2]
    dirs = (ii[..., None]-W2/2)/focal*r + -(jj[..., None]-H2/2)/focal*u + f
    tpl = -cam_pos[1]/np.where(np.abs(dirs[..., 1]) < 1e-6, -1e-6, dirs[..., 1])
    hit = tpl > 0
    dist = np.where(hit, tpl, 1e9)
    fade = np.clip(1 - dist/40.0, 0, 1)
    floor_col = np.array([0.62, 0.63, 0.66])
    fc = floor_col[None, None, :]*(1-0.55*sh[..., None])
    img = np.where(hit[..., None], img*(1-fade[..., None]) + fc*fade[..., None], img)
    zbuf = np.where(hit, dist*np.linalg.norm(dirs, axis=-1)*0+1e8, np.inf)

    for v, n, t, col, rough, metal, emit, glass in scene.objs:
        pr = project(v)
        for tri in t:
            p = pr[tri]
            if np.any(p[:, 2] <= 0.05): continue
            xmin = max(int(math.floor(p[:, 0].min())), 0); xmax = min(int(math.ceil(p[:, 0].max())), W2-1)
            ymin = max(int(math.floor(p[:, 1].min())), 0); ymax = min(int(math.ceil(p[:, 1].max())), H2-1)
            if xmin > xmax or ymin > ymax: continue
            (x0, y0, z0), (x1, y1, z1), (x2, y2, z2) = p
            den = (y1-y2)*(x0-x2) + (x2-x1)*(y0-y2)
            if abs(den) < 1e-9: continue
            X, Y = np.meshgrid(np.arange(xmin, xmax+1)+0.5, np.arange(ymin, ymax+1)+0.5)
            a = ((y1-y2)*(X-x2) + (x2-x1)*(Y-y2))/den
            b = ((y2-y0)*(X-x2) + (x0-x2)*(Y-y2))/den
            c = 1-a-b
            m = (a >= -1e-4) & (b >= -1e-4) & (c >= -1e-4)
            if not m.any(): continue
            z = 1/(a/z0 + b/z1 + c/z2)
            zb = zbuf[ymin:ymax+1, xmin:xmax+1]
            m &= z < zb
            if not m.any(): continue
            nn = (a[..., None]*n[tri[0]]/z0 + b[..., None]*n[tri[1]]/z1 + c[..., None]*n[tri[2]]/z2)*z[..., None]
            nn /= np.linalg.norm(nn, axis=-1, keepdims=True)+1e-9
            wp = (a[..., None]*v[tri[0]]/z0 + b[..., None]*v[tri[1]]/z1 + c[..., None]*v[tri[2]]/z2)*z[..., None]
            vd = cam_pos - wp; vd /= np.linalg.norm(vd, axis=-1, keepdims=True)
            ndl = np.clip((nn*sun).sum(-1), 0, 1)[..., None]
            hv = sun + vd; hv /= np.linalg.norm(hv, axis=-1, keepdims=True)
            spec_pow = 2/(max(rough, 0.03)**2*1.2)
            spec = np.clip((nn*hv).sum(-1), 0, 1)[..., None]**spec_pow * (1.0-rough)*1.5
            refl = 2*(nn*vd).sum(-1, keepdims=True)*nn - vd
            env = sky(refl)
            fres = 0.04 + 0.96*(1-np.clip((nn*vd).sum(-1), 0, 1))[..., None]**5
            amb = sky(nn)*0.45
            diffc = col*(1-metal)
            f0 = 0.04*(1-metal) + col*metal
            kr = (f0 + (1-f0)*fres)*(1-rough*0.85)
            if glass: diffc = col*0.15; kr = np.clip(kr*2.2, 0, 1)
            colr = diffc*(ndl*1.1 + amb) + kr*env + spec*(f0+0.3)
            colr += col*emit
            zb[m] = z[m]
            sub = img[ymin:ymax+1, xmin:xmax+1]
            sub[m] = colr[m]
    # тонмаппинг
    img = 1 - np.exp(-img*1.25)
    img = np.clip(img, 0, 1)**(1/1.1)
    im = Image.fromarray((img*255).astype(np.uint8)).resize((W, H), Image.LANCZOS)
    if title:
        d = ImageDraw.Draw(im)
        try: font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 26)
        except Exception: font = ImageFont.load_default()
        d.text((24, 18), title, fill=(25, 25, 30), font=font)
    return im


def smooth_normals(V, T):
    N = np.zeros_like(V)
    fn = np.cross(V[T[:, 1]]-V[T[:, 0]], V[T[:, 2]]-V[T[:, 0]])
    for k in range(3):
        np.add.at(N, T[:, k], fn)
    N /= np.linalg.norm(N, axis=1, keepdims=True)+1e-9
    return N


def loft(sections, ring=28, power=4.0, flat_bottom=False, cap=True):
    """sections: список (z, y_bot, y_top, half_w_bot, half_w_top). Сечение — суперэллипс
    с сужением кверху (tumblehome). Возвращает гладкий меш."""
    V, T = [], []
    for (z, yb, yt, wb, wt) in sections:
        cy, b = (yb+yt)/2, (yt-yb)/2
        for i in range(ring):
            a = 2*math.pi*i/ring
            c, s = math.cos(a), math.sin(a)
            x = math.copysign(abs(c)**(2/power), c)
            y = math.copysign(abs(s)**(2/power), s)
            if flat_bottom and y < 0:
                y = max(y, -1.0)
            tt = (y+1)/2
            hw = wb*(1-tt) + wt*tt
            V.append((x*hw, cy+y*b, z))
    n = len(sections)
    for j in range(n-1):
        for i in range(ring):
            a = j*ring+i; b = j*ring+(i+1) % ring
            c = (j+1)*ring+i; d = (j+1)*ring+(i+1) % ring
            T += [(a, c, b), (b, c, d)]
    V = np.array(V, float)
    if cap:
        for j in (0, n-1):
            ctr = V[j*ring:(j+1)*ring].mean(0)
            ci = len(V); V = np.vstack([V, ctr])
            for i in range(ring):
                a = j*ring+i; b = j*ring+(i+1) % ring
                T.append((ci, b, a) if j == 0 else (ci, a, b))
    T = np.array(T)
    # ориентация: проверяем, что нормали наружу
    Nn = smooth_normals(V, T)
    ctr = V.mean(0)
    if np.mean(np.sum((V-ctr)*Nn, 1)) < 0:
        T = T[:, ::-1]; Nn = -Nn
    return V, Nn, T


def ellipsoid(rx, ry, rz, seg=24, rings=16):
    v, n, t = sphere(1.0, seg, rings)
    v = v*np.array([rx, ry, rz])
    n = n/np.array([rx, ry, rz]); n /= np.linalg.norm(n, axis=1, keepdims=True)+1e-9
    return v, n, t


def limb(r0, r1, length, seg=16):
    """Конусный цилиндр от y=0 вниз на length с шарами на концах."""
    v, n, t = cylinder(r0, length, seg, r2=None)
    # сужение: нижний радиус r1
    lo = v[:, 1] < 0
    v[lo, 0] *= r1/r0; v[lo, 2] *= r1/r0
    v[:, 1] -= length/2
    s0 = sphere(r0, seg, 10); s1 = sphere(r1, seg, 10); s1[0][:, 1] -= length
    return merge([(v, n, t), s0, s1])
