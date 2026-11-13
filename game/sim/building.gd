extends RefCounted
## 一格建築嘅純資料。冇 Node、冇 signal、冇 _process —— 重播零浮點漂移嘅前提。

var type: int = 0
var dir: int = 0
var progress: int = 0
var in_count: int = 0
var has_out: bool = false
var item: int = 0        # ITEM_ORE / ITEM_INGOT
var origin: int = 0      # 由第幾個 loop 建成（拆幽靈嘢要 2 AP）
func copy():
	var b = get_script().new()
	b.type = type
	b.dir = dir
	b.progress = progress
	b.in_count = in_count
	b.has_out = has_out
	b.item = item
	b.origin = origin
	return b
