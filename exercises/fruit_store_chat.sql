/* 

This file contains the SQL code to set up the functions and triggers for the fruit store chat bot example, 
which demonstrates how to use the Mistral API to generate embeddings and create a simple retriever + narrator chatbot in Postgres.

Building blocks:
- api.mistral_embed: function to call the Mistral API and generate embeddings for a given input text, 
  with error handling for missing API key and API call issues
- api.generate_embedding_text: function to create the text that will be sent to the Mistral API for 
  embedding generation, by combining the fruit name and description into a single string
- api.fruit_embedding: function that combines the previous two functions to generate an embedding for a given fruit ID, 
  by first generating the text and then calling the embedding function  
- api.batch_fruit_embedding: function to generate embeddings for all fruits in the fruit table in batches, 
  which is more efficient than generating embeddings one by one, especially when you have a large number of fruits
- tr_fruit_embedding: trigger that automatically generates an embedding for a fruit whenever a new fruit is 
  inserted or an existing fruit is updated, by calling the api.mistral_embed function with the generated text from api.generate_embedding_text
- api.sf_retrieve_similar_fruit: a "retriever" function that takes a target text and returns the most similar fruits from 
  the database based on the embedding vectors, along with their descriptions and likeness scores
- api.sf_narrate_selected_fruit: a "narrator" function that takes the results from the retriever and 
  generates a natural language text response using the Mistral Chat API, which summarizes the results from the similarity search and explains the likeness scores.
- api.coordinator_fruit_selection: a "coordinator" function that serves as the main interface for the chatbot, coordinating the retrieval and narration functions.

*/



-- Holds all the API related functions, to keep them organized and separate from other database objects
CREATE SCHEMA IF NOT EXISTS api;

-- the function to generate embeddings using the MISTRAL codestral model with six dimensions
-- this has no error handling and is for illustrative purposes only - 
-- the next function is the one you should use in production, as it includes error handling and checks for the API key

DROP FUNCTION IF EXISTS api.mistral_embed_simple;

CREATE OR REPLACE FUNCTION api.mistral_embed_simple(input_text text)
RETURNS json
LANGUAGE plpython3u
AS $$
import json, ssl, urllib.request, urllib.error, plpy
# retrieve the API key from the database configuration
rv = plpy.execute("SELECT current_setting('api.mistral_api_key', true) AS apikey")
apikey = rv[0]["apikey"] 
# HTTP headers (auth + JSON)
headers = {
    "Authorization": f"Bearer {apikey}",
    "Content-Type": "application/json"
}
# JSON payload (model + input text)
payload = {
    "model": "codestral-embed",
    "output_dimension": 6,
    "input": input_text
}
# Create the request
req = urllib.request.Request(
    "https://api.mistral.ai/v1/embeddings",
    data=json.dumps(payload).encode("utf-8"),
    headers=headers,
    method="POST"
)
# create an SSL context to use for the request, which will ensure that the connection to the Mistral API is secure and encrypted
ctx = ssl.create_default_context() 
with urllib.request.urlopen(req, context=ctx, timeout=30) as resp:
    resp_data = json.load(resp)
    embedding = resp_data["data"][0]["embedding"]
    return embedding
$$;

/* 
Test the simple embedding function.
This will return a 6-dimensional embedding vector from the Codestral model, and will print an error if the API key is not set or if there is an issue with the API call 

SELECT 'Codestral embed with 6 dimensions returned:' || api.mistral_embed_simple ('test text')::TEXT;
*/

-- This version of the function with the real model and basic error handling

DROP FUNCTION IF EXISTS api.mistral_embed;

CREATE OR REPLACE FUNCTION api.mistral_embed (input_text text)
RETURNS vector
LANGUAGE plpython3u
AS $$
import json, ssl, urllib.request, urllib.error, plpy
# retrieve the API key from the database configuration
rv = plpy.execute("SELECT current_setting('api.mistral_api_key', true) AS apikey")
apikey = rv[0]["apikey"] 
# check if the API key is set, if not, raise an exception to alert the user to set the API key before trying to call the Mistral API
if not apikey:
    raise Exception("Mistral API key not set. Please set the MISTRAL_API_KEY environment variable.")
# Mistral endpoint for embeddings
url = "https://api.mistral.ai/v1/embeddings"
# HTTP headers (auth + JSON)
headers = {"Authorization": f"Bearer {apikey}", "Content-Type": "application/json"
}
# JSON payload (model + input text)
payload = { "model": "mistral-embed", "input": input_text
}
# Create the request
req = urllib.request.Request( url, data=json.dumps(payload).encode("utf-8"), headers=headers, method="POST"
)
# create an SSL context to use for the request, which will ensure that the connection to the Mistral API is secure and encrypted
ctx = ssl.create_default_context() 
try:
    with urllib.request.urlopen(req, context=ctx, timeout=30) as resp:
        resp_data = json.load(resp)
        embedding = resp_data["data"][0]["embedding"]
        # will help track embedding calls
        plpy.notice("Embedding generated for: %s" % input_text)
        return [float(x) for x in embedding]  # convert to float4 array
