BEGIN;

CREATE TABLE IF NOT EXISTS client (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS battery (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    registered_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    type text NOT NULL,
    manufacturer text,
    storage_location text,
    quantity integer NOT NULL CHECK (quantity >= 0),
    client_id bigint NOT NULL REFERENCES client (id)
);

COMMIT;
