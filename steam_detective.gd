extends Node


func _ready():
	var exe_path = OS.get_executable_path().get_base_dir()
	print("--- STEAM DETECTIVE REPORT ---")
	print("1. I am running from this folder: ", exe_path)
	
	var target_file = exe_path.path_join("steam_appid.txt")
	
	if FileAccess.file_exists(target_file):
		var content = FileAccess.get_file_as_string(target_file).strip_edges()
		print("2. FOUND the file!")
		print("3. Inside the file, I see: '", content, "'")
		if content == "480":
			print("SUCCESS: Everything looks correct. Restart Godot and Steam.")
		else:
			print("ERROR: The number is wrong. It should be 480.")
	else:
		print("2. MISSING: I cannot find 'steam_appid.txt' in this folder.")
		print("ACTION: Create the file in the path listed in Step 1.")
	print("------------------------------")
