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
import os, json, ssl, urllib.request, urllib.error, plpy
# retrieve the API key from the environment variable
api_key = os.environ.get('MISTRAL_API_KEY')
# HTTP headers (auth + JSON)
headers = {
    "Authorization": f"Bearer {api_key}",
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
    plpy.notice("Embedding generated for: %s" % input_text)
    plpy.notice("LLM response: %s" % json.dumps(resp_data))
    embedding = resp_data["data"][0]["embedding"]
    return embedding
$$;

/* 
Test the simple embedding function.
This will return a 6-dimensional embedding vector from the Codestral model

SELECT 'Codestral embed with 6 dimensions returned:' || api.mistral_embed_simple ('test text')::TEXT;
*/

-- This version of the function with the real model and basic error handling

DROP FUNCTION IF EXISTS api.mistral_embed;

CREATE OR REPLACE FUNCTION api.mistral_embed (input_text text)
RETURNS vector
LANGUAGE plpython3u
AS $$
import os, json, ssl, urllib.request, urllib.error, plpy
# retrieve the API key from the environment variable
api_key = os.environ.get('MISTRAL_API_KEY')
# check if the API key is set, if not, raise an exception to alert the user to set the API key before trying to call the Mistral API
if not api_key:
    raise Exception("Mistral API key not set. Please set the MISTRAL_API_KEY environment variable.")
# Mistral endpoint for embeddings
url = "https://api.mistral.ai/v1/embeddings"
# HTTP headers (auth + JSON)
headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"
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

SELECT api.mistral_embed ('I like strawberies');

SELECT FORMAT('Mistral embed returned an array of %s dimensions', VECTOR_DIMS(api.mistral_embed ('I like strawberies')));

*/

-- The function  api.generate_embedding_text assembles the text that will be sent to the Mistral API for 
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
Test the text generation function - this should return a string that combines the fruit name and description
SELECT id, name, api.generate_embedding_text(id) AS embedding_text
    FROM fruit LIMIT 5;
*/


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