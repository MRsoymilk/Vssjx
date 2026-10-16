"""Small RFC6455 test client (stdlib only), never used by the game runtime."""
import base64
import hashlib
import json
import os
import socket
import struct
from uuid import UUID
from urllib.parse import urlsplit


class WebSocket:
    def __init__(self, url, timeout=5, origin=None):
        parsed = urlsplit(url)
        assert parsed.scheme == 'ws' and parsed.hostname == '127.0.0.1'
        self.socket = socket.create_connection((parsed.hostname, parsed.port), timeout)
        self.socket.settimeout(timeout)
        self.buffer = b''
        self.entities = {}
        self.net_ids = {}
        self.world_stream = None
        self.world_seq = 0
        self.assembly = None
        key = base64.b64encode(os.urandom(16)).decode()
        assert origin is None or not any(char in origin for char in '\r\n')
        origin_header = '' if origin is None else f'Origin: {origin}\r\n'
        self.socket.sendall((f'GET {parsed.path} HTTP/1.1\r\nHost: {parsed.netloc}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: {key}\r\n{origin_header}\r\n').encode())
        while b'\r\n\r\n' not in self.buffer:
            self.buffer += self.socket.recv(4096)
            assert len(self.buffer) <= 16384
        headers, self.buffer = self.buffer.split(b'\r\n\r\n', 1)
        assert headers.startswith(b'HTTP/1.1 101'), headers
        accept = base64.b64encode(hashlib.sha1((key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest())
        assert accept.lower() in headers.lower()

    def send(self, value):
        self.send_frame(1, json.dumps(value, separators=(',', ':')).encode())

    def send_frame(self, opcode, body):
        mask = os.urandom(4)
        size = len(body)
        header = bytes([128 | opcode, 128 | size]) if size < 126 else bytes([128 | opcode, 128 | 126]) + struct.pack('!H', size)
        self.socket.sendall(header + mask + bytes(byte ^ mask[i % 4] for i, byte in enumerate(body)))

    def exact(self, size):
        while len(self.buffer) < size:
            data = self.socket.recv(max(4096, size - len(self.buffer)))
            if not data:
                raise EOFError('WebSocket closed')
            self.buffer += data
        result, self.buffer = self.buffer[:size], self.buffer[size:]
        return result

    def recv(self):
        assembled = bytearray()
        while True:
            first, second = self.exact(2)
            length = second & 127
            if length == 126: length = struct.unpack('!H', self.exact(2))[0]
            if length == 127: length = struct.unpack('!Q', self.exact(8))[0]
            assert not second & 128 and length <= 1048576
            body = self.exact(length)
            opcode = first & 15
            if opcode == 8: raise EOFError('WebSocket close frame')
            if opcode == 9:
                self.send_frame(10, body)
                continue
            assert opcode in (0, 1, 2)
            if opcode: message_opcode = opcode
            assembled.extend(body)
            assert len(assembled) <= 1048576
            if first & 128:
                raw = bytes(assembled)
                if message_opcode == 2:
                    return self.delta(raw), raw
                data = json.loads(raw)
                if data['type'] == 'auth.ready': self.world_stream = data['world_stream_id']
                elif data['type'] == 'snapshot.begin': self.assembly = dict(header=data, entities=[], digest=hashlib.sha256(), chunks=0)
                elif data['type'] == 'snapshot.chunk':
                    current = self.assembly
                    assert current and data['snapshot_id'] == current['header']['snapshot_id'] and data['chunk_index'] == current['chunks']
                    current['chunks'] += 1
                    current['digest'].update(struct.pack('!I', len(raw)) + raw)
                    current['entities'].extend(data['records'])
                elif data['type'] == 'snapshot.end':
                    current = self.assembly
                    assert current and data['snapshot_id'] == current['header']['snapshot_id']
                    assert len(current['entities']) == data['count'] == current['header']['count'] and current['chunks'] == data['chunks']
                    assert current['digest'].hexdigest() == data['sha256']
                    self.entities = {entity['id']: entity for entity in current['entities']}
                    self.net_ids = {entity['net_id']: entity['id'] for entity in current['entities']}
                    assert len(self.entities) == len(self.net_ids) == data['count']
                    self.world_seq = int(current['header']['base_world_seq'])
                    self.assembly = None
                return data, raw

    def delta(self, raw):
        assert len(raw) >= 70 and raw[:4] == b'VWD2' and str(UUID(bytes=raw[4:20])) == self.world_stream
        assert hashlib.sha256(raw[:-32]).digest() == raw[-32:]
        seq, size, leaves, moves = struct.unpack_from('!QIHH', raw, 20)
        assert seq == self.world_seq + 1 and len(raw) == 36 + size + leaves * 4 + moves * 26 + 32
        entered = json.loads(raw[36:36+size])
        offset = 36 + size
        for _ in range(leaves):
            net_id, = struct.unpack_from('!I', raw, offset); offset += 4
            self.entities.pop(self.net_ids.pop(net_id))
        for entity in entered:
            assert entity['id'] not in self.entities and entity['net_id'] not in self.net_ids
            self.entities[entity['id']] = entity
            self.net_ids[entity['net_id']] = entity['id']
        for _ in range(moves):
            net_id, cell, next_cell, progress, revision, input_seq = struct.unpack_from('!IHHHQQ', raw, offset); offset += 26
            entity = self.entities[self.net_ids[net_id]]
            entity.update(cell=[cell % 32, cell // 32], next_cell=None if next_cell == 65535 else [next_cell % 32, next_cell // 32], segment_progress=progress, entity_revision=str(revision), last_input_seq=str(input_seq))
        self.world_seq = seq
        return {'type': 'world.delta', 'seq': str(seq), 'count': len(self.entities)}

    def close(self):
        self.socket.close()

    def snapshot(self, predicate=lambda _entities: True, limit=100):
        for _ in range(limit):
            data, _raw = self.recv()
            if data['type'] == 'error': raise AssertionError(data)
            if data['type'] in ['snapshot.end', 'world.delta'] and predicate(self.entities): return self.entities
        raise AssertionError('No matching snapshot')
