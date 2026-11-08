WITH q AS
   (SELECT api.mistral_embed ('Select tart and light yellow fruits for me') AS target_embedding)
SELECT name,
      embedding_vector<=> q.target_embedding as likeness
FROM fruit_with_embedding_vw
JOIN q ON TRUE
ORDER BY likeness ASC
LIMIT 2;


-- Defining the retriever function that will be used to retrieve the most similar fruits based on a given query text.
CREATE OR REPLACE FUNCTION api.sf_retrieve_similar_fruit (p_target TEXT, p_limit INT DEFAULT 2) RETURNS JSONB 
LANGUAGE PLPGSQL AS 
$$
DECLARE
   v_similar_fruit JSONB;
BEGIN
   WITH q AS
       (SELECT api.mistral_embed (p_target) AS target_embedding)
   -- convert the resultset into JSONB
    SELECT JSONB_AGG(matching_fruit) INTO v_similar_fruit FROM (
        -- find the top matching fruit
        SELECT name, embedding_vector<=> q.target_embedding as likeness
            FROM fruit_with_embedding_vw
            JOIN q ON TRUE
            ORDER BY likeness ASC
            LIMIT p_limit) AS matching_fruit;
   -- return from the function
   RETURN v_similar_fruit;
END;
$$;

SELECT JSONB_PRETTY(api.sf_retrieve_similar_fruit('Select tart and light yellow fruits for me', 2));
