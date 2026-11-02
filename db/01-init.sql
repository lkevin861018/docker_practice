-- This file runs only during the FIRST initialization of an empty PostgreSQL volume.
CREATE TABLE IF NOT EXISTS visits (
    id BIGSERIAL PRIMARY KEY,
    visitor VARCHAR(80) NOT NULL CHECK (length(btrim(visitor)) > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
