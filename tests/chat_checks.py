"""Public channel checks against real authenticated WebSockets and PostgreSQL."""
from uuid import uuid4


class ChatProbe:
    def __init__(self, ws):
        self.ws = ws
        self.messages = []

    def until(self, predicate):
        for _ in range(200):
            data, _ = self.ws.recv()
            assert data['type'] != 'error', data
            if data['type'] == 'chat.batch': self.messages.extend(data['messages'])
            if predicate(data): return data
        raise AssertionError('No matching chat packet')

    def send(self, text, message_id=None, channel='public'):
        message_id = message_id or str(uuid4())
        self.ws.send(dict(type='chat.send', client_message_id=message_id, channel=channel, text=text))
        return message_id

    def result(self, message_id, status):
        packet = self.until(lambda data: data['type'] == 'chat.result' and data['result']['client_message_id'] == message_id and data['result']['status'] != 'QUEUED')
        assert packet['result']['status'] == status, packet
        return packet['result']

    def seen(self, message_id):
        if not any(message['message_id'] == message_id for message in self.messages):
            self.until(lambda data: any(message['message_id'] == message_id for message in self.messages))
        return next(message for message in self.messages if message['message_id'] == message_id)


def exercise_chat(a, b, first_id, second_id, db):
    alice, bob = ChatProbe(a), ChatProbe(b)
    literal = '[url=https://invalid.example]你好[/url] <b>world</b>'
    original = alice.send(literal)
    result = alice.result(original, 'SENT')
    remote = bob.seen(result['message_id'])
    assert remote['text'] == literal and remote['sender_character_id'] == first_id and remote['display_name'] == '青云甲'
    assert remote['channel'] == 'public' and int(remote['server_time_ms']) > 0
    assert not {'account_id', 'session_id', 'client_message_id', 'access_token'} & remote.keys()
    reply = bob.send('同图已收到，移动保持同步。')
    sent = bob.result(reply, 'SENT')
    assert alice.seen(sent['message_id'])['sender_character_id'] == second_id
    alice.send(literal, original)
    assert alice.result(original, 'SENT')['message_id'] == result['message_id']
    bob.ws.send({'type': 'ping'})
    bob.until(lambda data: data['type'] == 'pong')
    assert sum(message['message_id'] == result['message_id'] for message in bob.messages) == 1
    alice.send('不同内容', original)
    assert alice.result(original, 'REJECTED')['code'] == 'CHAT_ID_CONFLICT'
    for text, channel, code in [('换\n行','public','CHAT_INVALID_TEXT'), ('\u202e隐藏','public','CHAT_INVALID_TEXT'), ('空频道','private','CHAT_INVALID_CHANNEL'), ('界'*121,'public','CHAT_INVALID_TEXT')]:
        request = alice.send(text, channel=channel)
        assert alice.result(request, 'REJECTED')['code'] == code
    db.query("UPDATE accounts SET chat_muted_until=NOW()+INTERVAL '1 hour' WHERE username='world_second';")
    request = bob.send('被禁言后不能发送')
    assert bob.result(request, 'REJECTED')['code'] == 'CHAT_MUTED'
    # A previously accepted message stays replayable; mute never rebroadcasts it.
    bob.send('同图已收到，移动保持同步。', reply)
    assert bob.result(reply, 'SENT')['message_id'] == sent['message_id']
    db.query("UPDATE accounts SET chat_muted_until=NOW()-INTERVAL '1 second' WHERE username='world_second';")
    request = bob.send('禁言到期后恢复发送')
    assert bob.result(request, 'SENT')['message_id']
    # Exhaust Alice's per-character budget without changing socket/world ownership.
    limited = False
    for number in range(5):
        request = alice.send('限流验证%d' % number)
        packet = alice.until(lambda data: data['type'] == 'chat.result' and data['result']['client_message_id'] == request and data['result']['status'] != 'QUEUED')['result']
        if packet['status'] == 'REJECTED':
            assert packet['code'] == 'CHAT_RATE_LIMITED', packet
            limited = True
            break
    assert limited
    print('PASS: public chat identity, bidirectional delivery, literal markup, dedup/conflict, validation, mute and personal quota')
    return original, literal, result['message_id']
