# How multiplayer works, and how to add a synced feature

Slipstream has old-school LAN play for up to 8 players (humans plus bots), built on Godot's
high-level multiplayer API over ENet. There is no dedicated server: one player **hosts**, the host
is authoritative for the race, and every machine builds the same track locally.

Files: `scripts/autoload/net.gd` (autoload `Net`: hosting, discovery, lobby),
`scripts/race/race.gd` (in-race sync, see the `# ---- network` section),
`scripts/car/car.gd` (`net_pack()`, `net_push()`, `set_remote()`, `_remote_step()`),
`scripts/ui/menu.gd` (lobby screens).

## The pieces

### Discovery and lobby (`Net`)

- **Ports**: UDP `27015` (ENet game traffic, `Net.PORT`), UDP `27016` (LAN discovery,
  `Net.DISCOVERY_PORT`). `Net.MAX_PLAYERS = 8`.
- **Hosting**: `Net.host()` opens an ENet server and broadcasts a JSON beacon to
  `255.255.255.255:27016` once a second (`{proto, name, track, players, max, state}`).
  Clients in the Join screen listen (`start_scan()`) and list hosts seen in the last 3.5 s, or
  type an IP.
- **Version check**: `Net.PROTOCOL` (`"slipstream-1"`). A client sends it in `_register`; the host
  rejects mismatches. **Bump it whenever you change anything that goes over the wire** (RPC
  signatures, `net_pack()` layout, lobby keys that old builds would misread).
- **Lobby state** lives on the host and is mirrored to everyone with `_sync_lobby.rpc(players,
  lobby)`:
  - `Net.players`: `peer id -> {name, paint, car}`; clients change their own choice through
    `_set_choice` (an `any_peer` RPC to the host, which validates and re-broadcasts).
  - `Net.lobby`: `{track, laps, bots, difficulty, weather}` plus, at race start,
    `weather_timeline`. Only the host changes it (`Net.set_lobby()`).
- **Race start**: `Net.start_race()` (host) builds the grid (bots, then players in join order)
  and calls `_begin_race.rpc(grid, lobby)` (`call_local`), so every machine copies the settings
  into `Game` and changes to `scenes/race.tscn` with the identical grid. After the race the host
  calls `Net.back_to_lobby()`.

### In the race (`race.gd`)

- **Same world everywhere**: the track, scenery, crowds and weather timeline are built from the
  track def with seeded RNGs (`Gx.rng`, `hash(def.id)`), so nothing about the world is sent.
  This is why world-building code must never use unseeded randomness.
- **Entries** are created from `Game.grid` in slot order on every machine, so a slot index means
  the same car everywhere. Bot car models are derived from the slot and the available car list,
  so all players need the same game version and the same car files.
- **Ownership**: each machine simulates its own driver's car; the **host also simulates every
  bot** (`e.local = is_me or (e.bot and _is_authority())`). All other cars are **puppets**:
  `Car.set_remote()` makes them kinematic, on collision layer 2, with no local physics.
- **Car state stream**: 30 times a second each machine sends its local cars
  (`_net_cars.rpc(states)`, `unreliable_ordered`), where each state is `Car.net_pack()`: a
  `PackedFloat32Array` of position, rotation quaternion, linear and angular velocity, steering,
  rpm, throttle, brake, gear, speed, four suspension compressions, skid and drift (25 floats).
  The receiver checks that the sender owns that slot (the peer itself, or the host for bots), then
  `net_push()` buffers it. Puppets are drawn `NET_DELAY` (0.1 s) in the past, interpolated between
  states, and extrapolated briefly when starved. Wheels, audio, smoke and lights read the same
  public fields, so they work on puppets unchanged.
- **Contact**: local cars do not collide physically with puppets (they are drawn slightly in the
  past); `_soft_contact()` applies a soft push instead.
