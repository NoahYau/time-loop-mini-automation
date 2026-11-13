extends RefCounted
## 確定性工廠模擬：純資料、固定 tick、固定遍歷順序、零物理、零 delta。
## 任何讀寫都係格子資料，所以重播零漂移。

const K = preload("res://sim/constants.gd")
const Building = preload("res://sim/building.gd")

var buildings: Dictionary = {}   # int idx -> Building
var tick: int = 0
var delivered: int = 0
var ore_mined: int = 0
var parts_made: int = 0
var ore: Dictionary = {}      # int idx -> true（礦脈）

# ---------------------------------------------------------------- 配方表

func recipe_in_type(t: int) -> int:
	match t:
		K.T_FURNACE: return K.ITEM_ORE
		K.T_GEAR: return K.ITEM_INGOT
		K.T_ASSEMBLER: return K.ITEM_GEAR
	return -1

func recipe_in_count(t: int) -> int:
	match t:
		K.T_FURNACE: return K.SMELT_IN
		K.T_GEAR: return K.GEAR_IN
		K.T_ASSEMBLER: return K.ASSEMBLE_IN
	return 0

func recipe_ticks(t: int) -> int:
	match t:
		K.T_FURNACE: return K.SMELT_TICKS
		K.T_GEAR: return K.GEAR_TICKS
		K.T_ASSEMBLER: return K.ASSEMBLE_TICKS
	return 0

func recipe_in_cap(t: int) -> int:
	match t:
		K.T_FURNACE: return K.SMELT_CAP
		K.T_GEAR: return K.GEAR_CAP
		K.T_ASSEMBLER: return K.ASSEMBLE_CAP
	return 0

func recipe_out_type(t: int) -> int:
	match t:
		K.T_FURNACE: return K.ITEM_INGOT
		K.T_GEAR: return K.ITEM_GEAR
		K.T_ASSEMBLER: return K.ITEM_PART
	return -1

func is_machine(t: int) -> bool:
	return t == K.T_FURNACE or t == K.T_GEAR or t == K.T_ASSEMBLER

# ---------------------------------------------------------------- 基本操作

func clear() -> void:
	buildings.clear()
	tick = 0
	delivered = 0
	ore_mined = 0
	parts_made = 0
	_generate_ore()

## 礦脈係固定嘅（每個關卡一樣），所以重播唔會唔同。
func _generate_ore() -> void:
	ore.clear()
	for y in K.ORE_LANES:
		ore[idx_of(Vector2i(K.ORE_X, int(y)))] = true

func is_ore_cell(cell: Vector2i) -> bool:
	if not in_bounds(cell):
		return false
	return ore.has(idx_of(cell))

## 一格可唔可以放呢種建築（礦機要擺喺礦脈上）。
func can_place(cell: Vector2i, type: int) -> bool:
	if not in_bounds(cell):
		return false
	if buildings.has(idx_of(cell)):
		return false
	if type == K.T_MINER:
		return is_ore_cell(cell)
	return true

func idx_of(cell: Vector2i) -> int:
	return cell.y * K.GRID_W + cell.x

func cell_of(idx: int) -> Vector2i:
	@warning_ignore("integer_division")
	var y: int = idx / K.GRID_W
	return Vector2i(idx % K.GRID_W, y)

func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < K.GRID_W and cell.y < K.GRID_H

func build(idx: int, type: int, dir: int, origin: int) -> void:
	var b := Building.new()
	b.type = type
	b.dir = dir
	b.origin = origin
	buildings[idx] = b

func demolish(idx: int) -> void:
	buildings.erase(idx)

func building_at(cell: Vector2i) -> Building:
	if not in_bounds(cell):
		return null
	return buildings.get(idx_of(cell), null)

# ---------------------------------------------------------------- tick

func step() -> void:
	tick += 1
	_produce()
	_transport()

