SELECT id, name, description,
       features <-> '[0.95,0.90,0.80]' AS distance
FROM fruit_vectors
ORDER BY distance ASC;


SELECT id, name, description,
       features <=> '[0.95,0.90,0.80]' AS distance
FROM fruit_vectors
ORDER BY distance ASC;

-- add strawberry and pear to the fruit_vectors table with the following feature vectors:
-- strawberry: [0.95, 0.90, 0.80]
-- pear: [0.80, 0.85, 0.90]
INSERT INTO fruit_vectors (name, description, features) VALUES
('Strawberry', 'Very sweet, red, soft', '[0.95, 0.55, 0.80]'),
('Pear', 'Not sweet, green, firm', '[0.4, 0.3, 0.50]');


SELECT id, name, 
        description,
        features <=> '[0.95,0.90,0.80]' AS cosine,
        features <-> '[0.95,0.90,0.80]' AS euclidean,
        features <#> '[0.95,0.90,0.80]' AS inner_product,
        features <+> '[0.95,0.90,0.80]' AS manhattan
FROM fruit_vectors
ORDER BY cosine ASC;