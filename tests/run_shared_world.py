"""Disposable PostgreSQL/Rust + two independent Godot clients, optional real rendering."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from uuid import uuid4
from pg_fixture import PostgresFixture
from run_account_auth import stop
from run_server_connection import wait_for_server
from ws_fixture import WebSocket
from chat_checks import ChatProbe, exercise_chat

ROOT = Path(__file__).resolve().parents[1]
HASH = hashlib.sha256((ROOT / 'shared/data/qingyun-v1.json').read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--render', action='store_true')
    parser.add_argument('--output', type=Path, default=Path('/tmp/opencode/vssjx-shared-world'))
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    assert (ROOT / 'shared/data/qingyun-v1.json').read_bytes() == (ROOT / 'client/assets/data/qingyun-v1.json').read_bytes()
    imported = subprocess.run([os.environ.get('GODOT_BIN', 'godot'), '--headless', '--path', str(ROOT / 'client'), '--import'], capture_output=True, text=True, check=True)
    (args.output / 'import.log').write_text(imported.stdout + imported.stderr)
    assert not re.search(r'(^ERROR:|SCRIPT ERROR)', imported.stdout + imported.stderr, re.M), 'Godot import failed; see import.log'
    subprocess.run([os.environ.get('GODOT_BIN', 'godot'), '--headless', '--path', str(ROOT / 'client'), 'res://tests/public_chat_test.tscn'], check=True)
    subprocess.run([os.environ.get('GODOT_BIN', 'godot'), '--headless', '--path', str(ROOT / 'client'), 'res://tests/world_delta_test.tscn'], check=True)
    subprocess.run(['cargo', 'build', '--locked', '--manifest-path', str(ROOT / 'server/Cargo.toml')], check=True)
    with PostgresFixture() as db, tempfile.TemporaryDirectory(prefix='vssjx-world-') as scratch:
        env = {k: v for k, v in os.environ.items() if not k.startswith('SSJX_')}
        env.update(SSJX_ENV_FILE='', SSJX_DATABASE_URL=db.url, SSJX_BIND_ADDR='127.0.0.1:0', RUST_LOG='info',
                   SSJX_AUTH_RATE_IP='1000', SSJX_AUTH_RATE_GLOBAL='10000', SSJX_AUTH_RATE_ACCOUNT='100', SSJX_WORLD_SAVE_SECONDS='1', SSJX_WORLD_RECONNECT_SECONDS='2', SSJX_MONITOR_BIND_ADDR='', SSJX_LOG_DIR='')
        def start():
            process = subprocess.Popen([str(ROOT / 'server/target/debug/vssjx-server')], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            try: return process, wait_for_server(process)
            except BaseException:
                stop(process)
                raise
        process, base = start()
        sockets = []
        children = []
        logs = []
        password = 'world-test-password-1234'
        def api(path, data=None, token=None):
            headers = {'Content-Type': 'application/json'}
            if token: headers['Authorization'] = 'Bearer ' + token
            body = json.dumps(data).encode() if data is not None else None
            try: response = urlopen(Request(base + path, data=body, headers=headers), timeout=10)
            except HTTPError as error: response = error
            with response:
                body = response.read()
                return response.code, json.loads(body) if body else {}
        def user(name, display):
            assert api('/api/v1/auth/register', {'username': name, 'password': password})[0] == 201
            code, session = api('/api/v1/auth/login', {'username': name, 'password': password})
            assert code == 200
            code, created = api('/api/v1/characters', {'operation_id': str(uuid4()), 'display_name': display, 'job': 2, 'gender': int(name.endswith('bob')), 'school': 0, 'rules_version': 'creation-v1'}, session['access_token'])
            assert code == 201
            return session, created['character']['id']
        def ticket(session, character):
            code, data = api('/api/v1/world/ticket', {'character_id': character, 'protocol_version': 1, 'config_hash': HASH}, session['access_token'])
            assert code == 200, data
            return data['ticket']
        def connect(raw):
            ws = WebSocket(base.replace('http://', 'ws://') + '/api/v1/world/ws')
            sockets.append(ws)
            ws.send({'type': 'auth.exchange', 'ticket': raw, 'protocol_version': 1, 'config_hash': HASH, 'world_sync_version': 2})
            return ws, ws.recv()[0]
        def motion(ready, seq, target):
            data = {key: ready[key] for key in ('game_session_id', 'connection_epoch', 'world_epoch')}
            data.update(type='world.move_to', input_seq=str(seq), target=target)
            return data
        def error(ws, code):
            for _ in range(80):
                data, _raw = ws.recv()
                if data['type'] == 'error':
                    assert data['code'] == code, data
                    return
            raise AssertionError('Expected error ' + code)
        try:
            outsider = WebSocket(base.replace('http://', 'ws://') + '/api/v1/world/ws')
            sockets.append(outsider)
            outsider.send({'type': 'chat.send', 'client_message_id': str(uuid4()), 'channel': 'public', 'text': '未认证不能读写公共频道'})
            assert outsider.recv()[0] == {'type': 'error', 'code': 'INVALID_HANDSHAKE'}
            outsider.close()
            first, first_id = user('world_first', '青云甲')
            second, second_id = user('world_second', '青云乙')
            assert api('/api/v1/world/ticket', {'character_id': first_id, 'protocol_version': 1, 'config_hash': HASH})[0] == 401
            assert api('/api/v1/world/ticket', {'character_id': second_id, 'protocol_version': 1, 'config_hash': HASH}, first['access_token'])[0] == 403
            assert api('/api/v1/world/ticket', {'character_id': first_id, 'protocol_version': 1, 'config_hash': '0' * 64}, first['access_token'])[1]['code'] == 'CONFIG_MISMATCH'
            old = ticket(first, first_id)
            raw = ticket(first, first_id)
            invalid, message = connect(old)
            assert message['code'] == 'INVALID_TICKET'
            invalid.close()
            a, ready_a = connect(raw)
            assert ready_a['type'] == 'auth.ready'
            initial_chat = ChatProbe(a).until(lambda data: data['type'] == 'chat.ready')
            assert initial_chat['latest_seq'] == '0' and initial_chat['oldest_seq'] == '1'
            replay, message = connect(raw)
            assert message['code'] == 'INVALID_TICKET'
            replay.close()
            b, ready_b = connect(ticket(second, second_id))
            assert ready_b['type'] == 'auth.ready'
            entities = a.snapshot(lambda values: len(values) == 2)
            assert {first_id, second_id} == set(entities)
            assert all(not {'account_id', 'gold', 'hp', 'potions', 'session_id'} & entity.keys() for entity in entities.values())
            chat_id, chat_text, chat_message = exercise_chat(a, b, first_id, second_id, db)
            # A newly admitted character cannot read messages from before entry.
            late_session, late_id = user('world_late', '后到修士')
            late, _ = connect(ticket(late_session, late_id))
            late_chat = ChatProbe(late)
            boundary = late_chat.until(lambda data: data['type'] == 'chat.ready')
            assert int(boundary['latest_seq']) > 0
            assert int(boundary['oldest_seq']) == int(boundary['latest_seq']) + 1
            request = late_chat.send('上线后的消息[微笑]')
            delivered = late_chat.result(request, 'SENT')['message_id']
            assert late_chat.seen(delivered)['text'] == '上线后的消息[微笑]'
            assert [message['message_id'] for message in late_chat.messages] == [delivered]
            late.send({'type': 'world.leave'})
            assert late_id not in b.snapshot(lambda values: late_id not in values)
            late.close()
            a.send(motion(ready_a, 1, [13, 16]))
            moved = b.snapshot(lambda values: values[first_id]['cell'] == [13, 16] and values[first_id]['next_cell'] is None)
            assert moved[second_id]['cell'] == [10, 16]
            time.sleep(0.12)
            a.send(motion(ready_a, 2, [8, 8]))
            error(a, 'INVALID_TARGET')  # Exported scenery blocker.
            time.sleep(0.12)
            a.send(motion(ready_a, 3, [5, 10]))
            error(a, 'INVALID_TARGET')  # River.
            time.sleep(0.12)
            a.send(motion(ready_a, 2, [12, 16]))
            error(a, 'STALE_INPUT')
            _, another = api('/api/v1/auth/login', {'username': 'world_first', 'password': password})
            denied, message = connect(ticket(another, first_id))
            assert message['code'] == 'CHARACTER_BUSY'
            denied.close()
            replacement, ready_new = connect(ticket(first, first_id))
            assert ready_new['game_session_id'] == ready_a['game_session_id']
            assert int(ready_new['connection_epoch']) == int(ready_a['connection_epoch']) + 1
            error(a, 'SESSION_REPLACED')
            a.close()
            resumed_chat = ChatProbe(replacement)
            resumed_ready = resumed_chat.until(lambda data: data['type'] == 'chat.ready')
            assert resumed_ready['oldest_seq'] == initial_chat['oldest_seq']
            assert replacement.snapshot()[first_id]['cell'] == [13, 16]
            resumed_chat.send(chat_text, chat_id)
            assert resumed_chat.result(chat_id, 'SENT')['message_id'] == chat_message
            replacement.send(motion(ready_a, 4, [20, 16]))
            error(replacement, 'STALE_CONNECTION')
            replacement.send({'type': 'world.leave'})
            assert first_id not in b.snapshot(lambda values: first_id not in values)
            replacement.close()
            assert db.query(f"SELECT cell_x || ',' || cell_y FROM characters WHERE id='{first_id}';") == '13,16'
            # A new login is allowed after explicit leave, loading the durable coordinate.
            a, ready_a = connect(ticket(another, first_id))
            reentered_chat = ChatProbe(a).until(lambda data: data['type'] == 'chat.ready')
            assert int(reentered_chat['oldest_seq']) == int(reentered_chat['latest_seq']) + 1
            assert a.snapshot()[first_id]['cell'] == [13, 16]
            assert ready_a['game_session_id'] != ready_new['game_session_id']
            _, refreshed = api('/api/v1/auth/refresh', {'refresh_token': another['refresh_token']})
            a.send({'type': 'ping'})
            while True:
                message, _ = a.recv()
                assert message['type'] != 'error', message
                if message['type'] == 'pong': break
            assert api('/api/v1/auth/logout', {}, refreshed['access_token'])[0] == 204
            error(a, 'SESSION_REVOKED')
            assert first_id not in b.snapshot(lambda values: first_id not in values)
            a.close()
            db.query("UPDATE accounts SET disabled=TRUE WHERE username='world_second';")
            error(b, 'SESSION_REVOKED')
            b.close()
            expired_session, expired_id = user('world_expired', '票据过期')
            expired_ticket = ticket(expired_session, expired_id)
            db.query("UPDATE world_tickets SET expires_at=NOW()-INTERVAL '1 second';")
            expired, message = connect(expired_ticket)
            assert message['code'] == 'INVALID_TICKET'
            expired.close()

            # Restart recovers coordinates, never trusts a client's position or old ticket.
            logs.append(stop(process))
            process, base = start()
            _, first = api('/api/v1/auth/login', {'username': 'world_first', 'password': password})
            persisted, _ = connect(ticket(first, first_id))
            restarted_chat = ChatProbe(persisted).until(lambda data: data['type'] == 'chat.ready')
            assert restarted_chat['channel_epoch'] != initial_chat['channel_epoch'] and restarted_chat['latest_seq'] == '0'
            assert persisted.snapshot()[first_id]['cell'] == [13, 16]
            persisted.send({'type': 'world.leave'})
            time.sleep(0.15)
            persisted.close()

            sessions = {}
            for role, display in [('alice', '同图青衫'), ('bob', '同图听雪')]: sessions[role] = user('world_ui_' + role, display)
            sync = Path(scratch).resolve()
            for role in ('alice', 'bob'):
                other = 'bob' if role == 'alice' else 'alice'
                child_env = dict(env, SSJX_TEST_SERVER_URL=base, SSJX_WORLD_ROLE=role, SSJX_WORLD_SYNC=sync.as_posix(), SSJX_WORLD_OTHER=sessions[other][1], SSJX_WORLD_RENDER='1' if args.render else '0')
                command = [sys.executable, str(ROOT / 'tests/run_offscreen.py'), '--rendering-driver', 'opengl3_es'] if args.render else [os.environ.get('GODOT_BIN', 'godot'), '--headless']
                command += ['--path', str(ROOT / 'client'), 'res://tests/shared_world_test.tscn']
                logfile = (args.output / f'{role}.log').open('w')
                child = subprocess.Popen(command, env=child_env, stdout=logfile, stderr=subprocess.STDOUT)
                children.append((role, child, logfile))
            def wait_mark(*names):
                deadline = time.monotonic() + 35
                while not all((sync / name).exists() for name in names):
                    for role, child, log in children:
                        if child.poll() is not None:
                            log.flush()
                            raise AssertionError(f'{role} exited early; see {args.output / (role + ".log")}')
                    assert time.monotonic() < deadline, ('Godot barrier timeout', names)
                    time.sleep(0.05)
            wait_mark('alice_seen', 'bob_seen')
            (sync / 'go').write_text('go')
            wait_mark('alice_moved', 'bob_moved')
            (sync / 'reconnect').write_text('go')
            wait_mark('alice_done', 'bob_done')
            (sync / 'finish').write_text('go')
            for role, child, log in children:
                assert child.wait(timeout=15) == 0
                log.close()
                text = (args.output / f'{role}.log').read_text()
                print(text)
                assert '0 failures' in text and not re.search(r'(^ERROR:|SCRIPT ERROR)', text, re.M)
            for path in sync.glob('*.png'): (args.output / path.name).write_bytes(path.read_bytes())
            for role in ('alice', 'bob'):
                assert (sync / f'{role}_offline.json').read_text() == 'offline-sentinel'
            if args.render:
                from PIL import Image
                for role in ('alice', 'bob'):
                    with Image.open(args.output / f'{role}_together.png') as one, Image.open(args.output / f'{role}_moved.png') as two:
                        assert one.size == two.size == (640, 960)
                        assert one.crop((0, 56, 640, 836)).tobytes() != two.crop((0, 56, 640, 836)).tobytes()
            print('PASS: tickets, isolation, authoritative movement, public chat, ownership fencing, revocation, persistence and TWO independent Godot clients')
        finally:
            for ws in sockets: ws.close()
            for _role, child, log in children:
                if child.poll() is None:
                    child.terminate()
                    try: child.wait(timeout=8)
                    except subprocess.TimeoutExpired: child.kill(); child.wait()
                if not log.closed: log.close()
            logs.append(stop(process))
            assert password not in ''.join(logs) and db.password not in ''.join(logs)


if __name__ == '__main__': main()
