extends RefCounted
## Процедурные модели: машины (лофт кузова) и люди. Меши кешируются и
## объединяются по материалам, чтобы было мало draw calls на телефоне.
## Если в res://models/ лежит <kind>.glb — используется он (замена на готовые модели).

static var _mats := {}
static var _car_cache := {}
static var _wheel_cache := {}
static var _human_cache := {}


# ---------------- Материалы ----------------
static func mat(color: Color, rough := 0.7, metal := 0.0, emit := 0.0) -> StandardMaterial3D:
	var key = "%s|%.2f|%.2f|%.2f" % [color.to_html(), rough, metal, emit]
	if _mats.has(key):
		return _mats[key]
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	_mats[key] = m
	return m


static func paint_mat(color: Color) -> StandardMaterial3D:
	var key = "paint|" + color.to_html()
	if _mats.has(key):
		return _mats[key]
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = 0.55
	m.roughness = 0.22
	m.clearcoat_enabled = true
	m.clearcoat = 1.0
	m.clearcoat_roughness = 0.08
	_mats[key] = m
	return m


static func glass_mat() -> StandardMaterial3D:
	if _mats.has("glass"):
		return _mats["glass"]
	var m = StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.07, 0.09)
	m.metallic = 0.9
	m.roughness = 0.04
	_mats["glass"] = m
	return m


# ---------------- Геометрия ----------------
## Лофт: сечения [z, y_низ, y_верх, полуширина_низ, полуширина_верх] по возрастанию z.
static func loft(sections: Array, ring := 28, power := 4.0) -> ArrayMesh:
	var rings: Array = []
	var axis: Array = []
	for sec in sections:
		var z: float = sec[0]
		var yb: float = sec[1]
		var yt: float = sec[2]
		var wb: float = sec[3]
		var wt: float = sec[4]
		var cy = (yb + yt) * 0.5
		var b = (yt - yb) * 0.5
		var rp = PackedVector3Array()
		for i in ring:
			var a = TAU * float(i) / float(ring)
			var c = cos(a)
			var s = sin(a)
			var x = signf(c) * pow(absf(c), 2.0 / power)
			var y = signf(s) * pow(absf(s), 2.0 / power)
			var hw: float = lerp(wb, wt, (y + 1.0) * 0.5)
			rp.append(Vector3(x * hw, cy + y * b, z))
		rings.append(rp)
		axis.append(Vector3(0, cy, z))
	var n = rings.size()
	# нормали
	var norms: Array = []
	for j in n:
		var arr = PackedVector3Array()
		arr.resize(ring)
		norms.append(arr)
	for j in n - 1:
		for i in ring:
			var i2 = (i + 1) % ring
			var a: Vector3 = rings[j][i]
			var b2: Vector3 = rings[j][i2]
			var c2: Vector3 = rings[j + 1][i]
			var fn = (c2 - a).cross(b2 - a)
			var ax: Vector3 = axis[j]
			if fn.dot(a - ax) < 0.0:
				fn = -fn
			for pair in [[j, i], [j, i2], [j + 1, i], [j + 1, i2]]:
				var pj: int = pair[0]
				var pi: int = pair[1]
				var arr2: PackedVector3Array = norms[pj]
				arr2[pi] = arr2[pi] + fn
				norms[pj] = arr2
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in n - 1:
		var axm: Vector3 = (axis[j] + axis[j + 1]) * 0.5
		for i in ring:
			var i2 = (i + 1) % ring
			var quad = [[j, i], [j + 1, i], [j, i2], [j, i2], [j + 1, i], [j + 1, i2]]
			for t in 2:
				var v: Array = []
				var nn: Array = []
				for k in 3:
					var q: Array = quad[t * 3 + k]
					v.append(rings[q[0]][q[1]])
					nn.append((norms[q[0]][q[1]] as Vector3).normalized())
				_emit_tri(st, v, nn, ((v[0] + v[1] + v[2]) / 3.0) - axm)
	# торцы
	for j in [0, n - 1]:
		var ctr: Vector3 = Vector3.ZERO
		for p in rings[j]:
			ctr += p
		ctr /= float(ring)
		var out = Vector3(0, 0, -1) if j == 0 else Vector3(0, 0, 1)
		for i in ring:
			var i2 = (i + 1) % ring
			_emit_tri(st, [ctr, rings[j][i], rings[j][i2]], [out, out, out], out)
	return st.commit()


