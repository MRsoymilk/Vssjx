"""Reusable out-of-combat supplies; gameplay values are reconstructed rules."""
def catalog_items():
    return [dict(id=f'supply/{resource}_gourd',name=name,slot='gourd',price=200,
                 attack=0,defense=0,visual=0,head_visual=0,level=1,job=-1,
                 icon=f'res://assets/items/original/ix{icon}.png',restore_hp=0,restore_mp=0,
                 resource=resource,capacity=capacity,category='药品',sections=['hot','elixir'],
                 rules_basis='重建规则；仅战斗外自动补给，按实际恢复扣储量；NPC免费补充，每种限持一个')
            for resource,name,capacity,icon in [('hp','气血葫芦',10000,22),('mp','灵力葫芦',5000,23)]]
