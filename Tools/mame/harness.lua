-- MAME autoboot harness for neodrift: scripted inputs and state capture.
--
-- Driven by a job file named in the NEODRIFT_JOB environment variable. The
-- job is a Lua file returning a table:
--   out    = output directory (must exist)
--   stop   = frame number to exit at
--   inputs = { {first, last, "port tag", "field name"}, ... }  held on frames first..last
--   snaps  = { frame, ... }           screenshots (PNG)
--   dumps  = { frame, ... }           full state dumps (vram, palette, work ram)
--   dump_every = {first, last, step}  optional periodic dumps
--   ramlog = {first, last}            optional: work RAM appended to ramlog.bin every frame
--   watch  = {first, last, { {name, first_addr, last_addr, "r"|"w"}, ... }}
--            optional: log which code reads/writes the ranges, to watch.txt
--   vwatch = {first, last, vram_lo, vram_hi}  optional: log which code writes that
--            video RAM range, to vwatch.txt
--   trace  = { first, last, { {name, addr, size}, ... } }  optional per-frame RAM trace (CSV)
--
-- Video RAM is not readable without side effects, so it is shadowed here by
-- tapping the LSPC register writes from power-on.

local job = dofile(os.getenv("NEODRIFT_JOB"))
local machine = manager.machine
local cpu = machine.devices[":maincpu"]
local mem = cpu.spaces["program"]
local screen = machine.screens[":screen"]

neodrift_vwatch_on = false
neodrift_vwatch_hits = {}
local vram = {}
for i = 0, 0x87ff do vram[i] = 0 end
local vaddr, vmod = 0, 0
local lspc_mode = 0
local sysreg = {}       -- last write to each 0x3A00xx system latch
local timer_writes = 0  -- count of raster timer register writes this frame

-- Kept in globals: MAME drops taps and notifiers once their handles are collected.
neodrift_taps = {}
local taps = neodrift_taps
taps[1] = mem:install_write_tap(0x3c0000, 0x3c000f, "lspc", function(offset, data, mask)
  local reg = offset & 0xe
  if reg == 0 then
    vaddr = data & 0xffff
  elseif reg == 2 then
    if vaddr <= 0x87ff then vram[vaddr] = data & 0xffff end
    if neodrift_vwatch_on and vaddr >= job.vwatch[3] and vaddr <= job.vwatch[4] then
      local pc = cpu.state["CURPC"].value
      neodrift_vwatch_hits[pc] = (neodrift_vwatch_hits[pc] or 0) + 1
    end
    -- the address wraps within its half (lower 32K / upper 32K)
    vaddr = (vaddr & 0x8000) | ((vaddr + vmod) & 0x7fff)
  elseif reg == 4 then
    vmod = data & 0xffff
  elseif reg == 6 then
    lspc_mode = data & 0xffff
  elseif reg == 8 or reg == 10 then
    timer_writes = timer_writes + 1
  end
end)
taps[2] = mem:install_write_tap(0x3a0000, 0x3a001f, "sysreg", function(offset, data, mask)
  -- latches: bit 4 of the address is the value, bits 1-3 select the latch
  sysreg[(offset >> 1) & 7] = (offset >> 4) & 1
end)

local function set_inputs(frame)
  for _, e in ipairs(job.inputs or {}) do
    local field = machine.ioport.ports[e[3]].fields[e[4]]
    if frame >= e[1] and frame <= e[2] then
      field:set_value(1)
    elseif frame == e[2] + 1 then
      field:clear_value()
    end
  end
end

