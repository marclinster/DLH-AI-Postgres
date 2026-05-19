/* 
  Setup script for the fruit store dataset with vector embeddings.
  This script creates a table to hold fruit data along with their feature vectors,
  and populates it with sample data for testing vector similarity queries.
*/


CREATE EXTENSION IF NOT EXISTS vector;


-- Define a simple table to hold fruit data with vector embeddings
DROP TABLE IF EXISTS fruit_vectors;
CREATE TABLE fruit_vectors (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  features VECTOR(3) -- [taste, color, softness]
);

-- Insert sample fruit data with 3-dimensional feature vectors
INSERT INTO fruit_vectors (name, description, features) VALUES
  ('Apple',  'Sweet, medium red, medium firm',   '[0.70, 0.60, 0.50]'),
  ('Banana', 'Very sweet, yellow, soft',         '[0.95, 0.90, 0.80]'),
  ('Mango',  'Very sweet, orange, very soft',    '[0.90, 0.80, 0.70]'),
  ('Lemon',  'Very tart, yellow, firm',          '[0.30, 0.20, 0.40]'),
  ('Orange', 'Sweet-tart, orange, firm',         '[0.80, 0.70, 0.40]'),
  ('Peach',  'Sweet, pinkish, very soft',        '[0.85, 0.65, 0.90]'),
  ('Grape',  'Sweet, purple/green, soft-ish',    '[0.75, 0.50, 0.40]'),
  ('Kiwi',   'Tart-sweet, brown/green, soft',    '[0.60, 0.35, 0.60]'),
  ('Potato', 'Starchy, brown, firm',             '[0.20, 0.15, 0.10]'),
  ('Cherry', 'Sweet, red, firm',                 '[0.80, 0.55, 0.50]');



-- Optional index for faster KNN (ivfflat requires ANALYZE after insert)
CREATE INDEX ON fruit_vectors USING ivfflat (features vector_l2_ops) WITH (lists = 10);
ANALYZE fruit_vectors;

