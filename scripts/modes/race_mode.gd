class_name RaceMode
extends Node
## Base for a game mode layered on top of race.gd (championship round, time
## trial). race.gd creates one when Game.session isn't a plain race, asks it for
## setup overrides before building the circuit, adds it as a child, and the HUD
## asks it for results buttons / points. Everything here is a no-op default.

var race: Node ## race.gd (untyped: avoids a cyclic class reference)


## Before the circuit is built. Keys (all optional): track (String), laps (int),
## grid (Array like Game.grid), game (Dictionary of Game properties to set only
## while the race sets itself up, e.g. {difficulty = 2, car_id = "..."}).
func setup_overrides() -> Dictionary:
	return {}


## After every car is spawned, before the countdown.
func attach(_race: Node) -> void:
	race = _race


## Line under "RESULTS" (empty = the race's default).
func results_subtitle() -> String:
	return ""


## Adds this mode's buttons to the results panel. `make` is RaceHud._button
## (parent, text, callback). Returns false to fall back to the default buttons.
func results_buttons(_parent: Control, _make: Callable) -> bool:
	return false


## Championship points this entry scored in the race (-1 = no points column).
func points_for(_entry) -> int:
	return -1
