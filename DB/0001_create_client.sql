CREATE TABLE CLIENT (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    created_at timestamptz NOT NULL DEFAULT now(),
    token_hash bytea NOT NULL UNIQUE
);