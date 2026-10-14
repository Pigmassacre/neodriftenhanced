extends RefCounted
## Courses made by mods (the `[course]` section of a mod.cfg).

## Where the data a mod adds is put: after the bus addresses the game uses,
## where a Neo Geo has its memory card (NeoGeoMachine.extra_rom).
const EXTRA_START := 0x800000


## Data added to the machine's address space, kept as NeoGeoMachine.rom is.
class Extra:
	var bytes := PackedByteArray()


static func apply(_machine: NeoGeoMachine, _mod: Mods.Mod, _extra: Extra) -> void:
	pass
