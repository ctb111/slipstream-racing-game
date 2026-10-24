extends Node
## Headless check of the synthesised ambience: timing per weather, level,
## clipping and loop-seam continuity; optionally dumps every sound as .wav.
##   godot --headless --path . res://tests/ambience_test.tscn -- --dump=<dir>

func _ready() -> void:
	var dump := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dump="):
			dump = a.substr(7)
	var total := 0.0
	for k in [Ambience.Cond.CLEAR, Ambience.Cond.STORM, Ambience.Cond.SNOW]:
		var ms := Ambience.synthesise(k)
		total += ms
		print("synth %-5s %6.0f ms" % [Ambience.Cond.keys()[k], ms])
	print("synth total %.0f ms" % total)
	print(Ambience.timings)
	var bad := 0
	var cache := Ambience.cached()
	for key in cache:
		var w: AudioStreamWAV = cache[key]
		var pcm := Ambience._pcm(w)
		var sum := 0.0
		var peak := 0.0
		var diff := 0.0
		var clipped := 0
		for j in pcm.size():
			var v := pcm[j]
			sum += v * v
			peak = maxf(peak, absf(v))
			if absf(v) > 0.999:
				clipped += 1
			if j > 0:
				diff += absf(v - pcm[j - 1])
		var rms := sqrt(sum / pcm.size())
		diff /= pcm.size()
		var looped := w.loop_mode != AudioStreamWAV.LOOP_DISABLED
		var seam := absf(pcm[0] - pcm[pcm.size() - 1]) if looped else 0.0
		var ok := rms > 0.02 and peak > 0.3 and clipped < pcm.size() / 1000 and (not looped or seam < diff * 6.0 + 0.02)
		if not ok:
			bad += 1
		print("%-11s %5.2f s @%5d  rms %.3f  peak %.2f  clip %d  %s %s" % [key, pcm.size() / float(w.mix_rate), w.mix_rate,
			rms, peak, clipped, ("seam %.4f (mean step %.4f)" % [seam, diff]) if looped else "one-shot", "ok" if ok else "BAD"])
		if dump != "":
			w.save_to_wav(dump.path_join(key + ".wav"))
	UiSounds._warm_up()
	for key in UiSounds._cache:
		var u: AudioStreamWAV = UiSounds._cache[key]
		print("ui %-8s %d bytes" % [key, u.data.size()])
		if dump != "":
			u.save_to_wav(dump.path_join("ui_" + key + ".wav"))
	print("AMBIENCE TEST %s" % ("PASS" if bad == 0 else "FAIL (%d)" % bad))
	get_tree().quit(1 if bad else 0)