func _produce() -> void:
	for idx in range(K.GRID_W * K.GRID_H):
		if not buildings.has(idx):
			continue
		var b = buildings[idx]
		if b.type == K.T_MINER:
			if b.has_out:
				continue
			b.progress += 1
			if b.progress >= K.MINER_TICKS:
				b.progress = 0
				b.has_out = true
				b.item = K.ITEM_ORE
				ore_mined += 1
			continue
		if not is_machine(b.type):
			continue
		var need := recipe_in_count(b.type)
		if b.in_count < need:
			b.progress = 0
			continue
		if b.has_out:
			continue
		b.progress += 1
		if b.progress >= recipe_ticks(b.type):
			b.progress = 0
			b.in_count -= need
			b.has_out = true
			b.item = recipe_out_type(b.type)
			if b.type == K.T_ASSEMBLER:
				parts_made += 1

func _transport() -> void:
	# 兩階段：先收集所有移動，再統一提交。
	# 咁樣無論傳送帶指向邊個方向，一件貨每個 tick 都最多行一格。
	var moves: Array = []          # [from_idx, to_idx, item]
	var claimed: Dictionary = {}   # to_idx -> true
	for idx in range(K.GRID_W * K.GRID_H):
		if not buildings.has(idx):
			continue
		var b = buildings[idx]
		if not b.has_out:
			continue
		var nidx := _neighbor(idx, b.dir)
		if nidx < 0 or claimed.has(nidx):
			continue
		var nb = buildings.get(nidx, null)
		if nb == null:
			continue
		if nb.type == K.T_BELT:
			if nb.has_out:
				continue
		elif is_machine(nb.type):
			# B 規則：機器只可以推去帶或出口 -> 傳送帶變成必需
			if b.type != K.T_BELT:
				continue
			if b.item != recipe_in_type(nb.type) or nb.in_count >= recipe_in_cap(nb.type):
				continue
		elif nb.type == K.T_SINK:
			if b.item != K.ITEM_PART:
				continue
		else:
			continue
		moves.append([idx, nidx, b.item])
		claimed[nidx] = true
	if moves.is_empty():
		return
	for m in moves:
		buildings[m[0]].has_out = false
	for m in moves:
		var nb = buildings[m[1]]
		if nb.type == K.T_BELT:
			nb.has_out = true
			nb.item = m[2]
		elif is_machine(nb.type):
			nb.in_count += 1
		else:
			delivered += 1

func _neighbor(idx: int, dir: int) -> int:
	var cell: Vector2i = cell_of(idx) + K.DIR_VEC[dir]
	if not in_bounds(cell):
		return -1
	return idx_of(cell)

# ---------------------------------------------------------------- 狀態快照

func save_state() -> Dictionary:
	var d: Dictionary = {"tick": tick, "delivered": delivered, "ore_mined": ore_mined, "parts_made": parts_made, "b": {}}
	for idx in buildings:
		d["b"][idx] = (buildings[idx] as Building).copy()
	return d

func load_state(d: Dictionary) -> void:
	tick = int(d["tick"])
	delivered = int(d["delivered"])
	ore_mined = int(d["ore_mined"])
	parts_made = int(d["parts_made"])
	buildings.clear()
	var src: Dictionary = d["b"]
	for idx in src:
		buildings[idx] = (src[idx] as Building).copy()

# ---------------------------------------------------------------- 狀態指紋

func digest() -> int:
	var h: int = -3750763034362895579
	h = _mix(h, tick)
	h = _mix(h, delivered)
	h = _mix(h, ore_mined)
	h = _mix(h, parts_made)
	for idx in range(K.GRID_W * K.GRID_H):
		if not buildings.has(idx):
			continue
		var b = buildings[idx]
		h = _mix(h, idx)
		h = _mix(h, b.type)
		h = _mix(h, b.dir)
		h = _mix(h, b.progress)
		h = _mix(h, b.in_count)
		h = _mix(h, 1 if b.has_out else 0)
		h = _mix(h, b.item)
		h = _mix(h, b.origin)
	return h

func _mix(h: int, v: int) -> int:
	return (h ^ v) * 1099511628211