- **Host authority** for everything that decides the race (`_is_authority()`):
  - start lights: `_net_lights.rpc(count)` (reliable), `-1` = go;
  - lap counting and lap times: only the host runs the scoring in `_on_line_crossed()`;
  - standings, 5 times a second: `_net_race.rpc(race_time, state, data)` with per-entry
    `[lap, last_lap, best_lap, finished, finish_time, lap_start]`; clients also take
    `race_time` from it, which drives the changeable weather clock;
  - race end: `_net_finished.rpc()`.
- **Disconnects**: `_on_peer_left()` removes that player's car; `Net._fail()` returns a client to
  the menu with a message if the host leaves.

## Adding a synced feature

First decide **who owns the truth** and **whether it needs sending at all**:

1. **Can every machine compute it?** Prefer this. Derive it from shared state (track def, grid,
   lobby, seeded RNG, `race_time`). Example: the changeable weather is a pure function of the
   host's timeline and the race clock (`scripts/world/weather_cycle.gd`).
2. **Per-race setting chosen before the start** (a race option, a rule): put it in `Net.lobby`
   (host side, `Net.set_lobby({...})` or in `start_race()`), read it in `_begin_race()` into
   `Game`, and use it when the race scene builds. Plain types only (int, float, String, Array,
   Dictionary); no Objects or Resources.
3. **Continuous per-car state** (a new light, a visual state, a horn): append it to the end of
   `Car.net_pack()`, read it in `_remote_step()`, raise the size check in `net_push()` (currently
   `state.size() < 25`) and bump `Net.PROTOCOL`. Keep it a float; this stream is sent 30 times a
   second for every car.
4. **Event or decision about the race** (penalty, flag, chat line): an RPC from the authority.
   Pattern from `race.gd`:
   ```gdscript
   ## Host: show a yellow flag at a lap position for everyone.
   func raise_yellow(along: float) -> void:
   	if not _is_authority():
   		return
   	_apply_yellow(along)
   	if _online():
   		_net_yellow.rpc(along)


   @rpc("authority", "reliable")
   func _net_yellow(along: float) -> void:
   	_apply_yellow(along)
   ```
   For requests from clients use `@rpc("any_peer", "reliable")` on a function the host runs, check
   `multiplayer.get_remote_sender_id()` like `_net_cars()` and `Net._set_choice()` do, then
   broadcast the result from the host.

Rules:

- Keep single player working: guard network calls with `_online()` / `Net.is_host()`; with no
  peer the same code path must still run locally.
- Never trust a client for race results; clients only send their own car's state.
- `reliable` for rare events, `unreliable_ordered` for streams. Do not send per-frame data
  reliably.
- RPC functions must exist with the same signature in both builds: bump `Net.PROTOCOL` when they
  change.

## Testing with two instances

`menu.gd` has debug switches for automated network tests:

- `-- --nethost --wait=N [--weather=K] [--name=Host]`: hosts (Valle Club, 1 lap, 2 bots) and
  starts once N players are in.
- `-- --netjoin=<ip> [--name=Guest]`: joins.

Run the host headless and the client windowed so they use different lanes of the run queue and
run at the same time (the headless lane has a single slot):

```sh
LIMIT=240 tools/hrun.sh -- --nethost --wait=2 --name=Host --telemetry > /tmp/host.log 2>&1 &
sleep 2
LIMIT=240 tools/bgrun.sh "" -- --netjoin=127.0.0.1 --name=Guest --telemetry > /tmp/guest.log 2>&1
wait
grep -E "host:|lap|SCRIPT ERROR|t=" /tmp/host.log /tmp/guest.log | head -50
```

`--telemetry` prints every car's lap, speed and position every 2 s on each instance; compare the
two logs (laps and positions must agree; puppets should not show stuck or teleporting cars).
Add `--weather=7` to the host to check that the changeable weather plays the same on both.

Then test on two real machines on the same network (discovery needs UDP broadcast; allow the
game through the firewall), and over a VPN (ZeroTier, Radmin) by IP. Check: lobby updates when
the client changes car or paint, the client sees the host's bots driving smoothly, lap times and
the finish order agree, both return to the lobby, and a client quitting mid-race does not break
the host.
