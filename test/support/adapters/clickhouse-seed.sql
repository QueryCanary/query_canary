-- Create table
CREATE TABLE numbers
(
    id UInt32,
    value Int32
)
ENGINE = MergeTree()
ORDER BY id;

-- Insert 25 sample values
INSERT INTO numbers (id, value) VALUES 
  (1, 10), (2, 12), (3, 15), (4, 14), (5, 18),
  (6, 20), (7, 19), (8, 22), (9, 25), (10, 21),
  (11, 24), (12, 27), (13, 26), (14, 30), (15, 28),
  (16, 29), (17, 31), (18, 33), (19, 35), (20, 34),
  (21, 36), (22, 38), (23, 40), (24, 42), (25, 45);