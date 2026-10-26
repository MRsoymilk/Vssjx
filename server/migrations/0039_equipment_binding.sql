-- Missing binding history is conservatively bound. Never rewrite historical migrations.
UPDATE characters SET loot_state = jsonb_set(jsonb_set(loot_state, '{items}',
    COALESCE((SELECT jsonb_agg(item || jsonb_build_object('bound', COALESCE(item->'bound','true'::jsonb)))
              FROM jsonb_array_elements(loot_state->'items') item),'[]'::jsonb)), '{pending}',
    COALESCE((SELECT jsonb_agg(item || jsonb_build_object('bound', COALESCE(item->'bound','true'::jsonb)))
              FROM jsonb_array_elements(loot_state->'pending') item),'[]'::jsonb));
