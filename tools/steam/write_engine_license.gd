# Godot 엔진과 엔진에 들어 있는 라이브러리의 라이선스 문구를 파일로 씀 (배포물에 함께 넣어야 함)
extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dir := args[0] if args.size() else "."
	var f := FileAccess.open(dir.path_join("Godot-Engine-LICENSE.txt"), FileAccess.WRITE)
	f.store_string("This game uses Godot Engine, available under the following license:\n\n" + Engine.get_license_text())
	f.close()
	var g := FileAccess.open(dir.path_join("Godot-third-party.txt"), FileAccess.WRITE)
	for c in Engine.get_copyright_info():
		g.store_string("- %s\n" % c.name)
		for p in c.parts:
			g.store_string("    %s (%s)\n" % [", ".join(p.copyright), p.license])
	var lic := Engine.get_license_info()
	for k in lic:
		g.store_string("\n==== %s ====\n%s\n" % [k, lic[k]])
	g.close()
	var c := FileAccess.open(dir.path_join("CREDITS.txt"), FileAccess.WRITE)
	c.store_string(load("res://scripts/credits.gd").TEXT)
	c.close()
	quit()
