class_name Screen
## The size of the visible game area in game pixels. The window keeps the pixel scale whole and lets a wider or taller
## screen show more of the world, so the menus and the HUD place themselves by this rather than by 480x270.


static func view() -> Vector2:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_visible_rect().size
	return Vector2(480, 270)
