-- Create table
CREATE TABLE numbers (
  id SERIAL PRIMARY KEY,
  value INT NOT NULL
);

-- Insert 25 sample values
INSERT INTO numbers (value)
VALUES 
  (10), (12), (15), (14), (18),
  (20), (19), (22), (25), (21),
  (24), (27), (26), (30), (28),
  (29), (31), (33), (35), (34),
  (36), (38), (40), (42), (45);