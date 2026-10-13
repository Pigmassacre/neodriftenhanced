class_name YMAdpcmA
extends RefCounted
## The six sampled-sound channels (ADPCM-A) of the YM2610.
##
## Follows MAME's chip model (ymfm): the channels step once every third chip
## sample (18.5 kHz), a sample ends when the address reaches the block after
## its end address, and the 12-bit decoder value wraps around.

const STEPS: Array[int] = [
	16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130,
	143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796,
	876, 963, 1060, 1166, 1282, 1411, 1552,
]
const STEP_CHANGE: Array[int] = [-1, -1, -1, -1, 2, 5, 7, 9]

## Output of the last render(), one value per sample.
var out_left := PackedInt32Array()
var out_right := PackedInt32Array()

var rom := PackedByteArray()
## How loud each channel is mixed, 256 for as the chip plays it. The game's
## driver plays its music on the first channel and its effects on the last
## three (see SoundBoard.set_volumes).
var gains := PackedInt32Array([256, 256, 256, 256, 256, 256])

var _reg := PackedByteArray()
var _playing := PackedInt32Array([0, 0, 0, 0, 0, 0])
var _address := PackedInt32Array([0, 0, 0, 0, 0, 0])
var _nibble := PackedInt32Array([0, 0, 0, 0, 0, 0])
var _accumulator := PackedInt32Array([0, 0, 0, 0, 0, 0])
var _step := PackedInt32Array([0, 0, 0, 0, 0, 0])
var _left := 0
var _right := 0


func _init() -> void:
	_reg.resize(0x30)


## Chip samples from a key-on at `sample` until the channel reports its end,
## for a sample of `length` bytes.
static func samples_until_end(sample: int, length: int) -> int:
	return posmod(1 - sample, 3) + 6 * length


## Bytes a channel will play for these address registers (0 if it ends at once).
static func length_for(start: int, end: int) -> int:
	return (((end + 1) << 8) - (start << 8)) & 0xFFFFF


## Renders `count` samples starting at chip sample `first`; see YMFmChannel.render.
func render(writes: PackedInt64Array, first: int, count: int) -> void:
	out_left.resize(count)
	out_right.resize(count)
	var position := 0
	for entry in writes:
		if (entry & 0x1FF00) < 0x10000 or (entry & 0xFF00) >= 0x3000:
			continue
		var at := clampi((entry >> 17) - first, position, count)
		if at > position:
			_run(position, at, first)
			position = at
		_write((entry >> 8) & 0xFF, entry & 0xFF)
	if count > position:
		_run(position, count, first)


func _write(register: int, value: int) -> void:
	_reg[register] = value
	if register == 0x00:
		for channel in 6:
			if (value >> channel) & 1:
				if value & 0x80:
					_playing[channel] = 0
				else:
					_playing[channel] = 1
					_address[channel] = (_reg[0x10 + channel] | (_reg[0x18 + channel] << 8)) << 8
					_nibble[channel] = 0
					_accumulator[channel] = 0
					_step[channel] = 0
	_mix()


func _run(from: int, to: int, first: int) -> void:
	var size := rom.size()
	for index in range(from, to):
		if (first + index) % 3 == 1:
			var any := false
			for channel in 6:
				if _playing[channel] == 0:
					_accumulator[channel] = 0
					continue
				any = true
				var address := _address[channel]
				var data := 0
				if _nibble[channel] == 0:
					var end := ((_reg[0x20 + channel] | (_reg[0x28 + channel] << 8)) + 1) << 8
					if ((address ^ end) & 0xFFFFF) == 0:
						_playing[channel] = 0
						_accumulator[channel] = 0
						continue
					data = rom[address % size] >> 4
					_nibble[channel] = 1
				else:
					data = rom[address % size] & 0x0F
					_nibble[channel] = 0
					_address[channel] = address + 1
				var delta := (2 * (data & 7) + 1) * STEPS[_step[channel]] / 8
				_accumulator[channel] = (_accumulator[channel] + (-delta if (data & 8) else delta)) & 0xFFF
				_step[channel] = clampi(_step[channel] + STEP_CHANGE[data & 7], 0, 48)
			if any or _left != 0 or _right != 0:
				_mix()
		out_left[index] = _left
		out_right[index] = _right


## The channels' current values at their volumes, summed per side.
func _mix() -> void:
	_left = 0
	_right = 0
	for channel in 6:
		var accumulator := _accumulator[channel]
		if accumulator == 0:
			continue
		var control := _reg[0x08 + channel]
		var attenuation := ((control & 0x1F) ^ 0x1F) + ((_reg[0x01] & 0x3F) ^ 0x3F)
		if attenuation >= 63:
			continue
		# 12-bit signed value, scaled to 16 bits
		var value := ((accumulator ^ 0x800) - 0x800) << 4
		value = ((value * (15 - (attenuation & 7))) >> (5 + (attenuation >> 3))) & ~3
		value = (value * gains[channel]) >> 8
		if control & 0x80:
			_left += value
		if control & 0x40:
			_right += value
