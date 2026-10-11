extends SceneTree
## Headless check of the sound chip model against MAME.
##
##   godot --headless --path Project --script res://tools/synth_replay.gd -- \
##       --ymlog=PATH --wav=PATH [--parts=fm,ssg,adpcm] [--last=SECONDS] [--ssg-delay=SAMPLES]
##
## Replays the timed register writes of a MAME ymlog (Tools/mame/harness.lua)
## straight into the chip model, with no sound CPU involved, and writes what
## it produces as a 16-bit stereo WAV at the chip's sample rate, for
## Tools/compare_audio.py.
##
## --ssg-delay shifts the square-wave part later by that many chip samples.
## In MAME's recordings it lags the rest by about 47 samples (0.85 ms), so
## that is what a sample-by-sample comparison needs.

const MAME_SAMPLE_RATE := 55555.0

## The square-wave samples held back by --ssg-delay.
var _ssg_delay := PackedInt32Array()


func _init() -> void:
	var log_path := ""
	var wav_path := ""
	var parts := "fm,ssg,adpcm"
	var last := 1e9
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ymlog="):
			log_path = arg.trim_prefix("--ymlog=")
		elif arg.begins_with("--wav="):
			wav_path = arg.trim_prefix("--wav=")
		elif arg.begins_with("--parts="):
			parts = arg.trim_prefix("--parts=")
		elif arg.begins_with("--ssg-delay="):
			_ssg_delay.resize(int(arg.trim_prefix("--ssg-delay=")))
			_ssg_delay.fill(0)
		elif arg.begins_with("--last="):
			last = float(arg.trim_prefix("--last="))
	var chip := YM2610.new()
	chip.use_fm = "fm" in parts
	chip.use_ssg = "ssg" in parts
	chip.use_adpcm = "adpcm" in parts
	var dir := MachineLoader.repo_dir().path_join("neodrift")
	chip.set_sample_rom(FileAccess.get_file_as_bytes(dir.path_join("213-v1.v1"))
			+ FileAccess.get_file_as_bytes(dir.path_join("213-v2.v2")))
	var sound := PackedVector2Array()
	var source := FileAccess.open(log_path, FileAccess.READ)
	var started := Time.get_ticks_usec()
	var rendered_to := 0
	var seconds := 0.0
	while not source.eof_reached():
		var fields := source.get_line().split(" ")
		if fields.size() < 5 or fields[1] == "cmd":
			continue
		seconds = float(fields[4])
		if seconds > last:
			break
		# MAME runs the chip's sound stream at a whole number of samples per second
		var cycles := int(seconds * MAME_SAMPLE_RATE) * YM2610.CYCLES_PER_SAMPLE
		# render in chunks of about a video frame, as the game does
		while cycles - rendered_to > 67584:
			rendered_to += 67584
			_render(chip, rendered_to, sound)
		chip.write(0 if fields[1] == "A" else 1, fields[2].hex_to_int(), fields[3].hex_to_int(), cycles)
	_render(chip, rendered_to + 67584, sound)
	var elapsed := (Time.get_ticks_usec() - started) / 1000.0
	var seconds_made := sound.size() / YM2610.SAMPLE_RATE
	print("rendered %.1f s of sound in %.0f ms (%.2f ms per video frame)"
			% [seconds_made, elapsed, elapsed / (seconds_made * 59.185606)])
	SoundBoard.save_wav(sound, wav_path)
	quit()


func _render(chip: YM2610, cycles: int, sound: PackedVector2Array) -> void:
	chip.render(cycles)
	if not _ssg_delay.is_empty():
		var joined := _ssg_delay + chip.out_ssg
		chip.out_ssg = joined.slice(0, chip.out_ssg.size())
		_ssg_delay = joined.slice(chip.out_ssg.size())
	sound.append_array(chip.frames())
