--- Scaling Up

/*
Creating a function that generates embeddings in small batches, and only if there is no embedding
it returns the number of embeddings that were generated; 0 when all embeddings are complete

Call Tree:
api.batch_fruit_embedding(p_batch_size)  
    -> Loop through fruits without embeddings, and for each one:  
        -> api.fruit_embedding(p_id)  
            -> api.generate_embedding_text(p_id)  
            -> api.mistral_embed(input_text)
*/

DROP FUNCTION IF EXISTS api.batch_fruit_embedding(p_batch_size INTEGER);

CREATE FUNCTION api.batch_fruit_embedding (p_batch_size INTEGER DEFAULT 5) RETURNS INTEGER
AS 
$$
DECLARE 
    v_record RECORD;
    v_embedding_vector vector;
    v_embedding_ctr INTEGER DEFAULT 0;
BEGIN    

-- select p_batch_size rows that have no embedding
-- iterate through those rows, generate embeddings, and insert them into the embedding table.
FOR v_record IN 
    SELECT id, name, description FROM fruit f 
        -- left join finds all fruits that do not have an embedding yet
        -- either because they have no embedding record yet, or the embedding_vector is NULL
        LEFT JOIN embedding e ON f.id = e.fruit_id
        WHERE e.embedding_vector IS NULL 
        LIMIT p_batch_size
    LOOP
        v_embedding_vector := api.fruit_embedding(v_record.id);
        INSERT INTO embedding (embedding_vector, fruit_id)
            VALUES (v_embedding_vector, v_record.id)
        ON CONFLICT (fruit_id) DO 
            UPDATE SET embedding_vector = EXCLUDED.embedding_vector;
        v_embedding_ctr := v_embedding_ctr + 1;
    END LOOP;
RETURN v_embedding_ctr;
END;
$$ LANGUAGE PLPGSQL;





/* 
Test the batch embedding function
This will generate embeddings for any fruit that does not have an embedding yet, and return the number of embeddings that were generated in this batch. 
If you run it multiple times, it should return 0 once all embeddings are generated.

UPDATE embedding e
    SET embedding_vector = NULL
    FROM fruit f
    WHERE e.fruit_id = f.id AND f.name = 'Apple';

SELECT api.batch_fruit_embedding();

SELECT * FROM fruit f
 JOIN embedding e on f.id = e.fruit_id
 WHERE f.name = 'Apple';

 INSERT INTO fruit (name, description) VALUES ('Dragon Fruit', 'Exotic, sweet, pink and white with black seeds');
    SELECT api.batch_fruit_embedding();

SELECT * FROM fruit f
 JOIN embedding e on f.id = e.fruit_id;    
*/

--- Triggers
DROP FUNCTION IF EXISTS api.tr_fruit_embedding();

CREATE FUNCTION api.tr_fruit_embedding() RETURNS TRIGGER 
AS
  $$
    BEGIN
        INSERT INTO embedding (fruit_id, embedding_vector)
            VALUES (NEW.id, api.fruit_embedding(NEW.id))
        ON CONFLICT (fruit_id) DO 
            UPDATE SET embedding_vector = EXCLUDED.embedding_vector;
        CASE TG_OP
            WHEN 'INSERT' THEN RAISE NOTICE 'Created embedding for fruit id %', NEW.id;
            WHEN 'UPDATE' THEN RAISE NOTICE 'Updated embedding for fruit id %', NEW.id;
            ELSE RAISE NOTICE 'No idea what happened';
        END CASE;
        RETURN NEW; -- returns the new row
    END;
  $$ LANGUAGE PLPGSQL;

-- adding the trigger to the table as a AFTER trigger for INSERT and UPDATE
-- The AFTER trigger ensures that the embedding is generated after the fruit data is inserted or updated, 
-- so that the embedding generation function can access the latest data from the fruit table when creating the embedding vector.
-- trigger names are not schema qualified - the trigger inherits the schema of the table
CREATE OR REPLACE TRIGGER tr_fruit_embedding_change
    AFTER INSERT OR UPDATE
    ON fruit 
FOR EACH ROW EXECUTE FUNCTION api.tr_fruit_embedding(); 

/* Test the trigger by inserting a new fruit without an embedding, and seeing if the embedding is generated automatically by the trigger
Check the messages to see the notice from the trigger, and check the embedding table to see if the embedding was generated

*/

INSERT INTO fruit 
    (name, description) 
    VALUES ('Strawberry', 'Sweet, red, soft');

INSERT INTO fruit 
    (name, description) 
    VALUES ('White Grape', 'Tart, light yellow, medium firm');

SELECT * FROM fruit f
    JOIN embedding e on f.id = e.fruit_id; 

UPDATE fruit 
    SET description = 'A little tart, light yellow, medium firm' 
    WHERE name = 'White Grape';

/*
Call Tree:
INSERT INTO fruit (name, description)
    -> tr_fruit_embedding() [AFTER INSERT trigger]
    -> api.tr_fruit_embedding()
    -> api.fruit_embedding(p_id)
        -> api.generate_embedding_text(p_id)
        -> api.mistral_embed(input_text)

*/

-- Try to delete a fruit
DELETE FROM fruit 
    WHERE name = 'White Grape';  

-- create a trigger that deletes the embedding when a fruit is deleted, and returns a notice with the fruit id that was deleted