local function words(t, first, last)
  local parts = {}
  for i = first, last do parts[#parts + 1] = string.pack(">I2", t[i]) end
  return table.concat(parts)
end

local function dump(frame)
  local f = assert(io.open(string.format("%s/f%06d.bin", job.out, frame), "wb"))
  -- header: magic, frame, lspc mode, latches (shadow, fix bank, palette bank), timer writes
  f:write(string.pack(">c4I4I2BBBB", "NDF1", frame, lspc_mode,
    sysreg[0] or 0, sysreg[5] or 0, sysreg[7] or 0, math.min(timer_writes, 255)))
  f:write(words(vram, 0, 0x87ff))
  f:write(mem:read_range(0x400000, 0x401fff, 8))
  f:write(mem:read_range(0x100000, 0x10ffff, 8))
  f:close()
end

local snaps, dumps = {}, {}
for _, n in ipairs(job.snaps or {}) do snaps[n] = true end
for _, n in ipairs(job.dumps or {}) do dumps[n] = true end

local trace_file
if job.trace then
  trace_file = assert(io.open(job.out .. "/trace.csv", "w"))
  local names = { "frame" }
  for _, v in ipairs(job.trace[3]) do names[#names + 1] = v[1] end
  trace_file:write(table.concat(names, ",") .. "\n")
end

local watch_hits = {}
local watch_on = false
-- Installed when the watch window opens: the driver remaps work RAM at reset,
-- which would discard taps installed at boot.
local function install_watch()
  for _, w in ipairs(job.watch[3]) do
    local function hit(offset, data, mask)
      if not watch_on then return end
      local key = string.format("%s %s pc=%06X addr=%06X", w[1], w[4], cpu.state["CURPC"].value, offset)
      watch_hits[key] = (watch_hits[key] or 0) + 1
    end
    if w[4] == "r" then
      taps[#taps + 1] = mem:install_read_tap(w[2], w[3], "watch_" .. w[1], hit)
    else
      taps[#taps + 1] = mem:install_write_tap(w[2], w[3], "watch_" .. w[1], hit)
    end
  end
end

local ramlog_file
if job.ramlog then ramlog_file = assert(io.open(job.out .. "/ramlog.bin", "wb")) end

local frame = 0
set_inputs(0)
neodrift_frame_sub = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  if snaps[frame] then screen:snapshot(string.format("%s/f%06d.png", job.out, frame)) end
  local de = job.dump_every
  if dumps[frame] or (de and frame >= de[1] and frame <= de[2] and (frame - de[1]) % de[3] == 0) then
    dump(frame)
  end
  if trace_file and frame >= job.trace[1] and frame <= job.trace[2] then
    local row = { tostring(frame) }
    for _, v in ipairs(job.trace[3]) do
      local val
      if v[3] == 1 then val = mem:read_u8(v[2]) elseif v[3] == 2 then val = mem:read_u16(v[2]) else val = mem:read_u32(v[2]) end
      row[#row + 1] = tostring(val)
    end
    trace_file:write(table.concat(row, ",") .. "\n")
  end
  if ramlog_file and frame >= job.ramlog[1] and frame <= job.ramlog[2] then
    ramlog_file:write(mem:read_range(0x100000, 0x10ffff, 8))
  end
  timer_writes = 0
  if job.watch then
    if frame == job.watch[1] then install_watch() end
    watch_on = frame >= job.watch[1] and frame <= job.watch[2]
  end
  if job.vwatch then neodrift_vwatch_on = frame >= job.vwatch[1] and frame <= job.vwatch[2] end
  if frame >= job.stop then
    if job.vwatch then
      local wf = assert(io.open(job.out .. "/vwatch.txt", "w"))
      for pc, n in pairs(neodrift_vwatch_hits) do wf:write(string.format("pc=%06X n=%d\n", pc, n)) end
      wf:close()
    end
    if job.watch then
      local keys = {}
      for k in pairs(watch_hits) do keys[#keys + 1] = k end
      table.sort(keys)
      local wf = assert(io.open(job.out .. "/watch.txt", "w"))
      for _, k in ipairs(keys) do wf:write(k, " n=", watch_hits[k], "\n") end
      wf:close()
    end
    if trace_file then trace_file:close() end
    if ramlog_file then ramlog_file:close() end
    machine:exit()
  end
  set_inputs(frame)
end)
