extends VBoxContainer
## Local audition only. Selection changes always stop the previous resource.
var _updating := false
var _position := 0.0

func _ready() -> void:
	$Controls/Play.pressed.connect(func()->void:
		if $Player.stream!=null:
			if _position >= $Player.stream.get_length():_position=0
			$Player.play(_position)
	)
	$Controls/Stop.pressed.connect(stop)
	$Timeline.value_changed.connect(func(value:float)->void:
		if _updating:return
		_position=value
		if $Player.playing:$Player.seek(value)
		_update_time()
	)
	$Volume/Slider.value_changed.connect(func(value:float)->void:
		$Player.volume_db=value;$Volume/Value.text="%d dB"%int(value)
	)
	$Player.finished.connect(stop)
	visibility_changed.connect(func()->void:if not is_visible_in_tree():stop())

func display(entry:Dictionary)->void:
	stop()
	var preview:Dictionary=entry.get("preview",{})
	visible=preview.get("kind")=="audio"
	$Player.stream=GameAudio.stream(preview.get("audio_id","")) if visible else null
	$Controls/Play.disabled=$Player.stream==null
	$Controls/Stop.disabled=$Player.stream==null
	$Timeline.max_value=$Player.stream.get_length() if $Player.stream!=null else 1
	$Volume/Slider.value=float(entry.get("data",{}).get("volume_db",-6))
	$Player.volume_db=$Volume/Slider.value
	$Volume/Value.text="%d dB"%int($Player.volume_db)
	_update_time()

func stop()->void:
	$Player.stop();_position=0
	_updating=true;$Timeline.value=0;_updating=false
	_update_time()

func _process(_delta:float)->void:
	if not $Player.playing:return
	_position=$Player.get_playback_position()
	_updating=true;$Timeline.value=_position;_updating=false
	_update_time()

func _update_time()->void:
	var length:float=$Player.stream.get_length() if $Player.stream!=null else 0
	$Controls/Time.text="%.2f / %.2f 秒"%[_position,length]