CREATE OR REPLACE FUNCTION api.tr_fruit_delete_embedding() RETURNS TRIGGER 
AS
  $$
    BEGIN
        DELETE FROM embedding WHERE fruit_id = OLD.id;
        CASE TG_OP
            WHEN 'DELETE' THEN RAISE NOTICE 'Deleted embedding for fruit id %', OLD.id;
            ELSE RAISE NOTICE 'No idea what happened';
        END CASE;
        RETURN OLD; -- returns the old row
    END;
  $$ LANGUAGE PLPGSQL;     

CREATE OR REPLACE TRIGGER tr_fruit_delete_embedding_change
    BEFORE DELETE
    ON fruit
FOR EACH ROW EXECUTE FUNCTION api.tr_fruit_delete_embedding(); 

/* This could also have been done with a foreign key constraint with ON DELETE CASCADE, 
but we are using a trigger here to demonstrate how to use triggers in Postgres. 

ALTER TABLE embedding DROP CONSTRAINT embedding_fruit_id_fkey,
  ADD CONSTRAINT embedding_fruit_id_fkey
  FOREIGN KEY (fruit_id) REFERENCES fruit(id) ON DELETE CASCADE;

*/

SELECT fruit.id, fruit.name, embedding.embedding_vector <=> api.mistral_embed ('tart and light yellow') AS likeness
FROM fruit
JOIN embedding ON fruit.id = embedding.fruit_id
ORDER BY likeness ASC;






/* 
Looking at query timing for the similarity search, and how to optimize it by calculating the target embedding once in a 
Common Table Expression (CTE) and reusing it for all comparisons, instead of calculating it for each row in the fruit table.


Run this query in psql with \timing to see the time it takes to generate the embedding for a new fruit, 
which includes the time to call the Mistral API and store the embedding in the database.
Also watch the messages to see the notice from the embedding generation.
the target text is "Select tart and light yellow fruits for me" will be embedded multiple times!

*/

SELECT name,
       e.embedding_vector <=> api.mistral_embed ('tart and light yellow') AS likeness
FROM fruit f
JOIN embedding e ON f.id = e.fruit_id
ORDER BY likeness ASC;

/*
Running the same query as a Common Table Expression (CTE) to calculate the target embedding once, and 
then use it for all the similarity comparisons, which is more efficient than calculating the target 
embedding for each row in the fruit table.

*/ 


WITH q AS
    (SELECT api.mistral_embed ('tart and light yellow') AS target_embedding)
SELECT f.name,
       e.embedding_vector <=> q.target_embedding as likeness
FROM fruit f
JOIN embedding e ON f.id = e.fruit_id
JOIN q ON TRUE
ORDER BY likeness ASC;


/*
We are building the chatbot consisting of
- the Retriever - api.sf_retrieve_similar_fruit, which takes a target text and returns the most similar fruits 
  from the database based on the embedding vectors, along with their descriptions and likeness scores

- the Narrator - api.sf_narrate_selected_fruit, which takes the results from the retriever and generates a natural 
  language text response using the Mistral Chat API, which summarizes the results from the similarity search and explains the likeness scores.

- the Coordinator - api.coordinator_fruit_selection, which serves as the main interface for the chatbot, coordinating the retrieval and narration functions.

Call Tree:
api.coordinator_fruit_selection(p_target)  
    -> api.sf_retrieve_similar_fruit(p_target, p_limit)  
            -> api.mistral_embed(input_text)
    -> api.sf_narrate_selected_fruit(p_question, p_selected_fruit)  
        -> Mistral Chat API (external)
*/


DROP FUNCTION IF EXISTS api.sf_retrieve_similar_fruit(p_target TEXT, p_limit INT) ;

CREATE FUNCTION api.sf_retrieve_similar_fruit (p_target TEXT, p_limit INT DEFAULT 2) 
RETURNS JSONB
LANGUAGE PLPGSQL
AS
$$
DECLARE 
    v_similar_fruit JSONB;
BEGIN
    WITH q AS
        -- generate the target embedding in the common expression
        (SELECT api.mistral_embed (p_target) AS target_embedding)
    -- convert the resultset into JSONB
    SELECT JSONB_AGG(t) INTO v_similar_fruit FROM (
        -- find the top matching fruit
        SELECT f.id, f.name, f.description,
            e.embedding_vector <=> q.target_embedding as likeness
        FROM fruit f
        JOIN embedding e ON f.id = e.fruit_id
        JOIN q ON TRUE
        ORDER BY likeness ASC
        LIMIT p_limit) t;
    -- return from the function
    RETURN v_similar_fruit;
END;
$$;

/*

Call Tree:
api.sf_retrieve_similar_fruit (p_target TEXT, p_limit INT) 
    -> api.mistral_embed(input_text) -- for the target text, calculated once in the common table expression (CTE) and reused for all comparisons 
    -> SQL query to calculate the likeness scores and return the top matching fruits as a JSONB array
*/        

/* 
Test the retriever function - this will return a JSONB array with the most similar fruits based on the target text, 
along with their descriptions and likeness scores, and will print an error if the API key is not set or if there is an issue with the API call
Run this in psql to take advantage of the \x auto formatting for JSONB, which will make it easier to read the results

SELECT JSONB_PRETTY(api.sf_retrieve_similar_fruit ('Select tart and light yellow fruits for me'));

*/