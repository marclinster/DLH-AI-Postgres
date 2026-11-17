

/*


This should be run inside the database sportscars, which is created in the master_setup.sql script. 
The master_setup.sql script also sets the MISTRAL_API_KEY environment variable, which is required for generating the embeddings using the Mistral API.


This is part of the DLH Training Class for AI and Postgres, and is meant for educational purposes to 
demonstrate how to set up a database schema for vector embeddings and how to integrate with an 
external API for generating those embeddings.

This is the list of exercises in this file:
    1) Create the function api.generate_embedding_text that takes a configuration ID and generates a detailed description text for 
    that configuration by combining the brand name, model name, country of origin, price, description, and color from the vw_sportscars view. 
    This text will be used as input for generating the embedding vector.
    2) Create the function api.mistral_embed that takes an input text and calls the Mistral API to generate an embedding vector based on that 
    text. This function will handle the API call and return the embedding vector as a Postgres vector type.
    3) Create the function api.sportscar_embedding that takes a configuration ID, generates the description text using 
    api.generate_embedding_text, and then calls api.mistral_embed to get the embedding vector for that configuration.
    4) Create the function api.batch_sportscar_embedding that generates embedding vectors for all configurations in the database 
    by iterating over all configuration IDs in batches of five, calling api.sportscar_embedding for each, and storing 
    the results in the column configuration.embedding.
    5) Create the trigger sportscar_embedding_trigger that automatically generates the embedding vector for a configuration 
    whenever a new configuration is inserted or an existing one is updated, by calling api.sportscar_embedding with the appropriate configuration ID. 
    6) Create the retriever function api.sf_retrieve_similar_car that takes a user question, generates an embedding for 
    that question using api.mistral_embed, and retrieves the top 3 most similar cars from the database based on the embedding 
    similarity search, with an additional condition to filter the cars based on a price range provided as input
    7) Create the narrator function api.sf_narrate_selected_cars that takes the user question, the similar cars retrieved 
    in JSON format, and the price range bounds, and generates a detailed description for the user based on the similar 
    cars retrieved, including comments on how the price of the sportscars compares to the user's expectations based on their question.
    8) Create the coordinator function api.sf_coordinator that takes the user question and price range, calls the 
    retriever to get the similar cars, and then calls the narrator to generate a detailed description for the user.


Make sure to test each function after you create it by running the provided test queries, and check the results to ensure that everything is working correctly.
Last Update: 2026-05-05




*/

-- we will generate all the code in the api schema, just like the fruits example
CREATE SCHEMA IF NOT EXISTS api;

CREATE OR REPLACE FUNCTION api.generate_embedding_text(id INTEGER
) RETURNS TEXT AS $$
DECLARE 
    v_brand_name TEXT;
    v_model_name TEXT;
    v_country_of_origin TEXT;
    v_price NUMERIC;
    v_model_description TEXT;
    v_color_name TEXT;
BEGIN
    SELECT 
        brand_name,
        model_name,
        country_of_origin,
        price,
        model_description,
        color_name
    INTO v_brand_name, v_model_name, v_country_of_origin, v_price, v_model_description, v_color_name
    FROM vw_sportscars vw_sc
    WHERE configuration_id = id;
    RETURN format(
        'The %s %s is a sports car from %s, with a price of %s. It is built in %s and is available in %s. Description: %s',
        v_brand_name,
        v_model_name,
        v_country_of_origin,
        v_price,
        v_country_of_origin,
        v_color_name,
        v_model_description
    );
END;
$$ LANGUAGE plpgsql;

/*
Test function to see if it generates the correct description text for a given configuration ID. You can run the following query to test it:
SELECT api.generate_embedding_text(66);
*/

-- Now we will create the function to call the Mistral API and generate the embedding vector based on a text
-- this is identical to the one we created in the fruits example, 

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

CREATE OR REPLACE FUNCTION api.sportscar_embedding (config_id INTEGER)
RETURNS vector
LANGUAGE plpgsql
AS $$
DECLARE
    description_text TEXT;
    embedding_vector vector;
BEGIN
    -- Generate the description text for the given configuration ID
    description_text := api.generate_embedding_text(config_id);
    -- Generate the embedding vector by calling the Mistral API with the description text
    embedding_vector := api.mistral_embed(description_text);
    RETURN embedding_vector;
END;
$$;

/*
Test function to see if it generates the correct description text for a given configuration ID. You can run the following query to test it:
SELECT api.sportscar_embedding(1); -- test the function with a sample configuration ID
*/


DROP FUNCTION IF EXISTS api.batch_sportscar_embedding(p_batch_size INTEGER);

CREATE OR REPLACE FUNCTION api.batch_sportscar_embedding (p_batch_size INTEGER DEFAULT 5)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_config RECORD;
    v_embedding_vector vector;
    v_ctr INTEGER := 0;
