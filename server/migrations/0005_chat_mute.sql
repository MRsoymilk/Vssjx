-- Chat content/history are intentionally memory-only until retention policy D08.
ALTER TABLE accounts ADD COLUMN chat_muted_until TIMESTAMPTZ;
