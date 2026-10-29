extends Node
## Friendly matches on the same Wi-Fi or a phone hotspot, with no game server. The host runs the game's own
## server code (NetworkController in server mode, on its own SceneMultiplayer) inside the app and plays through
## it like any client; other devices on the network find it by a UDP beacon, or type its address. Battles are
## computed exactly as online, but nothing is ranked: accounts never reach a non-official server.

const NetworkControllerScript = preload("res://scripts/NetworkController.gd")
const BuildInfo = preload("res://scripts/ServerStats.gd")

const HOST_PORT := 7781
const DISCOVERY_PORT := 7782
const BEACON_SECONDS := 1.0
## A host that has not been heard from for this long leaves the list.
const HOST_TTL_MSEC := 4000
const MAGIC := "keepfall-local"
const MAX_BEACON := 256

signal hosts_changed(hosts: Array)

var host_holder: Node = null
var host_server = null
var host_name := ""
var beacon: PacketPeerUDP = null
var beacon_elapsed := 0.0
var listener: PacketPeerUDP = null
## address -> {"name", "version", "port", "seen"}
var hosts: Dictionary = {}

func hosting() -> bool:
	return host_server != null

## Starts the in-app server and its beacon. Returns false when the port is taken.
func start_host(nickname: String, port: int = HOST_PORT) -> bool:
	if hosting():
		return true
	host_holder = Node.new()
	host_holder.name = "LocalHost"
	get_tree().root.add_child(host_holder)
	# The server's own multiplayer, so the host's client and server can live in one process. The node path
	# below the holder mirrors Bootstrap/Main/NetworkController, which is where RPCs are addressed.
	get_tree().set_multiplayer(SceneMultiplayer.new(), host_holder.get_path())
	var bootstrap := Node.new()
	bootstrap.name = "Bootstrap"
	host_holder.add_child(bootstrap)
	var main := Node.new()
	main.name = "Main"
	bootstrap.add_child(main)
	var server = NetworkControllerScript.new()
	server.name = "NetworkController"
	main.add_child(server)
	server.replays.enabled = false # the players keep their own replays
	if not server.start_dedicated_server(port):
		stop_host()
		return false
	host_server = server
	host_name = nickname
	beacon = PacketPeerUDP.new()
	beacon.set_broadcast_enabled(true)
	beacon_elapsed = BEACON_SECONDS
	return true

func stop_host() -> void:
	if host_server != null and host_server.multiplayer.multiplayer_peer != null:
		host_server.multiplayer.multiplayer_peer.close()
	host_server = null
	if is_instance_valid(host_holder):
		host_holder.queue_free()
	host_holder = null
	if beacon != null:
		beacon.close()
	beacon = null

## Starts listening for hosts on this network.
func start_search() -> bool:
	if listener != null:
		return true
	listener = PacketPeerUDP.new()
	listener.set_broadcast_enabled(true)
	if listener.bind(DISCOVERY_PORT) != OK:
		listener = null
		return false
	hosts.clear()
	return true

func stop_search() -> void:
	if listener != null:
		listener.close()
	listener = null
	hosts.clear()

func stop_all() -> void:
	stop_search()
	stop_host()

func _process(delta: float) -> void:
	if beacon != null:
		beacon_elapsed += delta
		if beacon_elapsed >= BEACON_SECONDS:
			beacon_elapsed = 0.0
			_send_beacon()
	if listener != null:
		_receive()

func _send_beacon() -> void:
	var packet := beacon_packet(host_name, HOST_PORT).to_utf8_buffer()
	for address in broadcast_addresses(IP.get_local_addresses()):
		beacon.set_dest_address(address, DISCOVERY_PORT)
		beacon.put_packet(packet)

static func beacon_packet(nickname: String, port: int) -> String:
	return JSON.stringify({"magic": MAGIC, "name": nickname.left(16), "version": BuildInfo.ruleset_id(), "port": port})

## The general broadcast address plus each local IPv4 network's /24 broadcast: phone hotspots
## (192.168.43.x and similar) often drop 255.255.255.255 but deliver their own subnet's broadcast.
static func broadcast_addresses(local_addresses: Array) -> Array:
	var result := ["255.255.255.255"]
	for address in local_addresses:
		var parts := String(address).split(".")
		if parts.size() != 4 or String(address).begins_with("127.") or String(address).begins_with("169.254."):
			continue
		var subnet := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
		if not result.has(subnet):
			result.append(subnet)
	return result

## Parses a beacon; empty when it is not one of ours.
static func parse_beacon(text: String) -> Dictionary:
	if text.length() > MAX_BEACON:
		return {}
	# Other apps broadcast on networks too; parse quietly.
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var data = json.data
	if not data is Dictionary or data.get("magic") != MAGIC or not data.get("name") is String or not data.get("version") is String or not (data.get("port") is int or data.get("port") is float):
		return {}
	var port := int(data.port)
	if port < 1 or port > 65535 or String(data.name).length() > 16 or String(data.version).length() > 64:
		return {}
	return {"name": String(data.name), "version": String(data.version), "port": port}

func _receive() -> void:
	var changed := false
	while listener.get_available_packet_count() > 0:
		var text := listener.get_packet().get_string_from_utf8()
		var address := listener.get_packet_ip()
		var info := parse_beacon(text)
		if info.is_empty() or address.is_empty():
			continue
		info["seen"] = Time.get_ticks_msec()
		if not hosts.has(address) or hosts[address].name != info.name or hosts[address].version != info.version:
			changed = true
		hosts[address] = info
	for address in hosts.keys():
		if Time.get_ticks_msec() - int(hosts[address].seen) > HOST_TTL_MSEC:
			hosts.erase(address)
			changed = true
	if changed:
		hosts_changed.emit(host_list())

## Hosts found so far: {"address", "name", "port", "compatible"}, newest version match first.
func host_list() -> Array:
	var rows: Array = []
	var version := BuildInfo.ruleset_id()
	for address in hosts:
		rows.append({"address": String(address), "name": String(hosts[address].name), "port": int(hosts[address].port), "compatible": String(hosts[address].version) == version})
	rows.sort_custom(func(a, b): return a.compatible and not b.compatible or (a.compatible == b.compatible and String(a.name) < String(b.name)))
	return rows

## The addresses other players can type to reach this device (IPv4, not loopback).
static func shareable_addresses(local_addresses: Array) -> Array:
	var result: Array = []
	for address in local_addresses:
		var text := String(address)
		if text.split(".").size() == 4 and not text.begins_with("127.") and not text.begins_with("169.254."):
			result.append(text)
	# Hotspot gateways (x.x.x.1) first: on a phone hotspot that is the host's address.
	result.sort_custom(func(a, b): return a.ends_with(".1") and not b.ends_with(".1"))
	return result

static func valid_address(text: String) -> bool:
	var parts := text.strip_edges().split(".")
	if parts.size() != 4:
		return false
	for part in parts:
		if not part.is_valid_int() or int(part) < 0 or int(part) > 255:
			return false
	return true
