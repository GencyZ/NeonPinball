extends Node

const SfxSynthScript := preload("res://juice/sfx_synth.gd")
const POOL_SIZE := 8

var _players: Array = []
var _next := 0
var _ping: AudioStreamWAV

func _ready() -> void:
	_ping = SfxSynthScript.make_ping()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.stream = _ping
		add_child(p)
		_players.append(p)

func _take() -> AudioStreamPlayer:
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	return p

func play_hit(combo: int) -> void:
	var p := _take()
	p.pitch_scale = SfxSynthScript.pitch_scale_for_combo(combo)
	p.play()

func play_settle() -> void:
	var p := _take()
	p.pitch_scale = 0.5
	p.play()
