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
        SELECT name, description, embedding_vector<=> q.target_embedding as likeness
            FROM fruit_with_embedding_vw
            JOIN q ON TRUE
            ORDER BY likeness ASC
            LIMIT p_limit) AS matching_fruit;
   -- return from the function
   RETURN v_similar_fruit;
END;
$$;

SELECT JSONB_PRETTY(api.sf_retrieve_similar_fruit('Select tart and light yellow fruits for me', 2));


-- Defining the narrator function that will be used to generate a natural language response based on the retrieved similar fruits.
CREATE or REPLACE FUNCTION api.sf_narrate_selected_fruit (p_question TEXT, p_selected_fruit JSONB)
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
v_rows = json.dumps(p_selected_fruit)
# create the AI prompt
v_system_prompt = (
    "You are a helpful assistant. Take the user question and the SQL rows returned, and write a clear, human reply.\n"
    "Mention the question, summarize the results, and explain the likeness scores.\n"
    "List items with their name and description\n"
    "Describe the ordering and what the likeness, calculated as Euclidean distance, means.\n"
    "Do not invent anything that is not mentioned in the user prompt.\n"
    "Do not add markdown formatting, just write plain text.\n"
)
v_user_prompt = f"Question: {p_question}\n\nRows: {v_rows}"
# JSON payload (model + input text)
# pinned to a specific version: mistral-large-latest (Large 4) returns content as a list of thinking/text chunks
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
use 
\pset columns 120 
\pset format wrapped
to see the full output of the narration in psql
*/

SELECT api.sf_narrate_selected_fruit (
    'Select tart and light yellow fruits for me',
    '[{"id": 4, "name": "Lemon", "likeness": 0.20149098421582978, "description": "Very tart, yellow, firm"}, 
     {"id": 11, "name": "White Grape", "likeness": 0.21226197326502327, "description": "A little tart, light yellow, medium firm"}]'
);

-- Defining the coordinator function that will be used to coordinate the retrieval and narration functions, taking a user question as input and returning a natural language response.
CREATE OR REPLACE FUNCTION api.coordinator_fruit_selection (p_target TEXT) RETURNS TEXT
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


SELECT api.coordinator_fruit_selection ('Select tart and light yellow fruits for me');

SELECT api.coordinator_fruit_selection ('I want a starchy and sweet fruit');
