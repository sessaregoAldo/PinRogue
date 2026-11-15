class_name TouchScroll
extends Node
## Makes a ScrollContainer scroll by dragging anywhere on its content, cards
## and buttons included (on phones a drag that starts on a button or a panel
## was swallowed by it, so lists only scrolled from the gaps between items).
##
##   TouchScroll.setup(scroll)              once, after creating the container
##   if TouchScroll.dragged(scroll): return  first line of a button handler
##                                           inside it, so lifting the finger
##                                           after a scroll doesn't press it
##
## setup() adds one of these nodes to the container: it watches for new content
## (lists are rebuilt often) and goes away with the container.

## A drag shorter than this (pixels) still counts as a tap.
const DEADZONE := 12
## Button presses this soon after a scroll ends are ignored (ms).
const AFTER_DRAG_MS := 180

var _scroll: ScrollContainer
## -1 while dragging, otherwise when the last drag ended (Time.get_ticks_msec()).
var _drag_ms: int = -100000


static func setup(scroll: ScrollContainer) -> void:
	scroll.scroll_deadzone = DEADZONE
	var watcher := TouchScroll.new()
	watcher.name = "TouchScroll"
	watcher._scroll = scroll
	scroll.add_child(watcher, false, Node.INTERNAL_MODE_BACK)
	scroll.scroll_started.connect(watcher._on_started)
	scroll.scroll_ended.connect(watcher._on_ended)
	_pass_all(scroll)


## True while the list is being dragged, or just after.
static func dragged(scroll: ScrollContainer) -> bool:
	if scroll == null:
		return false
	var watcher := scroll.get_node_or_null("TouchScroll") as TouchScroll
	if watcher == null:
		return false
	return watcher._drag_ms == -1 or Time.get_ticks_msec() - watcher._drag_ms < AFTER_DRAG_MS


func _enter_tree() -> void:
	get_tree().node_added.connect(_on_node_added)
	_pass_all(_scroll)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if _scroll.is_ancestor_of(node):
		_pass(node)


func _on_started() -> void:
	_drag_ms = -1


func _on_ended() -> void:
	_drag_ms = Time.get_ticks_msec()


static func _pass_all(node: Node) -> void:
	for child in node.get_children():
		_pass(child)
		_pass_all(child)


## Let presses through to the scroll container as well (the control still gets them).
static func _pass(node: Node) -> void:
	if node is ScrollBar or node is LineEdit or node is TextEdit:
		return
	var control := node as Control
	if control != null and control.mouse_filter == Control.MOUSE_FILTER_STOP:
		control.mouse_filter = Control.MOUSE_FILTER_PASS
