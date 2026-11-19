BEGIN;

ALTER TABLE battery RENAME COLUMN registed_at TO registered_at;
-- Old rows remain NULL because their chemistry is unknown.
ALTER TABLE battery ADD COLUMN chemical text;

CREATE TABLE device (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 registered_at timestamptz NOT NULL DEFAULT now(),
 type text NOT NULL,
 name text NOT NULL,
 client_id bigint NOT NULL REFERENCES client(id)
);
CREATE TABLE device_battery (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 device_id bigint NOT NULL UNIQUE REFERENCES device(id),
 battery_id bigint NOT NULL REFERENCES battery(id),
 battery_quantity integer NOT NULL CHECK (battery_quantity BETWEEN 1 AND 100),
 started_at timestamptz NOT NULL,
 prediction_at timestamptz NOT NULL
);
CREATE INDEX battery_client_id_idx ON battery(client_id);
CREATE INDEX device_client_id_idx ON device(client_id);
CREATE INDEX device_battery_battery_id_idx ON device_battery(battery_id);

COMMIT;
