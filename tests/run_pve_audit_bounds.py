"""Reproduce oversized battle audits using an owned, disposable DB and sockets."""
import copy
import hashlib
import json
import os
import subprocess
from uuid import uuid4

from balance_fixture import BalanceFixture, ROOT
from run_loot_instances import LootPlayer


def main():
    checks = []

    def check(ok, label):
        assert ok, label
        checks.append(label)

    with BalanceFixture() as f:
        identity = f.create('audit_large', 1)
        other = f.create('audit_peer', 0)
        cid = identity[1]
        f.db.query(f"UPDATE characters SET level=60,hp=1000,mp=400,quest_stage=1,cell_x=22,cell_y=9 WHERE id='{cid}'")

        def connect(who):
            p = LootPlayer(f.base, *who)
            f.clients.append(p)
            return p

        p = connect(identity)
        p.approach('wolf_a')
        p.command('', request=dict(operation_id=str(uuid4()), action='challenge', target='wolf_a', encounter_version=2))
        bid = p.state['battle']['id']
        # Model a valid, large replay payload without altering damage or frozen
        # rules. Each narration line and the line count fit the wire validator.
        f.db.query(f"UPDATE pve_battles SET state=jsonb_set(state,'{{formation,lines}}',"
                   f"(SELECT jsonb_agg(repeat('战斗回放',30)) FROM generate_series(1,30))) WHERE id='{bid}'")
        f.restart()
        p = connect(identity)
        q = connect(other)
        before = copy.deepcopy(p.state)
        check(len(before['battle']['formation']['lines']) == 30, 'Restart resumes the existing large battle')
        full = dict(before=before['battle'], after=before['battle'])
        legacy_size = int(f.db.query("SELECT octet_length($owned$" + json.dumps(full, ensure_ascii=False) + "$owned$::jsonb::text)"))
        check(legacy_size > 16384, 'The previous full before/after battle audit exceeds the actual PostgreSQL limit')

        # This is the production failure: flee used to roll back and disconnect,
        # then the same account-owned pending UUID would fail on every reconnect.
        result, operation = p.command('flee')
        check(result['state']['battle']['outcome'] == 'fled', 'Flee from a large battle returns a confirmed receipt')
        check(result['state']['character']['gold'] == before['character']['gold'], 'Retreat does not award gold')
        check(f.db.query(f"SELECT active FROM pve_battles WHERE id='{bid}'") == 'f', 'The battle durably ends')
        audit = json.loads(f.db.query(f"SELECT details FROM security_audit WHERE operation_id='{operation['operation_id']}' AND outcome='accepted'"))
        check(audit['before']['battle']['id'] == bid and audit['before']['battle']['outcome'] == 'active'
              and audit['after']['battle']['outcome'] == 'fled', 'The same transaction records readable battle identity and outcome')
        check(audit['before']['character']['hp'] == before['character']['hp']
              and audit['after']['character']['gold'] == before['character']['gold'], 'Resource before/after values remain readable')
        digest = hashlib.sha256(json.dumps(before['battle'], sort_keys=True, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()
        check(audit['before']['battle']['source']['sha256'] == digest, 'The complete original battle is identified by a stable digest')
        persisted = f.db.query(f"SELECT hp,mp,gold,state_revision FROM characters WHERE id='{cid}'")
        f.restart()
        p = connect(identity)
        q = connect(other)
        check(p.state['battle'] is None, 'Reconnect no longer restores a stuck active battle')
        replay, _ = p.command('', request=operation)
        check(replay['replayed'] and replay['state'] == result['state'], 'The pending UUID confirms the original result after reconnect')
        check(f.db.query(f"SELECT hp,mp,gold,state_revision FROM characters WHERE id='{cid}'") == persisted, 'Replay cannot apply costs or revision changes twice')
        check(f.db.query(f"SELECT count(*) FROM security_audit WHERE operation_id='{operation['operation_id']}' AND outcome='accepted'") == '1', 'Exactly one accepted business audit remains')
        q.command('', request=dict(operation_id=str(uuid4()), action='equip', target='sword',
                                   expected_revision=q.state['character']['state_revision']))
        q.ws.send(dict(type='ping'))
        check(q.until('pong')['type'] == 'pong', 'Another player remains able to act and receive heartbeat replies')

        # Audit writes still fail closed on genuine database errors. Do not
        # silently discard the audit to make a business mutation succeed.
        p.approach('wolf_a')
        p.command('', request=dict(operation_id=str(uuid4()), action='challenge', target='wolf_a', encounter_version=2))
        pending = dict(operation_id=str(uuid4()), action='guard', battle_id=p.state['battle']['id'], expected_revision=p.state['battle']['revision'])
        frozen = f.db.query(f"SELECT state FROM pve_battles WHERE id='{pending['battle_id']}'")
        resources = f.db.query(f"SELECT hp,mp,gold,state_revision FROM characters WHERE id='{cid}'")
        f.db.query("CREATE FUNCTION reject_owned_audit() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN IF NEW.action='pve.guard' THEN RAISE EXCEPTION 'owned audit failure'; END IF; RETURN NEW; END$$; CREATE TRIGGER reject_owned_audit BEFORE INSERT ON security_audit FOR EACH ROW EXECUTE FUNCTION reject_owned_audit();")
        p.ws.send(dict(type='pve.command', command=pending))
        check(p.until('error')['code'] == 'DATABASE_UNAVAILABLE', 'A genuine audit database failure is still rejected')
        check(f.db.query(f"SELECT state FROM pve_battles WHERE id='{pending['battle_id']}'") == frozen
              and f.db.query(f"SELECT hp,mp,gold,state_revision FROM characters WHERE id='{cid}'") == resources,
              'Failed audit rolls back battle, resource and revision changes together')
        check(f.db.query(f"SELECT count(*) FROM pve_operation_receipts WHERE operation_id='{pending['operation_id']}'") == '0', 'A failed transaction cannot publish a successful receipt')
        f.db.query('DROP TRIGGER reject_owned_audit ON security_audit; DROP FUNCTION reject_owned_audit();')
        q.ws.send(dict(type='ping'))
        check(q.until('pong')['type'] == 'pong', 'A failed account transaction does not stall the other connection')
        f.restart()
        p = connect(identity)
        confirmed, _ = p.command('', request=pending)
        check(not confirmed['replayed'], 'The same UUID retries an actual rolled-back operation once')
        replay, _ = p.command('', request=pending)
        check(replay['replayed'] and replay['state'] == confirmed['state'], 'Its next retry is idempotent')

        # Exercise the real Rust append() against exact jsonb byte boundaries,
        # whitespace expansion, UTF-8 and invalid non-object details.
        env = dict(os.environ, SSJX_TEST_AUDIT_DATABASE_URL=f.db.url)
        subprocess.run(['cargo', 'test', '--offline', '--manifest-path', str(ROOT/'server/Cargo.toml'),
                        '--lib', 'security::tests::audit_size_boundary', '--', '--ignored', '--nocapture'],
                       cwd=ROOT, env=env, check=True)
        check(f.db.query("SELECT count(*) FROM security_audit WHERE action='fixture.audit_bounds'") == '4', 'All real PostgreSQL audit boundary cases commit')
        check(int(f.db.query('SELECT max(octet_length(details::text)) FROM security_audit')) <= 16384, 'Every persisted audit still meets the unchanged 16KiB constraint')
        print(f'PVE AUDIT BOUNDS: {len(checks)} checks, 0 failures; legacy battle audit {legacy_size} bytes')


if __name__ == '__main__':
    main()
