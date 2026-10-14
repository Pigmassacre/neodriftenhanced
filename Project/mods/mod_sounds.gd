extends Node
## Sounds and music of mods: a mod's `sounds/NUMBER.ogg` (or .wav, .mp3)
## is played in place of the game's sound NUMBER, in hexadecimal as
## `--log-sounds` prints the sounds the game asks for. Music ($20 to $3F)
## plays round and round until other music, or none, is asked for; the
## rest plays once.
##
## The game's requests for those sounds never reach the sound board: the
## machine keeps them (NeoGeoMachine.replaced_sounds, sounds_taken) for
## `play_taken` to play.

const EXTENSIONS := ["ogg", "wav", "mp3"]
const FIRST_MUSIC := 0x20
const LAST_MUSIC := 0x3F
## Effects that may sound at once.
const VOICES := 8

## By sound number, the stream.
var streams := {}
var music_volume := 1.0
var effects_volume := 1.0

var _music: AudioStreamPlayer
var _effects: Array[AudioStreamPlayer] = []
var _next_effect := 0


func _ready() -> void:
	_music = AudioStreamPlayer.new()
	add_child(_music)
	for voice in VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_effects.append(player)


static func is_music(sound: int) -> bool:
	return sound >= FIRST_MUSIC and sound <= LAST_MUSIC


## Reads the sounds of `mods`, later ones over earlier, and tells the
## machine which it is to keep from the sound board.
func load_mods(mods: Array[Mods.Mod], machine: NeoGeoMachine) -> void:
	stop()
	streams.clear()
	for mod in mods:
		var folder := mod.path.path_join("sounds")
		if not DirAccess.dir_exists_absolute(folder):
			continue
		for file in DirAccess.get_files_at(folder):
			var number := file.get_basename()
			if not file.get_extension().to_lower() in EXTENSIONS or not number.is_valid_hex_number():
				continue
			var stream := _load(folder.path_join(file), is_music(number.hex_to_int()))
			if stream == null:
				push_warning("Mod %s: sounds/%s could not be read" % [mod.id, file])
				continue
			streams[number.hex_to_int()] = stream
	machine.replaced_sounds = {}
	for sound: int in streams:
		machine.replaced_sounds[sound] = true


static func _load(path: String, looping: bool) -> AudioStream:
	match path.get_extension().to_lower():
		"ogg":
			var ogg := AudioStreamOggVorbis.load_from_file(path)
			if ogg != null:
				ogg.loop = looping
			return ogg
		"mp3":
			var mp3 := AudioStreamMP3.load_from_file(path)
			if mp3 != null:
				mp3.loop = looping
			return mp3
		"wav":
			var wav := AudioStreamWAV.load_from_file(path)
			if wav != null and looping:
				wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
				wav.loop_end = int(wav.get_length() * wav.mix_rate)
			return wav
	return null


## Plays what the game asked for this frame that mods replace, and stops
## their music when the game's own music, or none, is asked for.
func play_taken(machine: NeoGeoMachine) -> void:
	for sound in machine.sounds_taken:
		if sound == NeoGeoMachine.STOP_MUSIC:
			_music.stop()
		elif sound == NeoGeoMachine.RESET_SOUND:
			stop()
		elif not streams.has(sound):
			if sound < FIRST_MUSIC or is_music(sound):
				# the game's own music, or a command of the driver's that ends it
				_music.stop()
		elif is_music(sound):
			_music.stream = streams[sound]
			_music.volume_db = linear_to_db(maxf(music_volume, 0.0001))
			_music.play()
		elif streams.has(sound):
			var player := _effects[_next_effect]
			_next_effect = (_next_effect + 1) % VOICES
			player.stream = streams[sound]
			player.volume_db = linear_to_db(maxf(effects_volume, 0.0001))
			player.play()
	machine.sounds_taken.clear()


func stop() -> void:
	if _music == null:
		return
	_music.stop()
	for player in _effects:
		player.stop()


func set_paused(paused: bool) -> void:
	if _music == null:
		return
	_music.stream_paused = paused
	for player in _effects:
		player.stream_paused = paused


func set_volumes(music: float, effects: float) -> void:
	music_volume = music
	effects_volume = effects
	if _music != null:
		_music.volume_db = linear_to_db(maxf(music, 0.0001))
