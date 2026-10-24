class_name GxFans
extends RefCounted
## Crowd pieces for the Gx kit: WRC-style fans on the banks, red smoke flares,
## flag wavers, hand-painted bedsheet banners, spectator tape, apex
## photographers with camera flashes, sponsor banners on the rail.
## Implementation: scripts/track/trackside_kit.gd (one shared TracksideKit per
## circuit: everything merges per 80 m cell; people are PeopleKit crowds with
## their own LOD; smoke / flashes / flags are shader-animated MultiMeshes; no
## real lights). gimmicks.gd calls GxFans.flush(c) after the track's dress().
##
## `xf` is a Gx.frame(c, along, side, lateral): the piece goes at that spot on
## that side; people always stay behind the guardrail (and gravel traps) even
## when `lateral` is smaller, and step back to `lateral` when it is larger.
##
##   GxFans.place(c, Gx.frame(c, 640.0, Gx.RIGHT, 9.0))                   # a knot of ~14 fans
##   GxFans.place(c, xf, {count = 24, flares = 2, flags = 3, banner = true}) # big WRC bank
##   GxFans.place(c, xf, {kind = "photographers"})                        # 1-2 snappers + flashes
##   GxFans.place(c, xf, {kind = "banners", length = 60.0})               # sponsor banners on the rail
##   GxFans.place(c, xf, {kind = "flags", count = 4, keys = ["flag_it"]}) # flags on poles only
##   GxFans.place(c, xf, {kind = "flare"})                                # one fan holding a flare
##
## opts (kind "bank", the default):
##   count 14       fans (cheering / clapping, facing the road)
##   flags 2        flags on poles among them (random national / chequered / fan club)
##   flares 0       red smoke flares held up by fans (int; true = 1)
##   banner ""      bedsheet banner on stakes in front ("f_weber", "f_rossi", "f_lind",
##                  "f_hopp", "f_novak", "f_duval"; true = random)
##   tape true      red/white spectator tape in front of them
##   depth 5.0      how deep the crowd is (m, away from the road)
## kind "banners": length 40 (m along the road, centred on xf), keys [..] from
##   "b_helios" "b_valter" "b_kronen" "b_nordlicht" "b_aurel" "b_rallye" "b_falke"
##   "b_marzelli" "b_spect" "b_press".
## kind "flags": count, keys (TracksideKit.FLAGS names: "flag_de", "flag_it", ...).
## Any kind: outfit "summer" | "winter" | "rain" (default: from the weather, so
##   snow gives dark puffer jackets, rain gives bright waterproofs and umbrellas).
## Each bank also appends {pos, dir, radius, count} to the circuit meta "fan_zones".


static func place(c: Node3D, xf: Transform3D, opts := {}) -> void:
	var kit := TracksideKit.shared(c)
	var p := xf.origin
	var i := kit.nearest(p)
	var side := kit.side_of(p, i)
	var lat := Vector2(p.x - kit.centers[i].x, p.z - kit.centers[i].z).length()
	kit.outfit = str(opts.get("outfit", "")) # "" = from the weather
	match str(opts.get("kind", "bank")):
		"photographers":
			kit.photographer(i, side)
		"banners":
			var half_len := int(float(opts.get("length", 40.0)) / TracksideKit.STEP * 0.5)
			var keys: Array = opts.get("keys", ["b_rallye", "b_helios", "b_kronen", "b_spect"])
			kit.fence_banners(i - half_len, i + half_len, side, keys)
		"flags":
			var keys: Array = opts.get("keys", [])
			for k in int(opts.get("count", 3)):
				var j := i + kit.rng.randi_range(-4, 4)
				var q := kit.at(j, side * maxf(lat, kit.rail_dist(j, side) + 2.5) + side * kit.rng.randf_range(0.0, 3.0))
				if kit.road_clear(q, 1.5):
					kit.flag_pole(q, kit.tangents[kit._i(j)] * (1.0 if kit.rng.randf() < 0.5 else -1.0),
						"" if keys.is_empty() else str(keys[k % keys.size()]))
		"flare":
			var q := kit.at(i, side * maxf(lat, kit.rail_dist(i, side) + 2.4))
			if kit.road_clear(q, 1.5):
				kit.fan(q, -kit.rights[i] * side, 1.0)
				kit.flare(q + Vector3.UP * 2.05 - kit.rights[i] * side * 0.25)
		_:
			var banner = opts.get("banner", "")
			if str(banner) in ["true", "false"]:
				banner = str(banner) == "true"
			if banner is bool:
				banner = TracksideKit.FAN_SHEETS[kit.rng.randi() % TracksideKit.FAN_SHEETS.size()] if banner else ""
			var fl = opts.get("flares", 0)
			kit.spectator_bank(i, side, int(opts.get("count", 14)), {
				flags = int(opts.get("flags", 2)),
				flares = (1 if fl else 0) if fl is bool else int(fl),
				banner = str(banner),
				tape = bool(opts.get("tape", true)),
				depth = float(opts.get("depth", 5.0)),
				min_lat = lat,
			})


## Builds everything placed so far (called by gimmicks.gd after dress()).
static func flush(c: Node3D) -> void:
	TracksideKit.flush(c)