except urllib.error.HTTPError as e:
    body = e.read().decode("utf-8", errors="ignore")
    raise Exception(f"Mistral HTTP {e.code}. Body: {body[:400]} ...")
$$;

/* 
Test the embedding function with error handling 
This will return a 1024-dimensional embedding vector from the Mistral model, and will print an error if the API key is not set or if there is an issue with the API call

SELECT api.mistral_embed ('I like strawberies');

SELECT FORMAT('Mistral embed returned an array of %s dimensions', array_length(api.mistral_embed ('I like strawberies'),1));

*/

-- The function  assembles api.generate_embedding_text the text that will be sent to the Mistral API for 
-- embedding generation, by combining the fruit name and description into a single string, 

CREATE OR REPLACE FUNCTION api.generate_embedding_text(p_id INTEGER) RETURNS TEXT AS $$
DECLARE 
    v_name TEXT;
    v_description TEXT;
BEGIN
    SELECT 
        name, description INTO v_name, v_description
    FROM fruit
    WHERE id = p_id;
    RETURN FORMAT('%s has the properties %s', v_name, v_description);
END;
$$ LANGUAGE plpgsql;


/* 
The following function combines the previous two functions to generate an embedding for a given fruit ID, 
by first generating the text and then calling the embedding function.
*/

CREATE OR REPLACE FUNCTION api.fruit_embedding(p_id INTEGER) RETURNS vector AS $$
DECLARE 
    v_text TEXT;
BEGIN
    v_text := api.generate_embedding_text(p_id);
    RETURN api.mistral_embed(v_text);
END;
$$ LANGUAGE plpgsql;

/* 
Test the fruit embedding function - this should return the same embedding vector as calling the two functions separately
SELECT id, name, api.fruit_embedding(id) AS embedding
    FROM fruit LIMIT 5;
*/

/*

This query will generate embeddings for all fruits in the fruit table, store them in the embedding table
It may fail if you have a lot of fruits and hit rate limits, which is why we will create a batch processing 
function in the next step, but you can test it with a small number of fruits to see how it works

*/

INSERT INTO embedding (fruit_id, embedding_vector)
    SELECT id, api.fruit_embedding(id)
        FROM fruit
    ON CONFLICT (fruit_id) DO 
        UPDATE SET embedding_vector = EXCLUDED.embedding_vector; -- update the embedding if the fruit_id already exists in the embeddings table

-- see what happened
SELECT * FROM fruit f
 JOIN embedding e on f.id = e.fruit_id
 LIMIT 1;

-- run queries to find similar fruits based on the embedding vectors, and order them by likeness (Euclidean distance)

SELECT f.name, e.embedding_vector <=> api.mistral_embed ('Very sweet, yellow, and soft') AS likeness 
    FROM fruit f
    JOIN embedding e ON f.id = e.fruit_id
    ORDER BY likeness ASC;

SELECT f.name, e.embedding_vector <=> api.mistral_embed ('lots of carbohydrate')AS likeness 
    FROM fruit f
    JOIN embedding e ON f.id = e.fruit_id
    ORDER BY likeness ASC;    

SELECT f.name, e.embedding_vector <=> api.mistral_embed ('squishy') AS likeness 
    FROM fruit f
    JOIN embedding e ON f.id = e.fruit_id
    ORDER BY likeness ASC;        

SELECT f.name, e.embedding_vector <=> api.mistral_embed ('potato') AS likeness 
    FROM fruit f
    JOIN embedding e ON f.id = e.fruit_id
    ORDER BY likeness ASC;     
*/



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
        JOIN embedding e ON f.id = e.fruit_id
        WHERE e.embedding_vector IS NULL 
        LIMIT p_batch_size
    LOOP
        v_embedding_vector := api.fruit_embedding(v_record.id);
        INSERT INTO embedding (fruit_id, embedding_vector)
            SELECT id, v_embedding_vector
            FROM fruit WHERE id = v_record.id
        ON CONFLICT (fruit_id) DO 
            UPDATE SET embedding_vector = EXCLUDED.embedding_vector;
        -- increment the counter for the number of embeddings generated in this batch    
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

INSERT INTO fruit 
    (name, description) 
    VALUES ('Strawberry', 'Sweet, red, soft');

INSERT INTO fruit 
    (name, description) 
    VALUES ('White Grape', 'Tart, light yellow, medium firm');

UPDATE fruit 
    SET description = 'A little tart, light yellow, medium firm' 
    WHERE name = 'White Grape';

Call Tree:
INSERT INTO fruit (name, description)
    -> tr_fruit_embedding() [AFTER INSERT trigger]
    -> api.tr_fruit_embedding()
    -> api.fruit_embedding(p_id)
        -> api.generate_embedding_text(p_id)
        -> api.mistral_embed(input_text)

