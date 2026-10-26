ALTER TABLE characters ADD COLUMN skill_proficiency JSONB NOT NULL DEFAULT '{}'::jsonb
    CHECK(jsonb_typeof(skill_proficiency)='object');
