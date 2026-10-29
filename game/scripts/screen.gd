class_name Screen
## The size of the visible game area in game pixels. The window keeps the pixel scale whole and lets a wider or taller
## screen show more of the world, so the menus and the HUD place themselves by this rather than by 480x270.


static func view() -> Vector2:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_visible_rect().size
	return Vector2(480, 270)


## A menu lays itself out by the view size it was made with. If the window changes size afterwards (a phone settles
## into landscape just after start-up) the scene is made again, so nothing stays at the old size.
static func relayout_on_resize(node: Node) -> void:
	var root := node.get_tree().root
	var again := func() -> void:
		if is_instance_valid(node) and node.is_inside_tree() and not node.get("_going"):
			node.get_tree().reload_current_scene.call_deferred()
	root.size_changed.connect(again, CONNECT_ONE_SHOT)
	var watch := Timer.new()  # the size can settle without a signal we see (a phone's first seconds): look at it now and then too
	watch.wait_time = 0.25
	watch.autostart = true
	watch.timeout.connect(func() -> void:
		var made = node.get("VIEW")
		if made is Vector2 and (made as Vector2) != view():
			again.call())
	node.add_child(watch)