*/

/* 
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

DROP FUNCTION IF EXISTS api.sf_narrate_selected_fruit (p_target TEXT, p_selected_fruit JSONB) ;

CREATE FUNCTION api.sf_narrate_selected_fruit (p_question TEXT, p_selected_fruit JSONB) 
RETURNS TEXT
LANGUAGE plpython3u
AS $$
import json, ssl, urllib.error, urllib.request
# retrieve the API key from the database configuration
rv = plpy.execute("SELECT current_setting('api.mistral_api_key', true) AS apikey")
apikey = rv[0]["apikey"] 
# check if the API key is set, if not, raise an exception to alert the user to set the API key before trying to call the Mistral API
if not apikey:
    raise Exception("Mistral API key not set. Please set the MISTRAL_API_KEY environment variable.")
# Mistral endpoint for chat completions
url = "https://api.mistral.ai/v1/chat/completions"
# HTTP headers (auth + JSON)
headers = {"Authorization": f"Bearer {apikey}", "Content-Type": "application/json"}
# convert Postgres JSONB into Python json
v_rows = json.dumps(p_selected_fruit)
# create the AI prompt
v_system_prompt = (
    "You are a helpful assistant.\n"
    "Take the user question and the SQL rows returned, and write a clear, "
    "human reply.\n"
    "- Mention the question.\n"
    "- Summarize the results.\n"
    "- List items with their name and descrition\n"
    "- Describe the ordering and what the likeness, calculated as Euclidean distance, means"
    "- Do not invent anything beyond rows JSON.\n"
    "Schema tables/columns:\n"
    "- fruit_store.fruit(id, name, description, likeness) \n"
    "\n"
)
v_user_prompt = f"Question: {p_question}\n\nRows: {v_rows}"

# JSON payload (model + input text)
payload = { "model": "mistral-large-latest", 
            "messages": [
                {"role": "system", "content": v_system_prompt},
                {"role": "user", "content": v_user_prompt}]
}
# Create the request
req = urllib.request.Request( url, 
    data=json.dumps(payload).encode("utf-8"), 
    headers=headers, 
    method="POST"
)
# create an SSL context to use for the request, which will ensure that the connection to the Mistral API is secure and encrypted
ctx = ssl.create_default_context() 
try:
    with urllib.request.urlopen(req, context=ctx, timeout=30) as v_resp:
        v_raw = json.loads(v_resp.read().decode("utf-8", errors="replace"))
        v_narration = v_raw["choices"][0]["message"]["content"].strip()
        return v_narration
except urllib.error.HTTPError as e:
    body = e.read().decode("utf-8", errors="ignore")
    raise Exception(f"Mistral HTTP {e.code}. Body: {body[:400]} ...")
$$;


/* 
Call tree:
api.sf_narrate_selected_fruit (p_question TEXT, p_selected_fruit JSONB) 
    -> Mistral Chat API (external) - takes the user question and the JSONB array of selected fruits, and generates a natural language response that summarizes the results and explains the likeness

Test the narrator function - this should return a natural language text that summarizes the results from the similarity search, and 
will print an error if the API key is not set or if there is an issue with the API call
SELECT api.sf_narrate_selected_fruit (
    'Select tart and light yellow fruits for me',
    '[{"id": 4, "name": "Lemon", "likeness": 0.20149098421582978, "description": "Very tart, yellow, firm"}, 
     {"id": 11, "name": "White Grape", "likeness": 0.21226197326502327, "description": "A little tart, light yellow, medium firm"}]'
);
*/


DROP FUNCTION IF EXISTS api.coordinator_fruit_selection (p_target TEXT);

CREATE FUNCTION api.coordinator_fruit_selection (p_target TEXT) RETURNS TEXT
LANGUAGE PLPGSQL
AS
$$
DECLARE 
    v_max_responses INTEGER DEFAULT 2;
    v_jsonb_selected_fruit JSONB;
    v_narration TEXT;
BEGIN
    -- call the retriever
    v_jsonb_selected_fruit := api.sf_retrieve_similar_fruit (p_target, v_max_responses);
    -- call the narrator
    v_narration := api.sf_narrate_selected_fruit (p_target,v_jsonb_selected_fruit);
    RETURN v_narration;
END
$$;

/* Test the coordinator function 
This will return a natural language text that summarizes the 
results from the similarity search, and will print an error if the API key is not set or if there is an issue with the API call
SELECT api.coordinator_fruit_selection ('Select tart and light yellow fruits for me');

SELECT api.coordinator_fruit_selection ('I want a starchy and sweet fruit');

Call Tree:
api.coordinator_fruit_selection (p_target TEXT)
    -> api.sf_retrieve_similar_fruit(p_target, p_limit)  
            -> api.mistral_embed(input_text)
    -> api.sf_narrate_selected_fruit(p_question, p_selected_fruit)  
        -> Mistral Chat API (external)
*/
