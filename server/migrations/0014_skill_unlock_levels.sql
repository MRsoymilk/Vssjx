-- Reference skills include level 55. Keep local/online characters capped at 60.
ALTER TABLE characters DROP CONSTRAINT characters_level_check;
ALTER TABLE characters ADD CONSTRAINT characters_level_check CHECK (level BETWEEN 1 AND 60);
ALTER TABLE characters DROP CONSTRAINT allocated_attributes_valid;
ALTER TABLE characters ADD CONSTRAINT allocated_attributes_valid CHECK (
    array_ndims(allocated_attributes)=1 AND array_lower(allocated_attributes,1)=1
    AND array_upper(allocated_attributes,1)=5 AND array_position(allocated_attributes,NULL) IS NULL
    AND 0 <= ALL(allocated_attributes) AND 300 >= ALL(allocated_attributes)
    AND allocated_attributes[1]+allocated_attributes[2]+allocated_attributes[3]+allocated_attributes[4]+allocated_attributes[5] <= level*5
);
