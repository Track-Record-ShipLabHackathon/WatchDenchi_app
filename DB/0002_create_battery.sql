CREATE TABLE BATTERY (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    client_id bigint NOT NULL REFERENCES client(id),
    type text NOT NULL,
    manufacturer text NOT NULL,
    quantity integer NOT NULL CHECK (quantity >= 0),
    storage_location text NOT NULL
);