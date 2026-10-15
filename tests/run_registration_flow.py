"""Loopback HTTP contract fixture for the real Godot registration UI.

No Docker, production database, saved credentials or WebSocket server is used.
This verifies client routing/requests, not PostgreSQL durability or world sync.
"""
import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import subprocess
import threading
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--render', action='store_true')
    args = parser.parse_args()
    accounts, sessions, refreshes, characters, receipts, posts = {}, {}, {}, {}, {}, []

    class Fixture(BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass

        def reply(self, status, data=None):
            body = json.dumps(data, ensure_ascii=False).encode() if data is not None else b''
            self.send_response(status)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            self.handle_api()

        def do_POST(self):
            self.handle_api()

        def session(self, username):
            token, refresh = uuid4().hex + uuid4().hex, uuid4().hex + uuid4().hex
            sessions[token] = username
            refreshes[refresh] = (username, token)
            return dict(account=accounts[username][0], session_id=str(uuid4()), access_token=token,
                        refresh_token=refresh, expires_in=3600, refresh_expires_in=86400)

        def handle_api(self):
            payload = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))) or '{}')
            username = payload.get('username', '').strip().lower()
            digest = hashlib.sha256(payload.get('password', '').encode()).hexdigest()
            if self.path == '/api/v1/auth/register':
                if len(payload.get('password', '')) < 12:
                    return self.reply(422, {'code': 'WEAK_PASSWORD'})
                if username in accounts:
                    return self.reply(409, {'code': 'ACCOUNT_EXISTS'})
                identity = dict(id=str(uuid4()), username=username)
                accounts[username] = (identity, digest)
                return self.reply(201, {'account': identity})
            if self.path == '/api/v1/auth/login':
                if username not in accounts or accounts[username][1] != digest:
                    return self.reply(401, {'code': 'UNAUTHORIZED'})
                return self.reply(200, self.session(username))
            if self.path == '/api/v1/auth/refresh':
                previous = refreshes.pop(payload.get('refresh_token'), None)
                if previous is None:
                    return self.reply(401, {'code': 'UNAUTHORIZED'})
                username, token = previous
                sessions.pop(token, None)
                return self.reply(200, self.session(username))
            token = self.headers.get('Authorization', '').removeprefix('Bearer ')
            owner = sessions.get(token)
            if not owner:
                return self.reply(401, {'code': 'UNAUTHORIZED'})
            if self.path == '/api/v1/auth/logout':
                del sessions[token]
                return self.reply(204)
            if self.path == '/api/v1/auth/me':
                return self.reply(200, {'account': accounts[owner][0]})
            if self.path == '/api/v1/characters' and self.command == 'GET':
                return self.reply(200, dict(characters=[characters[owner]] if owner in characters else [],
                                            rules_version='creation-v1', name_rules_version='nickname-v1'))
            if self.path == '/api/v1/characters':
                posts.append(payload)
                operation = payload['operation_id']
                if (owner, operation) in receipts:
                    return self.reply(201, dict(operation_id=operation, replayed=True, character=receipts[owner, operation]))
                if payload['display_name'] in ('已占昵称', '青衫ab_1'):
                    return self.reply(409, dict(code='NAME_TAKEN', operation_id=operation))
                if owner in characters:
                    return self.reply(409, dict(code='CHARACTER_LIMIT_REACHED', operation_id=operation))
                if payload['display_name'] == '未决修士' and sum(p['display_name'] == '未决修士' for p in posts) == 1:
                    return self.reply(503, {'code': 'SERVER_BUSY'})
                character = dict(id=str(uuid4()), display_name=payload['display_name'], job=payload['job'],
                                 gender=payload['gender'], school=payload['school'], level=1, hp=95, mp=45,
                                 gold=30, xp=0, quest_stage=0, cell_x=10, cell_y=16, map_id='qingyun_trail',
                                 state_revision='1', rules_version='creation-v1', name_rules_version='nickname-v1')
                characters[owner] = character
                receipts[owner, operation] = character
                if payload['display_name'] == '未决修士':
                    return self.reply(201, dict(operation_id=operation, replayed=False, character=character))
                # Commit succeeded, but the first response is intentionally unavailable.
                return self.reply(503, {'code': 'SERVER_BUSY'})
            if self.path == '/api/v1/world/ticket':
                return self.reply(503, {'code': 'WORLD_UNAVAILABLE'})
            return self.reply(404, {'code': 'NOT_FOUND'})

    server = ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        env = dict(os.environ, SSJX_TEST_SERVER_URL=f'http://127.0.0.1:{server.server_port}',
                   SSJX_NICKNAME_VECTORS=str(ROOT / 'shared/protocol/nickname-v1.json'))
        command = [os.environ.get('GODOT_BIN', 'godot')]
        if args.render:
            command += ['--position', '-2000,-2000', '--audio-driver', 'Dummy']
        else:
            command += ['--headless']
        command += ['--path', str(ROOT / 'client')]
        startup = None
        if os.name == 'nt' and args.render:
            startup = subprocess.STARTUPINFO()
            startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            startup.wShowWindow = subprocess.SW_HIDE
        for scene in ('registration_flow_test', 'online_characters_test', 'account_auth_test'):
            run = subprocess.run(command + [f'res://tests/{scene}.tscn'], env=env, capture_output=True, text=True,
                                 encoding='utf-8', timeout=75, startupinfo=startup)
            print(run.stdout, end='')
            print(run.stderr, end='')
            assert run.returncode == 0 and '0 failures' in run.stdout and not re.search(r'(^ERROR:|SCRIPT ERROR)', run.stderr, re.M)
        assert set(accounts) == {'registration_ui', 'character_ui', 'character_ui_pending', 'ui_player'} and len(characters) == 3
        for name in ('注册青衫', '界面青衫', '未决修士'):
            retries = [post for post in posts if post['display_name'] == name]
            assert len(retries) == 2 and retries[0] == retries[1]
        print('PASS: registration -> original creation scene -> account-owned character -> later login; HTTP fixture only')
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


if __name__ == '__main__':
    main()
