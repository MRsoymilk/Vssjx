"""Consensual PK via real sockets, disposable PostgreSQL, optional two Godot UIs."""
import json
import os
from pathlib import Path
import subprocess
import threading
import time
from uuid import uuid4
from pg_fixture import PostgresFixture
from run_account_auth import stop
from run_online_pve import Player, api, HASH
from run_server_connection import wait_for_server
from ws_fixture import WebSocket

ROOT = Path(__file__).resolve().parents[1]


class DuelPlayer(Player):
    peers = []

    def __init__(self, base, session, character, supported=True):
        self.base, self.session, self.id = base, session, character
        code, ticket = api(base, '/api/v1/world/ticket', dict(character_id=character, protocol_version=1, config_hash=HASH), session['access_token'])
        assert code == 200 and ticket['duel_version'] == 2, ticket
        self.ws = WebSocket(base.replace('http://', 'ws://') + '/api/v1/world/ws')
        self.ws.send(dict(type='auth.exchange', ticket=ticket['ticket'], protocol_version=1, config_hash=HASH, world_sync_version=2, population_version=1, pve_version=1, maps_version=2, shop_version=2, duel_version=2 if supported else 0))
        self.population, self.state, self.seq, self.duel_state = {}, {}, 0, {}
        self.closed = False
        self.keepalive = time.monotonic()
        self.peers.append(self)
        self.ready = self.until('auth.ready')
        self.state = self.until('pve.state')['state']
        if supported: self.until('duel.state')

    def until(self, kind, operation=None):
        for peer in self.peers:
            if not peer.closed and time.monotonic() - peer.keepalive > 2:
                peer.ws.send(dict(type='ping')); peer.keepalive = time.monotonic()
        for _ in range(1200):
            value, _ = self.ws.recv()
            if value['type'] == 'error':
                if kind == 'error': return value
                raise AssertionError(value)
            if value['type'] == 'duel.state': self.duel_state = value
            if value['type'] == 'pve.state' or value['type'] == 'pve.result': self.state = value['state']
            if value['type'] == kind and (operation is None or value.get('request_id', value.get('operation_id')) == operation): return value
        raise AssertionError('No ' + kind)

    def synced(self, predicate):
        deadline = time.monotonic() + 8
        while not predicate(self.duel_state) and time.monotonic() < deadline: self.until('duel.state')
        assert predicate(self.duel_state), self.duel_state
        return self.duel_state

    def duel(self, action, ok=True, request=None, **fields):
        time.sleep(.21)
        request = request or dict(request_id=str(uuid4()), action=action, **fields)
        self.ws.send(dict(type='duel.command', command=request))
        value = self.until('duel.result', request['request_id'])
        assert value['ok'] == ok, value
        return value, request

    def close(self):
        if not self.closed: self.closed = True; self.ws.close()