BEGIN
    -- this creates the embedding vector for all configurations in the database by iterating over all configuration IDs, calling api.sportscar_embedding for each, and storing the results in the embedding table
    FOR v_config IN SELECT id FROM configuration
        WHERE NOT EXISTS 
            (SELECT 1 FROM embedding WHERE configuration_id = configuration.id) -- only generate embeddings for configurations that don't have an embedding yet
        LIMIT p_batch_size
     LOOP
        v_embedding_vector := api.sportscar_embedding(v_config.id);
        INSERT INTO embedding (configuration_id, embedding_vector)
        VALUES (v_config.id, v_embedding_vector)
        ON CONFLICT (configuration_id) DO UPDATE SET embedding_vector = EXCLUDED.embedding_vector;
        v_ctr := v_ctr + 1;
    END LOOP;
    RAISE NOTICE 'Generated embeddings for % configurations', v_ctr;
    RETURN v_ctr;
END;
$$;

/*
Test function to generate embeddings for all configurations in the database. You can run the following query to test it:

SELECT * FROM api.batch_sportscar_embedding(); -- run the batch embedding generation until it returns 0, which means all embeddings have been generated
TRUNCATE TABLE embedding; -- truncate the embedding table to reset it for testing

*/


-- create a DO loop to call the batch embedding function until it returns 0, which means all embeddings have been generated
DO $$
DECLARE
    v_rows INTEGER;
BEGIN
    LOOP
        v_rows := api.batch_sportscar_embedding(5);
        EXIT WHEN v_rows = 0;
    END LOOP;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION api.sportscar_embedding_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE 
    v_embedding_vector vector;
BEGIN
    -- This trigger will automatically generate the embedding vector for a configuration whenever 
    -- a new configuration is inserted or an existing one is updated, by calling api.sportscar_embedding 
    -- with the appropriate configuration ID.  
    v_embedding_vector := api.sportscar_embedding(NEW.id);
    PERFORM pg_sleep(1); -- add a small delay to avoid hitting API rate limits in case of bulk inserts/updates
    INSERT INTO embedding (configuration_id, embedding_vector)
        VALUES (NEW.id, v_embedding_vector)
        ON CONFLICT (configuration_id) DO UPDATE SET embedding_vector = EXCLUDED.embedding_vector;
    RETURN NEW;
END;
$$;

-- Create the trigger that calls the embedding function after insert or update on the configuration table
DROP TRIGGER IF EXISTS sportscar_embedding_trigger ON configuration;

CREATE TRIGGER sportscar_embedding_trigger
AFTER INSERT OR UPDATE ON configuration
FOR EACH ROW
EXECUTE FUNCTION api.sportscar_embedding_trigger();

/* Test the trigger by inserting a new configuration and checking if the embedding is generated automatically. You can run the following queries to test it:
-- Adding the Golf R model and configuration

DELETE FROM configuration WHERE model_id = 25; -- clean up any existing configurations beyond the initial 69
INSERT INTO configuration (model_id, color_id) VALUES
    (25, 6), (25, 10), (25, 5);-- Golf R: Blue, Gray, White

*/


/* Test the embedding generation by running a query that selects a car and calculates the similarity to a target embedding generated from a text description. 
   You can run the following query to test it:

WITH q AS
    (SELECT api.mistral_embed ('A low cost sports car from germany')::vector AS target_embedding)
SELECT vw_sc.configuration_id, vw_sc.brand_name, vw_sc.model_name, vw_sc.country_of_origin, vw_sc.price, vw_sc.model_description, vw_sc.color_name,
       e.embedding_vector::vector <=> q.target_embedding::vector as likeness
FROM embedding e
JOIN q ON true
JOIN vw_sportscars vw_sc ON e.configuration_id = vw_sc.configuration_id
ORDER BY likeness ASC;

*/

/* 
Chat Bot
* Retrieve the top 3 most similar cars based on a user query using the embedding similarity search as shown above.
* Narrator: "Based on your description, here are the top 3 cars that match your preferences:"
    For each of the top 3 cars, generate a detailed description using the data from the vw_sportscars view and the embedding text generation function. 
* Coordinator: "If you want to know more about any of these cars, just ask!"
*/

-- The Retriever
-- this returns entries from the fruit table that match the query text, and the strength of the match
DROP FUNCTION IF EXISTS api.sf_retrieve_similar_car(p_target TEXT, p_limit INT) ;

CREATE FUNCTION api.sf_retrieve_similar_car (p_target TEXT, p_limit INT DEFAULT 2) 
RETURNS JSONB
LANGUAGE PLPGSQL
AS
$$
DECLARE 
    v_similar_cars JSONB;
