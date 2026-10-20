class_name BattleDodgePlayback
extends RefCounted
## Presentation only: move away from the attacker and restore the exact station.
const DURATION:=0.32
var actor:Node2D
var home:=Vector2.ZERO
var step:=Vector2.ZERO
var elapsed:=0.0
var active:=false
func start(subject:Node2D,attacker:Node2D)->void:
	actor=subject;home=actor.position;elapsed=0;active=true
	var direction:=signf(actor.global_position.x-attacker.global_position.x) if is_instance_valid(attacker) else 0.0
	if direction==0:direction=signf(actor.global_transform.x.x)
	var parent:=actor.get_parent() as CanvasItem
	var transform:=parent.get_global_transform() if parent!=null else Transform2D.IDENTITY
	step=transform.affine_inverse()*(actor.global_position+Vector2(direction*12,0))-home
func remaining()->float:return maxf(0,DURATION-elapsed) if active else 0.0
func advance(delta:float)->void:
	if not active:return
	if not is_instance_valid(actor) or not actor.is_inside_tree():cancel();return
	elapsed=minf(DURATION,elapsed+maxf(0,delta))
	var t:=elapsed/0.12 if elapsed<0.12 else 1.0-(elapsed-0.12)/0.20
	t=clampf(t,0,1);actor.position=home+step*t*t*(3-2*t)
	if elapsed>=DURATION-0.000001:cancel()
func cancel()->void:
	if is_instance_valid(actor):actor.position=home
	active=false
