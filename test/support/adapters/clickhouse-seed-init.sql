CREATE TABLE numbers
(
    id UInt32,
    value Int32
)
ENGINE = MergeTree()
ORDER BY id