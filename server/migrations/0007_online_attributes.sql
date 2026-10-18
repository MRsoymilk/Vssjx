ALTER TABLE characters ADD COLUMN allocated_attributes INTEGER[] NOT NULL DEFAULT '{0,0,0,0,0}';
ALTER TABLE characters ADD CONSTRAINT allocated_attributes_valid CHECK (
    array_ndims(allocated_attributes)=1 AND array_lower(allocated_attributes,1)=1
    AND array_upper(allocated_attributes,1)=5 AND array_position(allocated_attributes,NULL) IS NULL
    AND 0 <= ALL(allocated_attributes) AND 250 >= ALL(allocated_attributes)
    AND allocated_attributes[1]+allocated_attributes[2]+allocated_attributes[3]+allocated_attributes[4]+allocated_attributes[5] <= level*5
);
