extends Node3D
## Генерация города: дороги, тротуары, здания с окнами, фонари, парки, реквизит.

const Models = preload("res://scripts/models.gd")

const N := 8          # кварталов по стороне
const P := 72.0       # шаг сетки дорог
const R := 14.0       # ширина дороги
const LANE := 4.6     # смещение полосы движения от оси
const CURB := 0.2     # высота тротуара

var half = N * P / 2.0
var rng = RandomNumberGenerator.new()
var lamp_positions: Array = []
var facade_mats: Array = []
var lamp_mat: StandardMaterial3D
var parks = {}
var special = {
	"mission_a": Vector2i(1, 1), "mission_b": Vector2i(6, 2), "mission_c": Vector2i(2, 6),
	"ammu": Vector2i(3, 2), "cars": Vector2i(5, 5), "garage": Vector2i(1, 4),
	"hospital": Vector2i(4, 3), "police": Vector2i(6, 6),
}
var mat_asphalt: StandardMaterial3D
var mat_walk: StandardMaterial3D
var mat_grass: StandardMaterial3D
var mat_roof: StandardMaterial3D
var mat_line_y: StandardMaterial3D
var mat_line_w: StandardMaterial3D


func _ready() -> void:
	rng.seed = 1337  # одинаковый город у всех игроков онлайн


# ---------------- Координаты ----------------
func node_pos(i: int, j: int) -> Vector3:
	return Vector3(i * P - half, 0.0, j * P - half)


func block_center(b: Vector2i) -> Vector3:
	return node_pos(b.x, b.y) + Vector3(P / 2.0, 0, P / 2.0)


func neighbors(n: Vector2i) -> Array:
	var res: Array = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var m: Vector2i = n + d
		if m.x >= 0 and m.y >= 0 and m.x <= N and m.y <= N:
			res.append(m)
	return res


func nearest_node(p: Vector3) -> Vector2i:
	var i = int(round((p.x + half) / P))
	var j = int(round((p.z + half) / P))
	return Vector2i(clampi(i, 0, N), clampi(j, 0, N))


func random_node_near(p: Vector3, rmin: float, rmax: float, r: RandomNumberGenerator):
	for t in 30:
		var n = Vector2i(r.randi_range(0, N), r.randi_range(0, N))
		var d = node_pos(n.x, n.y).distance_to(Vector3(p.x, 0, p.z))
		if d >= rmin and d <= rmax:
			return n
	return null


## Точка на тротуаре вокруг квартала (кольцо), возвращает [Vector3, Vector2i блок]
func random_sidewalk_near(p: Vector3, rmin: float, rmax: float, r: RandomNumberGenerator):
	for t in 30:
		var b = Vector2i(r.randi_range(0, N - 1), r.randi_range(0, N - 1))
		var corners = block_ring(b)
		var k = r.randi() % 4
		var a: Vector3 = corners[k]
		var c: Vector3 = corners[(k + 1) % 4]
		var pt = a.lerp(c, r.randf())
		var d = pt.distance_to(p)
		if d >= rmin and d <= rmax:
			return [pt, b, k]
	return null


func block_ring(b: Vector2i) -> Array:
	var c = block_center(b)
	var e = (P - R) / 2.0 - 1.3
	var y = CURB
	return [c + Vector3(-e, y, -e), c + Vector3(e, y, -e), c + Vector3(e, y, e), c + Vector3(-e, y, e)]


func special_pos(key: String) -> Vector3:
	var b: Vector2i = special[key]
	var c = block_center(b)
	return c + Vector3(0, CURB, (P - R) / 2.0 - 2.0)


func spawn_point() -> Vector3:
	return special_pos("hospital") + Vector3(3, 0.5, 0)


func road_point_near(p: Vector3) -> Transform3D:
	## Ближайшая точка на дороге (для спавна купленной машины)
	var n = nearest_node(p)
	var c = node_pos(n.x, n.y)
	var dir = Vector3(1, 0, 0)
	var pos = c + Vector3(R * 0.5 + 6.0, 0.6, LANE)
	return Transform3D(Basis.looking_at(-dir, Vector3.UP), pos)


