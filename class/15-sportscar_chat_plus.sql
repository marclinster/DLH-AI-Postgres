/***************************************************************************************************

Part of the DLH Training Class for AI and Postgres, and is meant for educational purposes to 
demonstrate how to integrate with an external API for generating those embeddings.

This extends the sportscar chatbot exercise by adding a SQL condition for the price of the sportscar, and 
then we will test the chatbot with a query that includes the price condition.
The price condition is added to the WHERE clause of the query that retrieves the sportscar configurations, 
and it filters the results to only include sportscars that are below a certain price threshold.
In this example, we will set the price threshold to $100,000, which means that the chatbot will only return 
sportscar configurations that are priced below $100,000.

The prce condition will be an upper and lower bound, for example we will set the price threshold 
to a range of $50,000 to $100,000, which means that the chatbot will only return sportscar configurations 
that are priced between $50,000 and $100,000.

Copyright 2026: Marc Linster
Last Update: 2026-11-17

***************************************************************************************************/



CREATE SCHEMA IF NOT EXISTS api;

-- a simple example that shows how to add a price condition to the basic selection query

-- query without a price condition:

WITH q AS
    (SELECT api.mistral_embed('A red sports car from Italy with a powerful engine') AS target)
SELECT vw_sc.configuration_id, vw_sc.brand_name, vw_sc.model_name, vw_sc.country_of_origin,
       vw_sc.price, vw_sc.color_name,
       e.embedding_vector <=> q.target as likeness
FROM embedding e
JOIN q ON true
JOIN vw_sportscars vw_sc ON e.configuration_id = vw_sc.configuration_id
ORDER BY likeness ASC
LIMIT 3;

-- query with a price condition:

WITH q AS (
    SELECT api.mistral_embed('A red sports car from Italy with a powerful engine') AS target
)
SELECT vw_sc.configuration_id, vw_sc.brand_name, vw_sc.model_name, vw_sc.country_of_origin, 
       vw_sc.price, vw_sc.color_name,
       e.embedding_vector <=> q.target as likeness
FROM embedding e
JOIN q ON true
JOIN vw_sportscars vw_sc ON e.configuration_id = vw_sc.configuration_id
WHERE vw_sc.price < 100000 -- this is the price condition that filters the sportscar configurations based on their price, only returning those that are priced below $100,000.
ORDER BY likeness ASC
LIMIT 3;


/* 
This is the updated chatbot that includes a price condition in the query to filter sportscar configurations based on their price, 
and the updated retriever function that includes a price condition in the query to filter sportscar configurations based on their price, 
and the updated narrator function that includes the price information in the generated response, and comments on how the price of the 
sportscars compares to the user's expectations based on their question.

*/


-- Updated retriever function that includes a price condition in the query to filter sportscar configurations based on their price.
DROP FUNCTION IF EXISTS api.sf_retrieve_similar_car(p_user_question TEXT, p_limit INT, p_price_range NUMRANGE);

CREATE FUNCTION api.sf_retrieve_similar_car (p_target TEXT, p_limit INT DEFAULT 2, p_price_range NUMRANGE DEFAULT '[0,10000000]') 
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
        WHERE vw_sc.price <@ p_price_range -- filter the sportscars based on the price range condition
        ORDER BY likeness ASC
        LIMIT p_limit) t;
    -- return from the function
    RETURN v_similar_cars;
END;
$$;

/* 

Test the retriever function with a query that includes the price condition, for example, to find similar cars that are priced between $50,000 and $100,000: 

SELECT api.sf_retrieve_similar_car('A red sports car from Italy with a powerful engine', 3, '[50000,100000]') AS similar_cars;

*/

-- Enhance the narrator function to include the price information in the generated response, and to comment on how the price of the sportscars 
-- compares to the user's expectations based on their question.

DROP FUNCTION IF EXISTS api.sf_narrate_selected_cars (p_target TEXT, p_selected_cars JSONB, p_price_lower_bound NUMERIC, p_price_upper_bound NUMERIC);

CREATE FUNCTION api.sf_narrate_selected_cars (p_question TEXT, p_selected_cars JSONB, p_price_lower_bound NUMERIC, p_price_upper_bound NUMERIC)
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
    "- Describe how the cars fit the expected price range: " + str(p_price_lower_bound) + "-" + str(p_price_upper_bound) + "\n"
    "- Summarize how many results were found.\n"
    "- List items with their name, description, and price\n"
    "- Order the items by likeness, and mention the likeness score for each item\n"
    "- Comment on the likeness of the results to the question, based on the likeness score, and mention the most similar one\n"
    "- Describe the ordering and what the likeness, calculated as Euclidean distance, means"
    "- Do not invent anything beyond the rows in JSON.\n"
    "- Write in a friendly and engaging tone, as if you were recommending cars to a friend based on their preferences.\n"
    "- Limit the output to 40 lines.\n"
    "- Format the response as plain text, without any markdown or HTML."
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


DROP FUNCTION IF EXISTS api.sf_coordinator(p_user_question TEXT, p_price_range NUMRANGE) ;

CREATE FUNCTION api.sf_coordinator(p_user_question TEXT, p_price_range NUMRANGE) 
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_similar_cars JSONB;
    v_narration TEXT;
    v_lower_bound NUMERIC := LOWER(p_price_range);
    v_upper_bound NUMERIC := UPPER(p_price_range);
BEGIN
    -- Call the retriever to get similar cars based on the user question
    v_similar_cars := api.sf_retrieve_similar_car(p_user_question, 3, p_price_range);
    -- Call the narrator to generate a detailed description for the user based on the similar cars retrieved
    v_narration := api.sf_narrate_selected_cars(p_user_question, v_similar_cars, v_lower_bound, v_upper_bound);
    RETURN v_narration;
END;
$$;

/*
Test the coordinator function with a query that includes the price condition, for example, to find similar cars that are priced between $50,000 and $100,000:

SELECT api.sf_coordinator('I am looking for a red sports car from Italy or Germany that is fun to drive. What are my best options?', '[50000, 100000]');

SELECT api.sf_coordinator('I am looking for a white sports car from Germany or the UK with a sleek design and good performance. What are my best options?', '[30000, 100000]');

*/