## Godot: лицевая сторона — по часовой стрелке. Разворачиваем треугольник наружу.
static func _emit_tri(st: SurfaceTool, v: Array, nn: Array, outward: Vector3) -> void:
	var a: Vector3 = v[0]
	var b: Vector3 = v[1]
	var c: Vector3 = v[2]
	var order = [0, 1, 2]
	if (b - a).cross(c - a).dot(outward) < 0.0:
		order = [0, 2, 1]
	for k in order:
		st.set_normal(nn[k])
		st.add_vertex(v[k])


static func box(sx: float, sy: float, sz: float) -> BoxMesh:
	var m = BoxMesh.new()
	m.size = Vector3(sx, sy, sz)
	return m


static func cyl(r: float, h: float, r2 := -1.0, seg := 20) -> CylinderMesh:
	var m = CylinderMesh.new()
	m.bottom_radius = r
	m.top_radius = r if r2 < 0.0 else r2
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	return m


static func sph(r: float, seg := 16) -> SphereMesh:
	var m = SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = seg
	m.rings = seg / 2
	return m


## Сборщик: части группируются по материалу и сливаются в одну ArrayMesh.
class Builder:
	var tools = {}
	var order: Array = []

	func add(group: String, mesh: Mesh, xf: Transform3D) -> void:
		if not tools.has(group):
			var st = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[group] = st
			order.append(group)
		var s: SurfaceTool = tools[group]
		s.append_from(mesh, 0, xf)

	func commit() -> Dictionary:
		var am = ArrayMesh.new()
		var groups: Array = []
		for g in order:
			var s: SurfaceTool = tools[g]
			s.commit(am)
			groups.append(g)
		return {"mesh": am, "groups": groups}


