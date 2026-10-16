"""Interpret serialized ANI references as the verified v48 native reader does.

22d74 stores frame/sequence tables backwards; 22fc8 dereferences native IDs.
Raw parse_ani output remains byte-order evidence and must not be mutated.
"""
import struct
from PIL import Image


def source_steps(animation, serialized_sequence):
    count = len(animation['frames'])
    return [[count - 1 - frame, ticks] for frame, ticks in animation['sequences'][serialized_sequence]]


def native_steps(animation, native_sequence):
    return source_steps(animation, len(animation['sequences']) - 1 - native_sequence)


def event_masks(animation):
    # 22b78 -> 27874 -> 27850: forward BE32 masks indexed by NATIVE sequence ID.
    tail = bytes.fromhex(animation['opaque_tail_hex'])
    if not tail:
        return []
    count = tail[0]
    if len(tail) < 1 + count * 4:
        raise ValueError('Truncated native ANI event masks')
    return list(struct.unpack_from('>' + str(count) + 'I', tail, 1))


def actor_playback(key, animation, source_dir):
    ids = {'idle': 4, 'walk': 0, 'attack': 5, 'hurt': 6}
    if not native_steps(animation, 0):
        # Monsters have no native 0/1 gait. Do not relabel another combat action.
        ids['walk'] = 4
    if key.endswith(('mfs', 'wfs')):
        # Native sequence 8 visibly raises/floats the staff. Its association
        # with the reconstructed skill is a presentation choice, not a recovered skill ID.
        ids['cast'] = 8
    playback = {mode: native_steps(animation, index) for mode, index in ids.items()}
    masks = event_masks(animation)
    impacts = {mode: [step for step in range(len(playback[mode]))
                      if index < len(masks) and masks[index] & (1 << step)]
               for mode, index in ids.items()}
    centers = {}
    for mode in (('idle', 'walk', 'attack', 'hurt') if key.startswith('hero/') else ('idle', 'attack', 'hurt')):
        centers[mode] = []
        for frame, _ in playback[mode]:
            bodies = [layer for layer in animation['frames'][frame]
                      if layer['source'] == animation['sources'][0] and layer['frame'] == 0]
            if len(bodies) != 1 or bodies[0]['transform'] != 0:
                raise ValueError(key + ': unaudited native ' + mode + ' body')
            body = bodies[0]
            with Image.open(source_dir / f"{body['source']}_frame000.png") as image:
                centers[mode].append(body['x'] + image.width // 2)
    return playback, {
        'indexing': 'reverse_serialized_tables', 'source_frame_count': len(animation['frames']),
        'sequence_ids': ids, 'impact_steps': impacts, 'attack_x': centers.pop('attack'),
        'pose_x': centers,
        'attack_basis': 'target', 'cast_mapping': 'reviewed_pose_not_recovered_skill_id' if 'cast' in ids else None,
    }
