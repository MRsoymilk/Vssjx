"""Record bounded static evidence for native v48 ANI playback and battle actions."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SHA256 = 'e08f93bebe133b700f2305bfbedd994b05cc8d04a5a854262af9ced956afbc03'
RANGES = [
    ('reverse_ani_tables', 0x22d74, 0x22e42),
    ('event_mask_loading', 0x22b78, 0x22bd8),
    ('event_mask_trigger', 0x22aa8, 0x22b3c),
    ('native_sequence_selection', 0x22fc8, 0x2301c),
    ('state_dispatch_and_target_origin', 0x245c0, 0x24694),
    ('attack_event_delivery', 0x39d0, 0x3a68),
    ('action_completion', 0x2be4, 0x2c38),
    ('restore_home_and_ready', 0x2ea4, 0x2ed6),
    ('copy_coordinates_source_to_destination', 0x2ee00, 0x2ee0a),
    ('acting_side_draw_list_selection', 0x2f28, 0x2f42),
    ('battle_draw_order', 0x316a, 0x3182),
    ('battle_update_order', 0x3948, 0x3958),
    ('team_side_assignment', 0x36fc, 0x371e),
    ('actor_side_flag_assignment', 0x4948, 0x4960),
    ('reverse_list_renderer', 0x21050, 0x21072),
    ('player_ring_resource_load', 0x2e544, 0x2e56c),
    ('world_player_ring_draw', 0x2bb54, 0x2bb62),
    ('battle_player_ring_draw', 0x2d98, 0x2dbc),
]


def evidence():
    blob = (ROOT / 'analysis/unpacked/ssjx/gameonline.ext').read_bytes()
    if hashlib.sha256(blob).hexdigest() != SHA256:
        raise ValueError('Native evidence applies only to the verified Online v48 binary')
    # Thumb ADD PC reads PC=instruction+4, byte table entries are halfword offsets.
    attack_target = 0x24604 + blob[0x24604] * 2
    if attack_target != 0x24636:
        raise ValueError('Unexpected native state 5 dispatch')
    return {
        'format_version': 1, 'native_sha256': SHA256,
        'frame_table': 'Serialized frame i is native frame count-1-i (22da6..22e0a).',
        'sequence_table': 'Serialized sequence i is native sequence count-1-i (22e26..22e3e).',
        'layer_order': 'The loader reverses layers; renderer 22c18/22c64 walks them backwards again. Serialized compositing order is retained.',
        'state_slots': {'walk': 0, 'ready': 4, 'normal_attack': 5, 'hurt': 6},
        'attack_target': hex(attack_target),
        'attack_origin': '24636..24642 copies first target logical coordinates (+10) into attacker render coordinates (+18). ANI layer offsets then supply approach, strike and retreat.',
        'hit_timing': '22b78 loads forward BE32 masks. 22aa8 tests native sequence mask bit at sequence step, only on tick zero. 39d0 delivers queued action events at those steps.',
        'restore': 'State 5 completion dispatches to 2c24, copies home (+10) to render (+18), then 2ea4 enters state 4 if alive.',
        'actor_draw_order': '4914 stores team side at actor+51. 2f28..2f40 selects the acting team as global list+48; 3174..317e draws list+4c first, then +48 (same order at 3948..3954). The acting side is in front; HUD/effect passes follow.',
        'hurt_recoil': '22c64 renders the original signed ANI layer x/y offsets. Stabilized atlases must restore state-6 body/head centers; e.g. wck 4,6,7,8,9 and langw 3,4,5,6,7.',
        'player_ring': '2e544..2e56a loads dongtai%d and stores its animation at SB+a38. 2bb54..2bb5e draws it at world actor coordinates; 2d98..2db8 draws it before the selected battle actor, excluding states 5,15,16,17. Blue dongtai1.ani uses dttx0.imgs, origin (-15,-10), native steps [3,2,1,0], 30x16 pixels. The original selector field at heroData+0d is not assigned a reconstructed gameplay meaning; the supplied blue reference is used.',
        'limitations': [
            'Native timer cadence has not been verified; Godot currently uses its existing 10 FPS attack clock.',
            'Native masks can contain multiple hit events. Current reconstructed/server rules supply one damage result per action; do not invent extra damage.',
            'Original skill IDs, target lists, effect payloads and full multiplayer turn ordering are not recovered by this evidence.',
            'Mage skill pose uses visually reviewed native sequence 8; its binding to the reconstructed skill is not an original skill mapping.',
        ],
        'evidence': [{'name': name, 'start': hex(start), 'end_exclusive': hex(end),
                      'sha256': hashlib.sha256(blob[start:end]).hexdigest()} for name, start, end in RANGES],
    }


if __name__ == '__main__':
    import argparse
    import sys
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--capstone-path', type=Path)
    args = parser.parse_args()
    report = evidence()
    folder = ROOT / 'analysis/recovery/battle'
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'native_action_evidence.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8', newline='\n')
    if args.capstone_path:
        sys.path.insert(0, str(args.capstone_path))
        from capstone import Cs, CS_ARCH_ARM, CS_MODE_THUMB
        decoder = Cs(CS_ARCH_ARM, CS_MODE_THUMB)
        blob = (ROOT / 'analysis/unpacked/ssjx/gameonline.ext').read_bytes()
        lines = ['; STATIC ONLY; SHA256 ' + SHA256, '; File offsets. Dispatch tables/literals are data, not instructions.']
        for name, start, end in RANGES:
            lines.append(f'\n; {name} [{start:#x}, {end:#x})')
            lines.extend(f'{i.address:08x} {i.bytes.hex():<12} {i.mnemonic:<9} {i.op_str}' for i in decoder.disasm(blob[start:end], start))
        (folder / 'native_action_evidence.asm').write_text('\n'.join(lines) + '\n', encoding='utf-8', newline='\n')
    print('Native attack: target-relative ANI motion; event-mask impacts; restore home.')