static func T(pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> Transform3D:
	var b = Basis.from_euler(rot).scaled(scl)
	return Transform3D(b, pos)


# ---------------- Машины ----------------
const CARS := {
	"sedan": {"L": 4.7, "W": 1.84, "wr": 0.33, "wb": 1.38, "mass": 1300.0, "force": 5200.0, "vmax": 46.0,
		"body": [[-1.0, .40, .78, .80], [-.985, .30, .92, .88], [-.90, .27, .985, .915], [-.55, .25, .99, .92],
			[-.45, .25, .985, .92], [0.0, .25, .955, .92], [.42, .25, .93, .92], [.55, .26, .915, .915],
			[.85, .27, .875, .905], [.96, .31, .82, .88], [1.0, .40, .74, .82]],
		"glass": [[-.60, .97, .82], [-.58, 1.02, .80], [-.50, 1.27, .75], [-.30, 1.40, .73], [.16, 1.38, .74], [.42, 1.02, .80], [.47, .955, .83]]},
	"sport": {"L": 4.45, "W": 1.96, "wr": 0.34, "wb": 1.34, "mass": 1250.0, "force": 8500.0, "vmax": 70.0,
		"body": [[-1.0, .34, .70, .88], [-.98, .24, .82, .95], [-.85, .21, .86, .98], [-.3, .2, .82, .98], [.2, .2, .76, .97],
			[.6, .21, .70, .96], [.9, .22, .62, .93], [1.0, .30, .55, .86]],
		"glass": [[-.68, .84, .84], [-.62, .88, .80], [-.32, 1.16, .70], [.02, 1.17, .72], [.28, .86, .82], [.35, .79, .86]]},
	"suv": {"L": 4.85, "W": 2.0, "wr": 0.41, "wb": 1.48, "mass": 1900.0, "force": 7200.0, "vmax": 44.0,
		"body": [[-1.0, .55, 1.0, .88], [-.98, .44, 1.13, .96], [-.9, .42, 1.17, .98], [0.0, .40, 1.16, .99], [.55, .40, 1.12, .99],
			[.85, .42, 1.08, .97], [.97, .46, 1.0, .94], [1.0, .55, .92, .88]],
		"glass": [[-.95, 1.17, .9], [-.92, 1.64, .82], [-.8, 1.74, .80], [.30, 1.72, .80], [.52, 1.22, .87], [.58, 1.14, .9]]},
	"van": {"L": 5.3, "W": 2.05, "wr": 0.37, "wb": 1.62, "mass": 2300.0, "force": 6800.0, "vmax": 36.0,
		"body": [[-1.0, .42, 2.05, .99], [-.98, .36, 2.12, 1.0], [.55, .36, 2.12, 1.0], [.62, .37, 1.05, 1.0], [.88, .38, 1.0, .98],
			[.98, .42, .92, .95], [1.0, .5, .82, .9]],
		"glass": [[.46, 1.05, .97], [.50, 1.70, .93], [.56, 1.70, .93], [.62, 1.10, .95], [.66, 1.02, .97]]},
}


static func car_base(kind: String) -> String:
	if kind == "police" or kind == "taxi":
		return "sedan"
	return kind


static func car_spec(kind: String) -> Dictionary:
	return CARS[car_base(kind)]


## Возвращает Node3D с мешем кузова (без колёс). Поверхность «paint» перекрашивается.
static func make_car_body(kind: String, paint: Color) -> Node3D:
	var root = Node3D.new()
	root.name = "Body"
	var glb = "res://models/%s.glb" % kind
	if ResourceLoader.exists(glb):
		var scene = load(glb)
		if scene is PackedScene:
			root.add_child(scene.instantiate())
			return root
	var data: Dictionary
	if _car_cache.has(kind):
		data = _car_cache[kind]
	else:
		data = _build_car(kind)
		_car_cache[kind] = data
	var mi = MeshInstance3D.new()
	mi.mesh = data["mesh"]
	var groups: Array = data["groups"]
	for i in groups.size():
		var g: String = groups[i]
		var m: Material = _group_mat(g)
		if g == "paint":
			m = paint_mat(paint)
		mi.set_surface_override_material(i, m)
	root.add_child(mi)
	return root


static func _group_mat(g: String) -> Material:
	match g:
		"glass":
			return glass_mat()
		"white":
			return paint_mat(Color(0.92, 0.92, 0.94))
		"dark":
			return mat(Color(0.05, 0.05, 0.055), 0.55)
		"black":
			return mat(Color(0.02, 0.02, 0.02), 0.35, 0.3)
		"chrome":
			return mat(Color(0.75, 0.75, 0.78), 0.12, 1.0)
		"head":
			return mat(Color(1.0, 0.97, 0.88), 0.05, 0.0, 1.5)
		"tail":
			return mat(Color(0.75, 0.04, 0.03), 0.1, 0.0, 1.2)
		"plate":
			return mat(Color(0.94, 0.94, 0.92), 0.5)
		"lightR":
			return mat(Color(1.0, 0.08, 0.05), 0.1, 0.0, 3.0)
		"lightB":
			return mat(Color(0.1, 0.3, 1.0), 0.1, 0.0, 3.0)
		"taxi":
			return mat(Color(1.0, 0.95, 0.7), 0.3, 0.0, 1.5)
	return mat(Color.GRAY)


static func _build_car(kind: String) -> Dictionary:
	var base = car_base(kind)
	var s: Dictionary = CARS[base]
	var L: float = s["L"]
	var W: float = s["W"]
	var hl = L / 2.0
	var hw = W / 2.0
	var bld = Builder.new()
	var I = Transform3D.IDENTITY
	var secs: Array = []
	for b in s["body"]:
		secs.append([b[0] * hl, b[1], b[2], b[3] * hw, b[3] * hw * 0.965])
	bld.add("paint", loft(secs, 36, 5.0), I)
	if kind == "police":
		var mid: Array = []
		for b in s["body"]:
			if b[0] >= -0.46 and b[0] <= 0.43:
				mid.append([b[0] * hl, b[1] + 0.08, b[2] - 0.06, b[3] * hw + 0.014, b[3] * hw * 0.965 + 0.014])
		if mid.size() >= 2:
			mid[0][0] = -0.45 * hl
			mid[mid.size() - 1][0] = 0.42 * hl
			bld.add("white", loft(mid, 36, 5.0), I)
	var gsecs: Array = []
	var yb = 0.80 if base != "van" else 0.95
	var top_y = 0.0
	var gz_min = 99.0
	var gz_max = -99.0
	for g in s["glass"]:
		gsecs.append([g[0] * hl, yb, g[1], g[2] * hw, g[2] * hw * 0.80])
		top_y = max(top_y, g[1])
		gz_min = min(gz_min, g[0] * hl)
		gz_max = max(gz_max, g[0] * hl)
	bld.add("glass", loft(gsecs, 32, 4.0), I)
	var rs: Array = []
	for i in range(1, gsecs.size() - 1):
		var q: Array = gsecs[i]
		if q[2] > top_y - 0.08:
			rs.append([q[0], q[2] - 0.05, q[2] + 0.014, q[4] * 0.98, q[4] * 0.93])
	if rs.size() >= 2:
		bld.add("white" if kind == "police" else "paint", loft(rs, 24, 6.0), I)
	# детали
	for sd in [-1.0, 1.0]:
		bld.add("chrome", box(0.012, 0.025, 0.12), T(Vector3(sd * (hw * 0.925 + 0.006), 0.78, 0.2)))
		bld.add("chrome", box(0.012, 0.025, 0.12), T(Vector3(sd * (hw * 0.925 + 0.006), 0.78, -0.75)))
		var my = 0.98
		if base == "sport":
			my = 0.86
		elif base == "suv":
			my = 1.2
		bld.add("paint", sph(0.06, 10), T(Vector3(sd * (hw * 0.86 + 0.04), my, gz_max - 0.2), Vector3.ZERO, Vector3(0.75, 0.8, 1.3)))
		var dh = 0.5 if base != "van" else 0.7
		var dy = 0.62 if base != "van" else 0.75
		for dz in [-0.25, 0.68 if base != "van" else 1.3]:
			bld.add("dark", box(0.006, dh, 0.008), T(Vector3(sd * hw * 0.928, dy, dz)))
	var fy = 0.62
	if base == "sport":
		fy = 0.55
	elif base == "suv":
		fy = 0.82
	elif base == "van":
		fy = 0.72
	var by = 0.36 if base != "suv" else 0.5
	for sd in [-1.0, 1.0]:
		bld.add("head", box(0.36, 0.11, 0.06), T(Vector3(sd * (hw - 0.32), fy, hl - 0.03)))
		bld.add("tail", box(0.30, 0.10, 0.06), T(Vector3(sd * (hw - 0.27), fy + 0.08, -hl + 0.04)))
	bld.add("black", box(W * 0.36, 0.13, 0.05), T(Vector3(0, fy - 0.02, hl - 0.005)))
	bld.add("chrome", box(W * 0.37, 0.02, 0.055), T(Vector3(0, fy + 0.055, hl - 0.003)))
	bld.add("dark", box(W * 0.9, 0.17, 0.08), T(Vector3(0, by, hl + 0.01)))
	bld.add("dark", box(W * 0.9, 0.17, 0.08), T(Vector3(0, by, -hl - 0.01)))
	bld.add("plate", box(0.42, 0.11, 0.012), T(Vector3(0, by + 0.06, hl + 0.055)))
	bld.add("plate", box(0.42, 0.11, 0.012), T(Vector3(0, by + 0.2, -hl - 0.005)))
	# колёсные арки
	var wr: float = s["wr"]
	var wb: float = s["wb"]
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			bld.add("black", cyl(wr + 0.07, 0.03, -1.0, 18), T(Vector3(sx * hw * 0.93, wr + 0.02, sz * wb), Vector3(0, 0, PI / 2)))
	if kind == "police":
		bld.add("dark", box(1.15, 0.09, 0.30), T(Vector3(0, top_y + 0.06, -0.15)))
		bld.add("lightR", box(0.5, 0.09, 0.26), T(Vector3(-0.29, top_y + 0.11, -0.15)))
		bld.add("lightB", box(0.5, 0.09, 0.26), T(Vector3(0.29, top_y + 0.11, -0.15)))
		bld.add("dark", box(1.1, 0.30, 0.06), T(Vector3(0, 0.55, hl + 0.18)))
	elif kind == "taxi":
		bld.add("taxi", box(0.62, 0.17, 0.26), T(Vector3(0, top_y + 0.09, -0.15)))
	elif kind == "sport":
		bld.add("paint", box(W - 0.25, 0.035, 0.28), T(Vector3(0, 0.98, -hl + 0.25)))
		for sd in [-1.0, 1.0]:
			bld.add("dark", box(0.05, 0.2, 0.06), T(Vector3(sd * 0.6, 0.88, -hl + 0.25)))
	var d = bld.commit()
	d["top_y"] = top_y
	return d


## Колесо: ось вдоль X. Возвращает Node3D.
static func make_wheel(wr: float) -> Node3D:
	var key = "%.2f" % wr
	var data: Dictionary
	if _wheel_cache.has(key):
		data = _wheel_cache[key]
	else:
		var bld = Builder.new()
		var rz = Vector3(0, 0, PI / 2)
		bld.add("tire", cyl(wr, 0.23, -1.0, 22), T(Vector3.ZERO, rz))
		bld.add("rim", cyl(wr * 0.66, 0.235, -1.0, 18), T(Vector3.ZERO, rz))
		for k in 5:
			var a = TAU * k / 5.0
			bld.add("rim", box(0.02, wr * 0.55, 0.06), T(Vector3(0.12, cos(a) * wr * 0.28, sin(a) * wr * 0.28), Vector3(-a, 0, 0)))
			bld.add("rim", box(0.02, wr * 0.55, 0.06), T(Vector3(-0.12, cos(a) * wr * 0.28, sin(a) * wr * 0.28), Vector3(-a, 0, 0)))
		bld.add("hub", cyl(wr * 0.15, 0.25, -1.0, 10), T(Vector3.ZERO, rz))
		data = bld.commit()
		_wheel_cache[key] = data
	var mi = MeshInstance3D.new()
	mi.mesh = data["mesh"]
	var groups: Array = data["groups"]
	for i in groups.size():
		var g: String = groups[i]
		var m = mat(Color(0.035, 0.035, 0.035), 0.85)
		if g == "rim":
			m = mat(Color(0.7, 0.71, 0.74), 0.15, 1.0)
		elif g == "hub":
			m = mat(Color(0.25, 0.25, 0.27), 0.2, 1.0)
		mi.set_surface_override_material(i, m)
	return mi


static func car_top_y(kind: String) -> float:
	if not _car_cache.has(kind):
		_car_cache[kind] = _build_car(kind)
	return _car_cache[kind]["top_y"]


# ---------------- Люди ----------------
const SKINS := [Color(0.86, 0.66, 0.53), Color(0.50, 0.35, 0.25), Color(0.93, 0.76, 0.64), Color(0.76, 0.56, 0.42), Color(0.36, 0.24, 0.17)]
const HAIRS := [Color(0.13, 0.09, 0.06), Color(0.04, 0.03, 0.02), Color(0.55, 0.40, 0.20), Color(0.18, 0.13, 0.09), Color(0.5, 0.5, 0.5)]
const TOPS := [Color(0.85, 0.85, 0.83), Color(0.70, 0.18, 0.15), Color(0.26, 0.38, 0.30), Color(0.18, 0.18, 0.19), Color(0.15, 0.25, 0.45), Color(0.6, 0.5, 0.35), Color(0.9, 0.75, 0.2)]
const PANTS := [Color(0.16, 0.22, 0.36), Color(0.08, 0.08, 0.09), Color(0.45, 0.39, 0.28), Color(0.30, 0.36, 0.52), Color(0.25, 0.25, 0.27)]


static func random_look(rng: RandomNumberGenerator) -> Dictionary:
	var jacket = null
	if rng.randf() < 0.3:
		jacket = [Color(0.1, 0.1, 0.11), Color(0.25, 0.18, 0.12), Color(0.2, 0.24, 0.2)][rng.randi() % 3]
	return {
		"skin": SKINS[rng.randi() % SKINS.size()],
		"hair": HAIRS[rng.randi() % HAIRS.size()],
		"shirt": TOPS[rng.randi() % TOPS.size()],
		"pants": PANTS[rng.randi() % PANTS.size()],
		"jacket": jacket,
		"sleeves": rng.randf() < 0.4,
		"cop": false,
	}


static func cop_look() -> Dictionary:
	return {"skin": SKINS[randi() % SKINS.size()], "hair": HAIRS[0], "shirt": Color(0.07, 0.11, 0.24),
		"pants": Color(0.05, 0.06, 0.11), "jacket": null, "sleeves": true, "cop": true}


## Человек: корень "Human" (вперёд -Z) с узлами-шарнирами hip_l/hip_r/sh_l/sh_r.
static func make_human(look: Dictionary) -> Node3D:
	var skin: Color = look["skin"]
	var shirt: Color = look["shirt"]
	var pants: Color = look["pants"]
	var hair: Color = look["hair"]
	var cop: bool = look["cop"]
	var top: Color = shirt
	if look["jacket"] != null:
		top = look["jacket"]
	var fore_is_skin: bool = not (look["sleeves"] or cop or look["jacket"] != null)
	var root = Node3D.new()
	root.name = "Human"
	var inner = Node3D.new()
	inner.name = "Inner"
	inner.rotation.y = PI
	root.add_child(inner)
	var M = {
		"skin": mat(skin, 0.5), "top": mat(top, 0.85), "shirt": mat(shirt, 0.85), "pants": mat(pants, 0.9),
		"hair": mat(hair, 0.8), "shoe": mat(Color(0.07, 0.065, 0.07), 0.35), "dark": mat(Color(0.03, 0.03, 0.03), 0.35),
		"gold": mat(Color(0.9, 0.72, 0.25), 0.2, 1.0), "eye": mat(Color(0.05, 0.04, 0.04), 0.1),
		"cap": mat(Color(0.05, 0.07, 0.15), 0.6),
	}
	var key = "body|%s|%s|%s|%s|%s|%s" % [skin.to_html(), top.to_html(), shirt.to_html(), pants.to_html(), hair.to_html(), cop]
	var body: Dictionary
	if _human_cache.has(key):
		body = _human_cache[key]
	else:
		var bld = Builder.new()
		var RX = Vector3(-PI / 2, 0, 0)
		bld.add("pants", loft([[0.84, -0.10, 0.10, 0.16, 0.16], [0.92, -0.115, 0.115, 0.175, 0.175], [1.02, -0.11, 0.11, 0.165, 0.165]], 20, 2.6), T(Vector3.ZERO, RX))
		bld.add("top", loft([[1.0, -0.112, 0.112, 0.168, 0.168], [1.12, -0.10, 0.11, 0.152, 0.152], [1.28, -0.11, 0.125, 0.172, 0.172],
			[1.42, -0.105, 0.115, 0.198, 0.198], [1.50, -0.085, 0.09, 0.19, 0.19], [1.555, -0.05, 0.055, 0.08, 0.08]], 24, 2.6), T(Vector3.ZERO, RX))
		if look["jacket"] != null:
			bld.add("shirt", box(0.07, 0.38, 0.02), T(Vector3(0, 1.30, 0.11)))
		bld.add("skin", cyl(0.055, 0.12, 0.05, 12), T(Vector3(0, 1.6, -0.005)))
		bld.add("skin", sph(1.0, 18), T(Vector3(0, 1.715, 0), Vector3.ZERO, Vector3(0.093, 0.118, 0.108)))
		bld.add("skin", sph(1.0, 14), T(Vector3(0, 1.655, 0.012), Vector3.ZERO, Vector3(0.07, 0.05, 0.078)))
		bld.add("skin", sph(1.0, 8), T(Vector3(0, 1.69, 0.108), Vector3.ZERO, Vector3(0.017, 0.03, 0.022)))
		for s in [-1.0, 1.0]:
			bld.add("skin", sph(1.0, 8), T(Vector3(s * 0.093, 1.70, -0.005), Vector3.ZERO, Vector3(0.015, 0.03, 0.02)))
			bld.add("eye", sph(0.011, 6), T(Vector3(s * 0.035, 1.725, 0.094)))
			bld.add("hair", box(0.04, 0.009, 0.01), T(Vector3(s * 0.036, 1.748, 0.1)))
		if cop:
			bld.add("cap", cyl(0.104, 0.07, -1.0, 16), T(Vector3(0, 1.81, -0.005)))
			bld.add("dark", cyl(0.1, 0.015, -1.0, 16), T(Vector3(0, 1.778, 0.06), Vector3.ZERO, Vector3(1, 1, 0.9)))
			bld.add("gold", box(0.04, 0.03, 0.01), T(Vector3(0, 1.81, 0.104)))
			bld.add("dark", loft([[1.03, -0.118, 0.118, 0.172, 0.172], [1.09, -0.118, 0.118, 0.172, 0.172]], 20, 2.6), T(Vector3.ZERO, RX))
			bld.add("gold", box(0.05, 0.06, 0.012), T(Vector3(0.09, 1.36, 0.118)))
			bld.add("dark", box(0.06, 0.14, 0.07), T(Vector3(0.19, 1.0, 0.0)))
		else:
			bld.add("hair", sph(1.0, 16), T(Vector3(0, 1.765, -0.012), Vector3.ZERO, Vector3(0.1, 0.085, 0.112)))
			bld.add("hair", sph(1.0, 12), T(Vector3(0, 1.71, -0.06), Vector3.ZERO, Vector3(0.095, 0.08, 0.06)))
		body = bld.commit()
		_human_cache[key] = body
	inner.add_child(_mi_from(body, M))
	# ноги
	for s in [-1.0, 1.0]:
		var hip = Node3D.new()
		hip.name = "hip_l" if s < 0 else "hip_r"
		hip.position = Vector3(s * 0.095, 0.93, 0)
		inner.add_child(hip)
		var lk = "leg|%s" % pants.to_html()
		var leg: Dictionary
		if _human_cache.has(lk):
			leg = _human_cache[lk]
		else:
			var b2 = Builder.new()
			b2.add("pants", cyl(0.066, 0.45, 0.088, 14), T(Vector3(0, -0.225, 0)))
			b2.add("pants", sph(0.07, 10), T(Vector3(0, -0.45, 0)))
			b2.add("pants", cyl(0.046, 0.43, 0.064, 14), T(Vector3(0.002, -0.665, 0.005)))
			b2.add("shoe", sph(1.0, 12), T(Vector3(0.003, -0.885, 0.035), Vector3.ZERO, Vector3(0.052, 0.045, 0.125)))
			leg = b2.commit()
			_human_cache[lk] = leg
		hip.add_child(_mi_from(leg, M))
		var sh = Node3D.new()
		sh.name = "sh_l" if s < 0 else "sh_r"
		sh.position = Vector3(s * 0.205, 1.47, -0.005)
		inner.add_child(sh)
		var ak = "arm|%s|%s|%s|%s" % [top.to_html(), skin.to_html(), fore_is_skin, s]
		var arm: Dictionary
		if _human_cache.has(ak):
			arm = _human_cache[ak]
		else:
			var b3 = Builder.new()
			b3.add("top", sph(0.058, 10), T(Vector3.ZERO))
			b3.add("top", cyl(0.045, 0.29, 0.056, 12), T(Vector3(s * 0.015, -0.145, 0), Vector3(0, 0, s * 0.1)))
			b3.add("skin" if fore_is_skin else "top", cyl(0.034, 0.27, 0.044, 12), T(Vector3(s * 0.03, -0.42, 0.005)))
			b3.add("skin", sph(1.0, 10), T(Vector3(s * 0.04, -0.59, 0.01), Vector3.ZERO, Vector3(0.028, 0.06, 0.045)))
			arm = b3.commit()
			_human_cache[ak] = arm
		sh.add_child(_mi_from(arm, M))
	return root


static func _mi_from(data: Dictionary, M: Dictionary) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	mi.mesh = data["mesh"]
	var groups: Array = data["groups"]
	for i in groups.size():
		var g: String = groups[i]
		if M.has(g):
			mi.set_surface_override_material(i, M[g])
	return mi


## Анимация ходьбы/бега: phase — фаза шага, amt — амплитуда (0..1.2).
static func animate_human(h: Node3D, phase: float, amt: float, aiming := false) -> void:
	var inner = h.get_node_or_null("Inner")
	if inner == null:
		return
	var sw = sin(phase) * amt
	var hl: Node3D = inner.get_node("hip_l")
	var hr: Node3D = inner.get_node("hip_r")
	var sl: Node3D = inner.get_node("sh_l")
	var sr: Node3D = inner.get_node("sh_r")
	hl.rotation.x = sw * 0.6
	hr.rotation.x = -sw * 0.6
	sl.rotation.x = -sw * 0.5
	if aiming:
		sr.rotation.x = -1.45
	else:
		sr.rotation.x = sw * 0.5
	inner.position.y = absf(sin(phase)) * 0.03 * amt