# ---------------- Материалы ----------------
func _load_tex(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var bytes = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var img = Image.new()
	if img.load_jpg_from_buffer(bytes) != OK:
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _noise_mat(c1: Color, c2: Color, freq: float, scale: float, rough: float) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	var fn = FastNoiseLite.new()
	fn.frequency = freq
	fn.fractal_octaves = 5
	var nt = NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.noise = fn
	var g = Gradient.new()
	g.set_color(0, c1)
	g.set_color(1, c2)
	nt.color_ramp = g
	m.albedo_texture = nt
	var nn = NoiseTexture2D.new()
	nn.width = 256
	nn.height = 256
	nn.seamless = true
	nn.as_normal_map = true
	nn.bump_strength = 3.0
	nn.noise = fn
	m.normal_enabled = true
	m.normal_texture = nn
	m.roughness = rough
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _pbr_mat(slot: String, scale: float, fallback: StandardMaterial3D) -> StandardMaterial3D:
	var base = "res://assets/tex/%s_" % slot
	var d = _load_tex(base + "diff.jpgdata")
	if d == null:
		return fallback
	var m = StandardMaterial3D.new()
	m.albedo_texture = d
	var n = _load_tex(base + "nor.jpgdata")
	if n:
		m.normal_enabled = true
		m.normal_texture = n
	var r = _load_tex(base + "rough.jpgdata")
	if r:
		m.roughness_texture = r
		m.roughness = 1.0
	else:
		m.roughness = 0.85
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _facade(wall: Color, glass: Color, frame: float, lit: float, seed_i: int, metal := 0.15) -> StandardMaterial3D:
	var S = 256
	var cells = 4
	var cs = S / cells
	var alb = Image.create(S, S, false, Image.FORMAT_RGB8)
	var rgh = Image.create(S, S, false, Image.FORMAT_RGB8)
	var emi = Image.create(S, S, false, Image.FORMAT_RGB8)
	alb.fill(wall)
	rgh.fill(Color(0.88, 0.88, 0.88))
	emi.fill(Color.BLACK)
	var r = RandomNumberGenerator.new()
	r.seed = seed_i
	# лёгкая грязь/неоднородность стены
	for k in 600:
		var px = r.randi_range(0, S - 8)
		var py = r.randi_range(0, S - 8)
		alb.fill_rect(Rect2i(px, py, r.randi_range(2, 8), r.randi_range(2, 8)), wall.darkened(r.randf_range(0.02, 0.1)))
	for cy in cells:
		# межэтажный пояс
		alb.fill_rect(Rect2i(0, cy * cs, S, 3), wall.darkened(0.25))
		for cx in cells:
			var x0 = cx * cs + int(cs * frame)
			var y0 = cy * cs + int(cs * frame * 1.4)
			var w = cs - int(cs * frame * 2.0)
			var h = cs - int(cs * frame * 2.4)
			var g = glass.lerp(Color(0.55, 0.65, 0.75), r.randf() * 0.25)
			alb.fill_rect(Rect2i(x0 - 2, y0 - 2, w + 4, h + 4), wall.darkened(0.35))
			alb.fill_rect(Rect2i(x0, y0, w, h), g)
			alb.fill_rect(Rect2i(x0 + w / 2 - 1, y0, 2, h), wall.darkened(0.4))
			rgh.fill_rect(Rect2i(x0, y0, w, h), Color(0.06, 0.06, 0.06))
			if r.randf() < lit:
				var lc = Color(1.0, 0.8, 0.5).lerp(Color(0.85, 0.9, 1.0), r.randf() * 0.6)
				emi.fill_rect(Rect2i(x0, y0, w, h), lc * r.randf_range(0.6, 1.0))
	alb.generate_mipmaps()
	rgh.generate_mipmaps()
	emi.generate_mipmaps()
	var m = StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(alb)
	m.roughness_texture = ImageTexture.create_from_image(rgh)
	m.roughness = 1.0
	m.metallic = metal
	m.emission_enabled = true
	m.emission = Color.BLACK
	m.emission_texture = ImageTexture.create_from_image(emi)
	m.emission_energy_multiplier = 0.0
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / 12.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func set_night(k: float) -> void:
	for m in facade_mats:
		(m as StandardMaterial3D).emission_energy_multiplier = k * 2.2
	if lamp_mat:
		lamp_mat.emission_energy_multiplier = 0.3 + k * 6.0


# ---------------- Постройка ----------------
func build() -> void:
	mat_asphalt = _pbr_mat("asphalt", 0.25, _noise_mat(Color(0.09, 0.09, 0.095), Color(0.2, 0.2, 0.21), 0.08, 0.3, 0.9))
	mat_walk = _pbr_mat("concrete", 0.33, _noise_mat(Color(0.48, 0.47, 0.45), Color(0.62, 0.61, 0.58), 0.05, 0.25, 0.85))
	mat_grass = _pbr_mat("grass", 0.25, _noise_mat(Color(0.12, 0.2, 0.07), Color(0.25, 0.35, 0.12), 0.06, 0.2, 0.95))
	mat_roof = _noise_mat(Color(0.18, 0.18, 0.19), Color(0.3, 0.3, 0.31), 0.1, 0.2, 0.9)
	mat_line_y = Models.mat(Color(0.85, 0.65, 0.1), 0.6)
	mat_line_w = Models.mat(Color(0.85, 0.85, 0.85), 0.6)
	lamp_mat = Models.mat(Color(1.0, 0.85, 0.6), 0.3, 0.0, 0.3).duplicate() as StandardMaterial3D
	var walls = [
		[Color(0.72, 0.68, 0.6), Color(0.12, 0.16, 0.2), 0.16, 0.25, 0.1],
		[Color(0.55, 0.3, 0.22), Color(0.1, 0.13, 0.16), 0.18, 0.3, 0.05],
		[Color(0.5, 0.52, 0.55), Color(0.14, 0.2, 0.26), 0.12, 0.25, 0.2],
		[Color(0.2, 0.24, 0.28), Color(0.2, 0.3, 0.38), 0.03, 0.35, 0.6],
		[Color(0.85, 0.84, 0.8), Color(0.12, 0.15, 0.18), 0.15, 0.25, 0.1],
		[Color(0.62, 0.55, 0.42), Color(0.1, 0.12, 0.15), 0.2, 0.3, 0.05],
	]
	for i in walls.size():
		var w: Array = walls[i]
		facade_mats.append(_facade(w[0], w[1], w[2], w[3], 100 + i, w[4]))
	_build_ground()
	_build_roads()
	_build_blocks()
	_build_lamps()
	_build_scenery()
	for m in _merge.keys():
		var data: Dictionary = _merge[m].commit()
		var mi = MeshInstance3D.new()
		mi.mesh = data["mesh"]
		mi.material_override = m
		add_child(mi)
	_merge.clear()


var _merge = {}


## Статичные коробки сливаются в один меш на материал (мало draw calls).
func _static_box(pos: Vector3, size: Vector3, m: Material, collide := true, _vis_end := 0.0) -> void:
	if not _merge.has(m):
		_merge[m] = Models.Builder.new()
	var bld = _merge[m]
	var bm = BoxMesh.new()
	bm.size = size
	bld.add("g", bm, Transform3D(Basis(), pos))
	if collide:
		var sb = StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var cs = CollisionShape3D.new()
		var sh = BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		sb.add_child(cs)
		sb.position = pos
		add_child(sb)


func _build_ground() -> void:
	var mi = MeshInstance3D.new()
	var pm = PlaneMesh.new()
	pm.size = Vector2(3000, 3000)
	mi.mesh = pm
	mi.material_override = mat_grass
	add_child(mi)
	var sb = StaticBody3D.new()
	sb.collision_layer = 1
	var cs = CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	sb.add_child(cs)
	add_child(sb)
	# асфальт под всем городом (дороги)
	var am = MeshInstance3D.new()
	var ap = PlaneMesh.new()
	ap.size = Vector2(N * P + R + 40, N * P + R + 40)
	am.mesh = ap
	am.material_override = mat_asphalt
	am.position.y = 0.01
	add_child(am)


func _build_roads() -> void:
	# разметка через MultiMesh: жёлтая двойная сплошная, белые пунктиры, зебры
	var yellow: Array = []
	var white: Array = []
	var total = N * P
	for k in N + 1:
		for seg in N:
			var a = seg * P + R / 2.0 - half
			var b = (seg + 1) * P - R / 2.0 - half
			var seg_len = b - a
			var mid = (a + b) / 2.0
			var line = k * P - half
			for off in [-0.15, 0.15]:
				yellow.append(Transform3D(Basis().scaled(Vector3(0.12, 1, seg_len)), Vector3(line + off, 0.02, mid)))
				yellow.append(Transform3D(Basis().scaled(Vector3(seg_len, 1, 0.12)), Vector3(mid, 0.02, line + off)))
			var d = a + 2.0
			while d < b - 3.0:
				for off2 in [-3.3, 3.3]:
					white.append(Transform3D(Basis().scaled(Vector3(0.12, 1, 3.0)), Vector3(line + off2, 0.02, d + 1.5)))
					white.append(Transform3D(Basis().scaled(Vector3(3.0, 1, 0.12)), Vector3(d + 1.5, 0.02, line + off2)))
				d += 9.0
	# зебры у перекрёстков
	for i in N + 1:
		for j in N + 1:
			var c = node_pos(i, j)
			for s in [-1.0, 1.0]:
				var st = -R / 2.0 + 1.0
				while st < R / 2.0 - 0.5:
					white.append(Transform3D(Basis().scaled(Vector3(0.5, 1, 2.6)), c + Vector3(st, 0.02, s * (R / 2.0 + 1.6))))
					white.append(Transform3D(Basis().scaled(Vector3(2.6, 1, 0.5)), c + Vector3(s * (R / 2.0 + 1.6), 0.02, st)))
					st += 1.1
	_multimesh(yellow, Models.box(1, 0.01, 1), mat_line_y)
	_multimesh(white, Models.box(1, 0.01, 1), mat_line_w)


func _multimesh(xfs: Array, mesh: Mesh, m: Material, vis_end := 0.0, shadows := false) -> MultiMeshInstance3D:
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi = MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if vis_end > 0.0:
		mmi.visibility_range_end = vis_end
	add_child(mmi)
	return mmi


func _build_blocks() -> void:
	var inner = P - R
	var center = Vector2(N / 2.0, N / 2.0)
	for bx in N:
		for bz in N:
			var b = Vector2i(bx, bz)
			var c = block_center(b)
			_static_box(c + Vector3(0, CURB / 2.0, 0), Vector3(inner, CURB, inner), mat_walk)
			var dist = Vector2(bx + 0.5, bz + 0.5).distance_to(center) / (N * 0.7)
			var is_special = special.values().has(b)
			if not is_special and rng.randf() < 0.1 and dist > 0.3:
				parks[b] = true
				_static_box(c + Vector3(0, CURB + 0.02, 0), Vector3(inner - 7, 0.04, inner - 7), mat_grass, false)
				continue
			if dist < 0.35 and rng.randf() < 0.6 and not is_special:
				# небоскрёб на весь квартал
				var h = rng.randf_range(70, 150)
				_building(c, Vector2(rng.randf_range(34, 42), rng.randf_range(34, 42)), h)
				continue
			for lx in [-1.0, 1.0]:
				for lz in [-1.0, 1.0]:
					var lc = c + Vector3(lx * 12.5, 0, lz * 12.5)
					var hmax: float = lerp(70.0, 12.0, clamp(dist, 0.0, 1.0))
					var h2 = rng.randf_range(hmax * 0.35, hmax)
					_building(lc, Vector2(rng.randf_range(15, 21), rng.randf_range(15, 21)), max(h2, 8.0))


func _building(c: Vector3, foot: Vector2, h: float) -> void:
	var m: StandardMaterial3D = facade_mats[rng.randi() % facade_mats.size()]
	var y0 = CURB
	# цоколь (первый этаж — витрины)
	var base_h = 4.5
	_static_box(c + Vector3(0, y0 + base_h / 2.0, 0), Vector3(foot.x + 0.4, base_h, foot.y + 0.4), facade_mats[3], true)
	_static_box(c + Vector3(0, y0 + base_h + (h - base_h) / 2.0, 0), Vector3(foot.x, h - base_h, foot.y), m, true)
	_static_box(c + Vector3(0, y0 + h + 0.3, 0), Vector3(foot.x + 0.6, 0.6, foot.y + 0.6), mat_roof, false, 600.0)
	# ступенчатые верхушки у высоток
	if h > 50 and rng.randf() < 0.6:
		var f2 = foot * rng.randf_range(0.55, 0.75)
		var h3 = rng.randf_range(8, 25)
		_static_box(c + Vector3(0, y0 + h + h3 / 2.0, 0), Vector3(f2.x, h3, f2.y), m, false, 900.0)
		_static_box(c + Vector3(0, y0 + h + h3 + 0.3, 0), Vector3(f2.x + 0.5, 0.6, f2.y + 0.5), mat_roof, false, 600.0)
	# кондиционеры/будки на крыше
	for k in rng.randi_range(1, 3):
		var p = c + Vector3(rng.randf_range(-foot.x, foot.x) * 0.3, y0 + h + 1.2, rng.randf_range(-foot.y, foot.y) * 0.3)
		_static_box(p, Vector3(rng.randf_range(1.5, 3), rng.randf_range(1.2, 2.2), rng.randf_range(1.5, 3)), mat_roof, false, 250.0)


func _build_lamps() -> void:
	var poles: Array = []
	var heads: Array = []
	for k in N + 1:
		for seg in N:
			var a = seg * P + R / 2.0 + 6.0 - half
			var b = (seg + 1) * P - R / 2.0 - 4.0 - half
			var d = a
			while d < b:
				var line = k * P - half
				for s in [-1.0, 1.0]:
					var off: float = s * (R / 2.0 + 0.7)
					# вдоль Z-дороги
					var p1 = Vector3(line + off, CURB, d)
					poles.append(Transform3D(Basis(), p1 + Vector3(0, 3.5, 0)))
					heads.append(Transform3D(Basis(), p1 + Vector3(-s * 1.2, 7.0, 0)))
					lamp_positions.append(p1 + Vector3(-s * 1.2, 6.8, 0))
					var p2 = Vector3(d, CURB, line + off)
					poles.append(Transform3D(Basis(), p2 + Vector3(0, 3.5, 0)))
					heads.append(Transform3D(Basis(), p2 + Vector3(0, 7.0, -s * 1.2)))
					lamp_positions.append(p2 + Vector3(0, 6.8, -s * 1.2))
				d += 28.0
	_multimesh(poles, Models.cyl(0.09, 7.0, 0.07, 8), Models.mat(Color(0.18, 0.19, 0.2), 0.4, 0.8), 260.0, true)
	_multimesh(heads, Models.box(0.5, 0.18, 0.5), lamp_mat, 260.0)


func _build_scenery() -> void:
	var tree_xf: Array = []
	for b in parks.keys():
		var c = block_center(b)
		for k in 14:
			var p = c + Vector3(rng.randf_range(-22, 22), CURB, rng.randf_range(-22, 22))
			tree_xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.3)), p))
	# деревья вдоль тротуаров
	for bx in N:
		for bz in N:
			var c2 = block_center(Vector2i(bx, bz))
			var e = (P - R) / 2.0 - 1.2
			for s in [-1.0, 1.0]:
				for t in [-0.5, 0.0, 0.5]:
					if rng.randf() < 0.5:
						tree_xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), c2 + Vector3(t * e * 1.6, CURB, s * e)))
	var tree_scene = _prop("tree")
	if tree_scene:
		_instance_scene_multi(tree_scene, tree_xf, 300.0)
	else:
		var trunks: Array = []
		var crowns: Array = []
		for xf in tree_xf:
			var x: Transform3D = xf
			trunks.append(x * Transform3D(Basis(), Vector3(0, 1.6, 0)))
			crowns.append(x * Transform3D(Basis().scaled(Vector3(2.2, 2.6, 2.2)), Vector3(0, 4.6, 0)))
			crowns.append(x * Transform3D(Basis().scaled(Vector3(1.6, 1.8, 1.6)), Vector3(0.8, 5.8, 0.4)))
		_multimesh(trunks, Models.cyl(0.18, 3.2, 0.12, 8), Models.mat(Color(0.25, 0.18, 0.12), 0.9), 300.0, true)
		_multimesh(crowns, Models.sph(1.0, 10), Models.mat(Color(0.16, 0.3, 0.1), 0.95), 300.0, true)
	# скамейки и урны у тротуаров
	var bench_xf: Array = []
	var bin_xf: Array = []
	for bx in N:
		for bz in N:
			var c3 = block_center(Vector2i(bx, bz))
			var e2 = (P - R) / 2.0 - 0.9
			if rng.randf() < 0.6:
				bench_xf.append(Transform3D(Basis(Vector3.UP, PI), c3 + Vector3(rng.randf_range(-15, 15), CURB, e2)))
			if rng.randf() < 0.7:
				bin_xf.append(Transform3D(Basis(), c3 + Vector3(e2, CURB, rng.randf_range(-15, 15))))
	var bench = _prop("bench")
	if bench:
		_instance_scene_multi(bench, bench_xf, 150.0)
	var bin = _prop("bin")
	if bin:
		_instance_scene_multi(bin, bin_xf, 120.0)
	else:
		var bx2: Array = []
		for xf in bin_xf:
			bx2.append((xf as Transform3D) * Transform3D(Basis(), Vector3(0, 0.5, 0)))
		_multimesh(bx2, Models.cyl(0.3, 1.0, 0.33, 10), Models.mat(Color(0.15, 0.25, 0.18), 0.5, 0.6), 120.0, true)
	# далёкие горы
	for k in 14:
		var a = TAU * k / 14.0 + rng.randf() * 0.2
		var dist = rng.randf_range(900, 1200)
		var mi = MeshInstance3D.new()
		mi.mesh = Models.cyl(rng.randf_range(180, 320), rng.randf_range(120, 260), 0.0, 9)
		mi.material_override = Models.mat(Color(0.28, 0.32, 0.26), 1.0)
		mi.position = Vector3(cos(a) * dist, 50, sin(a) * dist)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


func _prop(slot: String):
	var path = "res://assets/props/%s/%s.gltf" % [slot, slot]
	if ResourceLoader.exists(path):
		var s = load(path)
		if s is PackedScene:
			return s
	return null


## Разбирает сцену glTF на меши и рисует их через MultiMesh (дёшево на телефоне).
func _instance_scene_multi(scene: PackedScene, xfs: Array, vis_end: float) -> void:
	var inst = scene.instantiate()
	var found: Array = []
	_collect_meshes(inst, Transform3D.IDENTITY, found)
	for f in found:
		var local: Transform3D = f[1]
		var arr: Array = []
		for xf in xfs:
			arr.append((xf as Transform3D) * local)
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = f[0]
		mm.instance_count = arr.size()
		for i in arr.size():
			mm.set_instance_transform(i, arr[i])
		var mmi = MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = vis_end
		add_child(mmi)
	inst.queue_free()


func _collect_meshes(n: Node, parent_xf: Transform3D, out: Array) -> void:
	var xf = parent_xf
	if n is Node3D:
		xf = parent_xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append([(n as MeshInstance3D).mesh, xf])
	for ch in n.get_children():
		_collect_meshes(ch, xf, out)
