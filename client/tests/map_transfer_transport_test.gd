extends "res://tests/online_pve_test.gd"
var listener: TCPServer
var peer: WebSocketPeer
var notices: Array[String] = []

func closed_world(packet: Dictionary = {}, action: String = "", extra_packets: int = 0, close_socket: bool = true) -> OnlineWorldClient:
    listener=TCPServer.new();check(listener.listen(0,"127.0.0.1")==OK,"Owned loopback listener starts")
    var world:=OnlineWorldClient.new();add_child(world);world.set_process(false)
    world.character_id=SELF;world.server=OnlineAccount.server_address;world.login_session=OnlineAccount.login_session_id
    world._state="ready";world.world_ready=true;world._pve_version=1
    world.pve.bind_character(SELF,world.server);world.pve.state=pve_state();world.pve.ready=true
    world._heartbeat=Time.get_unix_time_from_system();world._last_received=world._heartbeat;world.pve.sent_at=world._heartbeat
    world.status_changed.connect(func(text:String)->void:notices.append(text))
    OnlineAccount.pending_pve={} if action.is_empty() else {"realm":world.server,"character":SELF,"command":{"operation_id":SELF,"action":action,"target":"ai_001"}}
    world.socket=WebSocketPeer.new();world.socket.max_queued_packets=128
    check(world.socket.connect_to_url("ws://127.0.0.1:%d"%listener.get_local_port())==OK,"Transport connects to the owned peer")
    var until:=Time.get_ticks_msec()+3000
    while Time.get_ticks_msec()<until:
        if peer==null and listener.is_connection_available():peer=WebSocketPeer.new();peer.accept_stream(listener.take_connection())
        if peer!=null:peer.poll()
        world.socket.poll()
        if peer!=null and peer.get_ready_state()==WebSocketPeer.STATE_OPEN and world.socket.get_ready_state()==WebSocketPeer.STATE_OPEN:break
        await get_tree().process_frame
    check(world.socket.get_ready_state()==WebSocketPeer.STATE_OPEN,"Real WebSocket handshake completes")
    for i in extra_packets:peer.send_text(JSON.stringify({"type":"pong"}))
    if not packet.is_empty():peer.send_text(JSON.stringify(packet))
    peer.poll()
    await get_tree().process_frame
    if close_socket:peer.close()
    until=Time.get_ticks_msec()+3000
    while Time.get_ticks_msec()<until:
        peer.poll();world.socket.poll()
        if not close_socket and world.socket.get_available_packet_count()>0:break
        if world.socket.get_ready_state()==WebSocketPeer.STATE_CLOSED:break
        await get_tree().process_frame
    check((world.socket.get_ready_state()==WebSocketPeer.STATE_CLOSED) if close_socket else (world.socket.get_available_packet_count()>0),"Real transport reaches final-data or closed phase before application processing")
    return world

func release(world: OnlineWorldClient)->void:
    world.leave();world.free();peer=null;listener.stop();notices.clear();OnlineAccount.pending_pve={}

func _run()->void:
    var old:={}
    for key in ["account","server_address","login_session_id","_refresh_expires_at","busy","pending_pve","characters","network_suspended"]:old[key]=OnlineAccount.get(key)
    var processing:=OnlineAccount.is_processing();OnlineAccount.set_process(false)
    OnlineAccount.account={"id":SELF};OnlineAccount.server_address="http://127.0.0.1:1";OnlineAccount.login_session_id=SELF;OnlineAccount._refresh_expires_at=Time.get_unix_time_from_system()+600;OnlineAccount.busy=true;OnlineAccount.network_suspended=false
    var world:=OnlineWorldClient.new();add_child(world);world.set_process(false);world.server=OnlineAccount.server_address
    for capability in [{"maps_version":1,"ai_world_version":1,"expected":2},{"maps_version":1,"expected":1},{"maps_version":2,"expected":2},{"expected":0}]:
        world._state="ticket";var ticket:Dictionary=capability.duplicate();ticket.ok=true;ticket.ticket="owned-ticket"
        world._on_ticket(ticket)
        check(world._exchange_packet().get("maps_version",0)==capability.expected,"Real ticket capability controls the handshake, including expansion support")
        if world.socket!=null:world.socket.close();world.socket=null
    world.free()
    var state:=pve_state(2);state.character.map_id="ancient_ruins";state.character.cell_x=5
    var receipt:={"type":"pve.result","operation_id":SELF,"ok":true,"replayed":false,"lines":[],"state":state}
    world=await closed_world(receipt,"transfer")
    world._process(0)
    check(world._state=="request" and not world.world_ready and (not world.pve.pending() or OnlineAccount.pending_pve.command.operation_id==SELF),"Final close either consumes its receipt or preserves the UUID for confirmation")
    check(notices==["正在切换地图……"] and world._attempts==0,"Expected room close never becomes DISCONNECTED or consumes a retry")
    release(world)
    world=await closed_world(receipt,"transfer",67,false)
    world._process(0)
    check(world.socket!=null and world.pve.pending() and notices.is_empty(),"A bounded packet drain retains the unread tail for the next frame")
    world._process(0)
    check(not world.pve.pending() and notices==["正在切换地图……"],"Receipt behind the per-frame packet budget still completes normally")
    release(world)
    world=await closed_world({},"ai_travel")
    world._process(0)
    check(world._state=="request" and world.pve.pending() and OnlineAccount.pending_pve.command.operation_id==SELF and notices==["正在切换地图……"],"Lost transfer receipt preserves its UUID for authoritative confirmation after reconnect")
    release(world)
    world=await closed_world({},"school_join")
    world._process(0)
    check(world._state=="request" and world.pve.pending() and OnlineAccount.pending_pve.command.operation_id==SELF and notices==["正在切换地图……"] and world._attempts==0,"Lost admission receipt keeps its original UUID and rejoins without a false disconnect")
    release(world)
    world=await closed_world({"type":"error","code":"SESSION_REVOKED"},"",0,false)
    world._process(0)
    check(world._state=="failed" and notices==["账号会话失效，请重新登录。"],"Queued authentication rejection is not hidden by a generic disconnected error")
    release(world)
    world=await closed_world()
    world._process(0)
    check(world._attempts==1 and notices==["连接中断：DISCONNECTED"],"Unexpected connection loss still reports an actual failure")
    release(world)
    for key in old:OnlineAccount.set(key,old[key])
    OnlineAccount.set_process(processing)
    print("MAP TRANSFER TRANSPORT: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
