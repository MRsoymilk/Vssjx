"""Mirror the authored balance contract into Godot; never rewrite legacy combat data."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PAIRS = (
    ('shared/data/monster-combat-v1.json', 'client/assets/data/monster-combat-v1.json'),
    ('shared/data/loot-v1.json', 'client/assets/data/loot-v1.json'),
    ('shared/data/skill-balance-v1.json', 'client/assets/data/skill-balance-v1.json'),
    ('shared/data/balance-v1.json', 'client/assets/data/balance-v1.json'),
    ('shared/data/balance-v1-vectors.json', 'client/tests/fixtures/balance-v1-vectors.json'),
)


def main():
    for source, target in PAIRS:
        destination = ROOT / target
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes((ROOT / source).read_bytes())
        print(target)


if __name__ == '__main__':
    main()