BEGIN
    WITH q AS
        -- generate the target embedding in the common expression
        (SELECT api.mistral_embed (p_target)::vector AS target_embedding)
    -- convert the resultset into JSONB
    SELECT JSONB_AGG(t) INTO v_similar_cars FROM (
        -- find the top matching cars by comparing the target embedding with the embeddings in the database, and calculate the likeness score
        SELECT vw_sc.configuration_id, vw_sc.brand_name, vw_sc.model_name, vw_sc.country_of_origin, vw_sc.price, vw_sc.model_description, vw_sc.color_name,
            e.embedding_vector::vector <=> q.target_embedding::vector as likeness
        FROM embedding e
        JOIN q ON true
        JOIN vw_sportscars vw_sc ON e.configuration_id = vw_sc.configuration_id
        ORDER BY likeness ASC
        LIMIT p_limit) t;
    -- return from the function
    RETURN v_similar_cars;
END;
$$;

/* Test the retriever function by providing a sample query and checking the results. You can run the following query to test it:
SELECT api.sf_retrieve_similar_car('A red sports car from Italy with a powerful engine', 3) AS similar_cars;
*/

-- The Narrator
-- this function takes the output from the retriever and generates a detailed description for each of the similar cars using the generate_embedding_text function
DROP FUNCTION IF EXISTS api.sf_narrate_selected_cars (p_target TEXT, p_selected_cars JSONB) ;

CREATE FUNCTION api.sf_narrate_selected_cars (p_question TEXT, p_selected_cars JSONB) 
RETURNS TEXT
LANGUAGE plpython3u
AS $$
import os, json, ssl, urllib.error, urllib.request
# retrieve the API key 
api_key = os.environ.get('MISTRAL_API_KEY')
# check if the API key is set, if not, raise an exception to alert the user to set the API key before trying to call the Mistral API
if not api_key:
   raise Exception("Mistral API key not set. Please set the MISTRAL_API_KEY environment variable.")
# Mistral endpoint for chat completions
url = "https://api.mistral.ai/v1/chat/completions"
# HTTP headers (auth + JSON)
headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
# convert Postgres JSONB into Python json
v_rows = json.dumps(p_selected_cars)
# create the AI prompt
v_system_prompt = (
    "You are a helpful assistant.\n"
    "Take the user question and the SQL rows returned, and write a clear, "
    "human reply.\n"
    "- Mention the question.\n"
    "- Summarize how many results were found.\n"
    "- List items with their name and description\n"
    "- If possible, group items by brand and country of origin\n"
    "- Comment on the likeness of the results to the question, based on the likeness score, and mention the most similar one\n"
    "- Describe the ordering and what the likeness, calculated as cosine distance, means in terms of similarity to the user question.\n"
    "- Do not invent anything beyond the rows in JSON.\n"
    "- Write in a friendly and engaging tone, as if you were recommending cars to a friend based on their preferences.\n"
    "- Format the response in in plain text, no formatting.\n"
)
v_user_prompt = f"Question: {p_question}\n\nRows: {v_rows}"

# JSON payload (model + input text)
payload = { "model": "mistral-large-2512", 
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
-- Test the narrator function by providing a sample question and a set of similar cars in JSON format. You can run the following query to test it:
SELECT api.sf_narrate_selected_cars(
    'What are the best options for a red sports car from Italy with a powerful engine?',
    (SELECT api.sf_retrieve_similar_car('A red sports car from Italy with a powerful engine', 3))
) AS narration;

*/

-- The Coordinator
-- this function will take the user question, call the retriever to get the similar cars, and then call the narrator to generate a detailed description for the user
DROP FUNCTION IF EXISTS api.sf_coordinator(p_user_question TEXT) ;
CREATE FUNCTION api.sf_coordinator(p_user_question TEXT) 
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_similar_cars JSONB;
    v_narration TEXT;
BEGIN
    -- Call the retriever to get similar cars based on the user question
    v_similar_cars := api.sf_retrieve_similar_car(p_user_question, 3);
    -- Call the narrator to generate a detailed description for the user based on the similar cars retrieved
    v_narration := api.sf_narrate_selected_cars(p_user_question, v_similar_cars);
    RETURN v_narration;
END;
$$;

/*
-- Test the coordinator function by providing a sample user question. You can run the following query to test it:
SELECT api.sf_coordinator('I am looking for a red sports car from Italy with a powerful engine. What are my best options?') AS coordinator_response;

-- once you add the Golf R configurations, you can test the coordinator function with a question about a white sports car from Germany, which should return the Golf R as one of the top options. You can run the following query to test it:
SELECT api.sf_coordinator('I am looking for a white sports car from Germany or the UK with a sleek design and good performance. What are my best options?') AS coordinator_response;
*/