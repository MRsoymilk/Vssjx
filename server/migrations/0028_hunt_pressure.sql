-- Character-owned counter survives reconnects; every actual map transfer resets it.
ALTER TABLE characters ADD COLUMN hunt_pressure JSONB NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(hunt_pressure) = 'object');
CREATE FUNCTION reset_hunt_pressure_on_transfer() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.map_id IS DISTINCT FROM OLD.map_id THEN NEW.hunt_pressure := '{}'::jsonb; END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER character_hunt_transfer BEFORE UPDATE OF map_id ON characters
FOR EACH ROW EXECUTE FUNCTION reset_hunt_pressure_on_transfer();