def main():
    binary = os.environ.get('SSJX_TEST_SERVER_BIN', str(ROOT / 'work/duels/target/debug/vssjx-server.exe'))
    checks = []

    def check(value, label):
        assert value, label
        checks.append(label)

    with PostgresFixture() as db:
        env = {k: v for k, v in os.environ.items() if not k.startswith('SSJX_')}
        env.update(SSJX_ENV_FILE='', SSJX_DATABASE_URL=db.url, SSJX_BIND_ADDR='127.0.0.1:0', SSJX_MONITOR_BIND_ADDR='', SSJX_LOG_DIR='', RUST_LOG='info', SSJX_AUTH_RATE_IP='1000', SSJX_AUTH_RATE_GLOBAL='10000', SSJX_AUTH_RATE_ACCOUNT='100', SSJX_WORLD_RECONNECT_SECONDS='1')

        def start():
            process = subprocess.Popen([binary], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding='utf8')
            try: base = wait_for_server(process)
            except BaseException: stop(process); raise
            threading.Thread(target=lambda: list(process.stdout), daemon=True).start()
            return process, base

        process, base = start()
        password = 'owned-duel-test-password'

        def create(name, job=0, gender=0):
            assert api(base, '/api/v1/auth/register', dict(username=name, password=password))[0] == 201
            _, session = api(base, '/api/v1/auth/login', dict(username=name, password=password))
            code, data = api(base, '/api/v1/characters', dict(operation_id=str(uuid4()), display_name=name, job=job, gender=gender, school=3, rules_version='creation-v1'), session['access_token'])
            assert code == 201, data
            cid = data['character']['id']
            db.query(f"UPDATE characters SET level=8,hp=180,mp=50,quest_stage=3 WHERE id='{cid}'")
            return session, cid

        try:
            sa, ia = create('duel_a', 0, 0); sb, ib = create('duel_b', 1, 1); sc, ic = create('duel_c')
            db.query(f"UPDATE characters SET allocated_attributes=ARRAY[0,0,0,20,0] WHERE id='{ib}'")
            a, b, c = DuelPlayer(base, sa, ia), DuelPlayer(base, sb, ib), DuelPlayer(base, sc, ic)
            resources = db.query("SELECT id,hp,mp,gold,xp FROM characters ORDER BY id")
            a.duel('invite', target=ib)
            invite = b.synced(lambda s: s.get('incoming') is not None)['incoming']['id']
            check(b.duel_state['battle'] is None and a.duel_state['battle'] is None, 'Invitation alone cannot start or damage a player')
            value, _ = a.duel('accept', ok=False, invite_id=invite); check(value['code'] == 'DUEL_FORBIDDEN', 'Inviter cannot accept for target')
            value, _ = c.duel('accept', ok=False, invite_id=invite); check(value['code'] == 'DUEL_FORBIDDEN', 'Third player cannot accept an intercepted invitation')
            db.query("CREATE FUNCTION reject_duel_write() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'owned failure'; END $$; CREATE TRIGGER reject_duel BEFORE INSERT ON duel_invite_cooldowns FOR EACH ROW EXECUTE FUNCTION reject_duel_write();")
            value, _ = b.duel('reject', ok=False, invite_id=invite); check(value['code'] == 'DATABASE_UNAVAILABLE', 'Cooldown write failure is not acknowledged as a rejection')
            db.query('DROP TRIGGER reject_duel ON duel_invite_cooldowns; DROP FUNCTION reject_duel_write();')
            _, rejection = b.duel('reject', invite_id=invite)
            b.duel('', request=rejection)
            value, _ = a.duel('invite', ok=False, target=ib)
            check(value['code'] == 'DUEL_REJECT_COOLDOWN' and 290000 <= value['retry_after_ms'] <= 300000, 'Rejected inviter waits five real minutes')
            for p in [a, b, c]: p.close()
            stop(process); process, base = start()
            a, b, c = DuelPlayer(base, sa, ia), DuelPlayer(base, sb, ib), DuelPlayer(base, sc, ic)
            value, _ = a.duel('invite', ok=False, target=ib); check(value['code'] == 'DUEL_REJECT_COOLDOWN', 'Reconnect and server restart cannot bypass cooldown')
            # Expire only this disposable pair rather than making the suite wait five minutes.
            db.query(f"UPDATE duel_invite_cooldowns SET expires_at=clock_timestamp()-interval '1 second' WHERE inviter_id='{ia}' AND target_id='{ib}'")
            a.duel('invite', target=ib)
            invite = b.synced(lambda s: s.get('incoming') is not None)['incoming']['id']
            b.duel('accept', invite_id=invite)
            state = a.synced(lambda s: s.get('battle') is not None and s['battle']['status'] == 'active')['battle']
            b.synced(lambda s: s.get('battle') is not None and s['battle']['id'] == state['id'])
            check({f['id'] for f in state['fighters']} == {ia, ib} and state['fighters'][0]['stats']['hp'] != 180, 'Both authoritative profiles start with isolated full combat resources')
            a.move([11,16]); check(a.until('error')['code'] == 'BATTLE_ACTIVE', 'Movement is blocked by the server during PK')
            value, _ = a.command('restore', 'qingwei', ok=False); check(value['code'] == 'DUEL_ACTIVE', 'PvE and inventory mutations cannot overlap a duel')
            baseline=[f['hp'] for f in state['fighters']]
            _, attack=a.duel('attack',battle_id=state['id'],expected_revision=state['decision_revision'])
            locked=a.synced(lambda s:s['battle']['submitted'][0])['battle']
            check([f['hp'] for f in locked['fighters']]==baseline and locked['events']==[],'One commitment cannot spend resources or deal damage')
            value,_=a.duel('guard',ok=False,battle_id=state['id'],expected_revision=state['decision_revision']);check(value['code']=='DUEL_ALREADY_SUBMITTED','A locked decision cannot be changed or submitted twice')
            hidden=b.synced(lambda s:s['battle']['submitted'][0])['battle']
            check(hidden['your_choice'] is None and 'choices' not in hidden and 'turn' not in hidden,'Opponent decision is hidden until simultaneous resolution')
            b.duel('attack',battle_id=state['id'],expected_revision=state['decision_revision'])
            next_state=a.synced(lambda s:s['battle']['resolved_round']==1)['battle']
            b.synced(lambda s:s['battle']['resolved_round']==1)
            check(next_state['events'][0]['actor']==ib and next_state['fighters'][1]['speed']==120,'Allocated agility determines initiative, irrespective of arrival order')
            actor=a
            actor.duel('',request=attack)
            next_state=a.synced(lambda s:s['battle']['phase']=='planning' or s['battle']['status']=='finished')['battle']
            value,_=actor.duel('attack',ok=False,battle_id=state['id'],expected_revision=state['decision_revision']);check(value['code']=='DUEL_STALE_REVISION','A prior round token cannot deal damage again')
            for _ in range(50):
                if next_state['status']!='active':break
                next_state=a.synced(lambda s:s['battle']['phase']=='planning' or s['battle']['status']=='finished')['battle']
                if next_state['status']!='active':break
                b.synced(lambda s:s['battle']['decision_revision']==next_state['decision_revision'])
                token=next_state['decision_revision'];round_no=next_state['round']
                a.duel('attack',battle_id=state['id'],expected_revision=token)
                b.duel('attack',battle_id=state['id'],expected_revision=token)
                next_state=a.synced(lambda s:s['battle']['resolved_round']>=round_no)['battle']
                b.synced(lambda s:s['battle']['resolved_round']>=round_no)
            check(next_state['status'] == 'finished' and next_state['winner'] in [ia, ib], 'Two real players reach one authoritative winner')
            check(db.query("SELECT id,hp,mp,gold,xp FROM characters ORDER BY id") == resources, 'Sparring never changes permanent health, mana, gold or XP')
            a.duel('invite',target=ib)
            offer=b.synced(lambda s:s.get('incoming') is not None)['incoming']['id']
            b.duel('accept',invite_id=offer)
            active=a.synced(lambda s:s.get('battle') is not None and s['battle']['status']=='active')['battle']
            a.duel('attack',battle_id=active['id'],expected_revision=active['decision_revision'])
            a.synced(lambda s:s['battle']['submitted'][0])
            a.close();time.sleep(.4);a=DuelPlayer(base,sa,ia)
            check(a.duel_state['battle']['id']==active['id'] and a.duel_state['battle']['status']=='active' and a.duel_state['battle']['submitted'][0] and a.duel_state['battle']['your_choice']['action']=='attack','Reconnect restores the same hidden commitment without another choice')
            a.duel('flee',battle_id=active['id'],expected_revision=a.duel_state['battle']['decision_revision'])
            b.synced(lambda s:s.get('battle') is not None and s['battle']['id']==active['id'] and s['battle']['status']=='finished')
            check(b.duel_state['battle']['winner']==ib,'Surrender ends both views with the same winner')
            a.move([11,16]); a.until('world.delta')
            check(db.query("SELECT COUNT(*) FROM security_audit WHERE action LIKE 'duel.%'") != '0', 'Duel actions are attributable in the audit log')
            check(db.query("SELECT COUNT(*) FROM security_audit WHERE action='duel.attack' AND jsonb_typeof(details->'duration_ms')='number' AND details->'progress'->>'phase' IN ('planning','resolving','finished') AND details->'progress'->>'round' IS NOT NULL")!='0','Duel audit distinguishes authoritative round progress and business duration without logging packet bodies')
            # A legacy client must never be forced into a battle it cannot display.
            c.close(); time.sleep(.3); c = DuelPlayer(base, sc, ic, supported=False)
            value, _ = a.duel('invite', ok=False, target=ic); check(value['code'] == 'DUEL_PLAYER_OFFLINE', 'Unsupported clients are protected from duel invitations')
            for p in [a, b, c]: p.close()

            if os.environ.get('GODOT_BIN'):
                _, ui_a = create('duel_ui_a', 0, 0); _, ui_b = create('duel_ui_b', 1, 1)
                # Spend only these owned level-8 fixtures' forty legal points.
                # The revised isolated PvP HP/reduction is deliberately slower
                # than the legacy unallocated fight used by the old 65s UI bound.
                db.query(f"UPDATE characters SET allocated_attributes=ARRAY[8,0,32,0,0] WHERE id IN ('{ui_a}','{ui_b}')")
                # Exercise each UI role against an independent socket peer so its
                # startup and opponent input are controlled separately.
                for role in ['a','b']:
                    partner_role='b' if role=='a' else 'a'
                    _, session=api(base,'/api/v1/auth/login',dict(username='duel_ui_'+partner_role,password=password))
                    partner=DuelPlayer(base,session,ui_b if role=='a' else ui_a)
                    errors=[];heartbeat_done=threading.Event()
                    def heartbeat():
                        while not heartbeat_done.wait(2):
                            try:partner.ws.send(dict(type='ping'))
                            except OSError:return
                    threading.Thread(target=heartbeat,daemon=True).start()
                    def sparring_peer():
                        try:
                            if role=='a':
                                offer=partner.synced(lambda s:s.get('incoming') is not None)['incoming']['id']
                                partner.duel('accept',invite_id=offer)
                            else:
                                while ui_b not in partner.ws.entities:partner.until('world.delta')
                                partner.duel('invite',target=ui_b)
                            partner.synced(lambda s:s.get('battle') is not None and s['battle']['status']=='active')
                            submitted_tokens=set()
                            while partner.duel_state['battle']['status']=='active':
                                duel=partner.duel_state['battle']
                                me=0 if duel['fighters'][0]['id']==partner.id else 1
                                if duel['phase']=='planning' and not duel['submitted'][me] and duel['decision_revision'] not in submitted_tokens:
                                    time.sleep(.4)
                                    partner.duel('attack',battle_id=duel['id'],expected_revision=duel['decision_revision'])
                                    submitted_tokens.add(duel['decision_revision'])
                                partner.until('duel.state')
                        except BaseException as e:errors.append(repr(e))
                    worker=threading.Thread(target=sparring_peer,daemon=True);worker.start()
                    child_env=dict(os.environ,SSJX_DUEL_BASE=base,SSJX_DUEL_ROLE=role,SSJX_DUEL_PASSWORD=password)
                    args=[os.environ['GODOT_BIN']]
                    if os.environ.get('SSJX_DUEL_RENDER')=='1': args+=['--position','-2000,-2000','--audio-driver','Dummy']
                    else:args+=['--headless']
                    args+=['--path',str(ROOT/'client'),'--quit-after','18000','res://tests/duel_live_test.tscn']
                    p=subprocess.Popen(args,env=child_env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf8')
                    try:output,_=p.communicate(timeout=110)
                    except BaseException:p.kill();print(p.communicate()[0]);raise
                    print(output,flush=True)
                    heartbeat_done.set();partner.close();worker.join(timeout=3)
                    check(not errors, 'Protocol sparring peer: '+str(errors))
                    check(p.returncode==0 and '0 failures' in output and 'SCRIPT ERROR' not in output,'Real Godot duel UI completes as '+role)
                    time.sleep(1.2)
            print(f'DUEL SERVER: {len(checks)} checks, 0 failures',flush=True)
        finally:
            for p in DuelPlayer.peers:
                try:p.close()
                except OSError:pass
            stop(process)


if __name__ == '__main__': main()
