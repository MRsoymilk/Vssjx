"""Owned database: portal authority, map isolation, receipts, restart, and real Godot UI."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import threading
import time
from uuid import uuid4

from pg_fixture import PostgresFixture
from run_account_auth import stop
from run_online_pve import HASH, Player, api
from run_server_connection import wait_for_server
from ws_fixture import WebSocket

ROOT = Path(__file__).resolve().parents[1]


class MapPlayer(Player):
    instances = []

    def until(self, kind, operation=None):
        now = time.monotonic()
        for peer in self.instances:
            if not peer.closed and now - peer.keepalive > 3:
                peer.keepalive = now
                try: peer.ws.send(dict(type="ping"))
                except OSError: pass
        return super().until(kind, operation)

    def close(self):
        self.closed = True
        super().close()

    def flush(self):
        self.ws.send(dict(type="ping"))
        self.until("pong")
    def __init__(self, base, session, character, maps_version=1):
        self.base, self.session, self.id = base, session, character
        status, ticket = api(base, '/api/v1/world/ticket', dict(
            character_id=character, protocol_version=1, config_hash=HASH), session['access_token'])
        assert status == 200, ticket
        self.ws = WebSocket(base.replace('http://', 'ws://') + '/api/v1/world/ws')
        self.ws.send(dict(type='auth.exchange', ticket=ticket['ticket'], protocol_version=1,
                          config_hash=HASH, world_sync_version=2, population_version=1,
                          pve_version=1, maps_version=maps_version))
        self.population, self.state, self.seq = {}, {}, 0
        self.closed, self.keepalive = False, time.monotonic()
        self.instances.append(self)
        self.ready = self.until('auth.ready')
        self.state = self.until('pve.state')['state']
        self.until('population.state')
        name = 'ancient-ruins-v1.json' if self.ready['map_id'] == 'ancient_ruins' else 'qingyun-v1.json'
        assert self.ready['map_hash'] == hashlib.sha256((ROOT / 'shared/data' / name).read_bytes()).hexdigest()

    def walk(self, goal):
        self.move(goal)
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            self.until('world.delta')
            own = self.ws.entities[self.id]
            if own['cell'] == goal and own['next_cell'] is None:
                return
        raise AssertionError('Portal not reached')


def main():
    binary = os.environ.get('SSJX_TEST_SERVER_BIN', str(ROOT / 'server/target/debug/vssjx-server'))
    sockets = []
    with PostgresFixture() as db:
        env = {k: v for k, v in os.environ.items() if not k.startswith('SSJX_')}
        env.update(SSJX_ENV_FILE='', SSJX_DATABASE_URL=db.url, SSJX_BIND_ADDR='127.0.0.1:0',
                   SSJX_MONITOR_BIND_ADDR='', SSJX_LOG_DIR='', RUST_LOG='info',
                   SSJX_AUTH_RATE_IP='1000', SSJX_AUTH_RATE_GLOBAL='10000',
                   SSJX_AUTH_RATE_ACCOUNT='100', SSJX_WORLD_RECONNECT_SECONDS='1')

        def start():
            process = subprocess.Popen([binary], env=env, stdout=subprocess.PIPE,
                                       stderr=subprocess.STDOUT, text=True, encoding='utf-8')
            try:
                base = wait_for_server(process)
            except BaseException:
                stop(process)
                raise
            threading.Thread(target=lambda: list(process.stdout), daemon=True).start()
            return process, base

        def create(name, stage=0):
            password = 'owned-map-test-password'
            assert api(base, '/api/v1/auth/register', dict(username=name, password=password))[0] == 201
            code, session = api(base, '/api/v1/auth/login', dict(username=name, password=password))
            assert code == 200
            code, data = api(base, '/api/v1/characters', dict(operation_id=str(uuid4()),
                display_name=name, job=0, gender=0, school=0, rules_version='creation-v1'), session['access_token'])
            assert code == 201, data
            cid = data['character']['id']
            # Only seed our disposable characters. Production progression remains authoritative.
            if stage:
                db.query(f"UPDATE characters SET quest_stage={stage},level=8,hp=246,mp=91 WHERE id='{cid}'")
            return session, cid

        def join(session, cid):
            player = MapPlayer(base, session, cid)
            sockets.append(player)
            return player

        def run_ui():
            create('map_ui', 3)
            godot_env = dict(os.environ, SSJX_MAP_TEST_BASE=base,
                             SSJX_MAP_TEST_PASSWORD='owned-map-test-password')
            args = [os.environ['GODOT_BIN'], '--path', str(ROOT / 'client')]
            if os.environ.get('SSJX_MAP_RENDER') != '1': args.append('--headless')
            result = subprocess.run(args + ['res://tests/online_maps_live_test.tscn'],
                env=godot_env, capture_output=True, text=True, encoding='utf-8', timeout=100)
            print(result.stdout); print(result.stderr)
            assert result.returncode == 0 and '0 failures' in result.stdout and 'SCRIPT ERROR' not in result.stderr

        process, base = start()
        try:
            if os.environ.get('SSJX_MAP_UI_ONLY') == '1':
                run_ui()
                return
            session, cid = create('map_first')
            other, other_id = create('map_second', 3)
            watcher, watcher_id = create('map_watcher')
            a, b, c = join(session, cid), join(other, other_id), join(watcher, watcher_id)
            value, _ = a.command('transfer', 'ruins_gate', ok=False)
            assert value['code'] == 'PORTAL_TOO_FAR'
            a.walk([28, 16])
            value, _ = a.command('transfer', 'ruins_gate', ok=False)
            assert value['code'] == 'PORTAL_LOCKED'
            db.query(f"UPDATE characters SET quest_stage=3,level=8,hp=246,mp=91 WHERE id='{cid}'")
            value, _ = a.command('transfer', 'trail_gate', ok=False)
            assert value['code'] == 'INVALID_PORTAL'

            # A failed receipt must roll back the map and position together.
            db.query("CREATE FUNCTION reject_map_receipt() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'owned rollback probe'; END$$; CREATE TRIGGER reject_map BEFORE INSERT ON pve_operation_receipts FOR EACH ROW EXECUTE FUNCTION reject_map_receipt();")
            a.ws.send(dict(type='pve.command', command=dict(operation_id=str(uuid4()), action='transfer', target='ruins_gate')))
            assert a.until('error')['code'] == 'DATABASE_UNAVAILABLE'
            assert db.query(f"SELECT map_id FROM characters WHERE id='{cid}'") == 'qingyun_trail'
            db.query('DROP TRIGGER reject_map ON pve_operation_receipts; DROP FUNCTION reject_map_receipt();')
            a.close()
            a = join(session, cid)
            receipt, transfer = a.command('transfer', 'ruins_gate')
            assert receipt['state']['character']['map_id'] == 'ancient_ruins'
            a.close()
            a = join(session, cid)
            assert a.ready['map_id'] == 'ancient_ruins'
            assert a.state['character']['cell_x'] == 5 and a.state['character']['cell_y'] == 16
            assert set(a.population) == {'guardian', 'boss'}
            assert set(a.ws.entities) == {cid}
            for _ in range(500):
                if set(c.ws.entities) == {other_id, watcher_id}: break
                c.until("world.delta")
            assert set(c.ws.entities) == {other_id, watcher_id}, c.ws.entities
            replay, _ = a.command('', request=transfer)
            assert replay['replayed'] and replay['state'] == receipt['state']

            # A second player joins the ruins; only same-map players are replicated.
            b.walk([28, 16])
            b.command('transfer', 'ruins_gate')
            b.close()
            b = join(other, other_id)
            assert set(b.ws.entities) == {cid, other_id}
            for _ in range(500):
                if set(a.ws.entities) == {cid, other_id}: break
                a.until("world.delta")
            assert set(a.ws.entities) == {cid, other_id}

            # NPCs from the other map cannot be invoked by guessed IDs.
            value, _ = a.command('restore', 'qingwei', ok=False)
            assert value['code'] == 'INVALID_RESIDENT'
            a.walk([17, 19])
            a.command('challenge', 'guardian')
            value, _ = a.command('transfer', 'trail_gate', ok=False)
            assert value['code'] == 'BATTLE_ACTIVE'
            while a.state['battle']['outcome'] == 'active':
                a.command('skill' if a.state['battle']['mp'] >= 9 else 'attack')
            assert a.state['battle']['outcome'] == 'victory'
            assert 'guardian' in a.state['progress']['defeated']
            a.close()
            a = join(session, cid)
            value, _ = a.command('challenge', 'guardian', ok=False)
            assert value['code'] == 'MONSTER_RESPAWNING'

            a.walk([24, 12])
            a.command('challenge', 'boss')
            while a.state['battle']['outcome'] == 'active':
                a.command('skill' if a.state['battle']['mp'] >= 9 else 'attack')
            assert a.state['battle']['outcome'] == 'victory'
            assert a.state['character']['quest_stage'] == 4
            a.close()
            a = join(session, cid)
            value, _ = a.command('challenge', 'boss', ok=False)
            assert value['code'] == 'MONSTER_RESPAWNING'
            a.walk([3, 16])
            a.command('transfer', 'trail_gate')
            a.close()
            a = join(session, cid)
            assert a.ready['map_id'] == 'qingyun_trail'

            # Existing single-map clients keep working, but cannot enter unknown terrain.
            a.close()
            legacy = MapPlayer(base, session, cid, maps_version=0)
            sockets.append(legacy)
            legacy.walk([28, 16])
            legacy.ws.send(dict(type='pve.command', command=dict(operation_id=str(uuid4()), action='transfer', target='ruins_gate')))
            assert legacy.until('error')['code'] == 'MAP_UPDATE_REQUIRED'
            assert db.query(f"SELECT map_id FROM characters WHERE id='{cid}'") == 'qingyun_trail'
            legacy.close()
            a = join(session, cid)
            assert a.state['character']['quest_stage'] == 4
            # Old transfer receipts cannot send a character back to the ruins.
            a.command('', request=transfer)
            a.close()
            a = join(session, cid)
            assert a.ready['map_id'] == 'qingyun_trail'

            # Service restart restores the second player's map and authoritative position.
            a.close(); b.close(); c.close(); stop(process)
            process, base = start()
            b = join(other, other_id)
            assert b.ready['map_id'] == b.state['character']['map_id'] == 'ancient_ruins'
            assert set(b.population) == {'guardian', 'boss'}
            print('ONLINE MAPS: authority, rollback, isolation, replay, ruins battles, return and restart passed')

            if os.environ.get('GODOT_BIN'): run_ui()
        finally:
            for player in sockets:
                try: player.close()
                except OSError: pass
            stop(process)


if __name__ == '__main__':
    main()
