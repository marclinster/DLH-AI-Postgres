SELECT id, name, description,
       features <-> '[0.95,0.90,0.80]' AS distance
FROM fruit_vectors
ORDER BY distance ASC;


SELECT id, name, description,
       features <=> '[0.95,0.90,0.80]' AS distance
FROM fruit_vectors
ORDER BY distance ASC;


SELECT id, name, 
        description,
        features <=> '[0.95,0.90,0.80]' AS cosine,
        features <-> '[0.95,0.90,0.80]' AS euclidean,
        features <#> '[0.95,0.90,0.80]' AS inner_product,
        features <+> '[0.95,0.90,0.80]' AS manhattan
FROM fruit_vectors
ORDER BY cosine ASC;