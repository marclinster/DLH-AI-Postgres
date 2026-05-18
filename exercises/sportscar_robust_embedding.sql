/*
This will illustrate how to enhance the mebedding fuunction to handle errors and retry the mebedding generation



*/


-- This will likely cause a MISTRAL API error
-- Mistral HTTP 429. Body: {"object":"error","message":"Rate limit exceeded","type":"rate_limited","param":null,"code":"1300","raw_status_code":429} 

TRUNCATE embedding;
SELECT api.batch_sportscar_embedding(100);


-- We will rewrite the embedding generation function to include error handling and retry logic, so that it can handle API errors gracefully and continue processing the remaining sportscar configurations without failing completely when an error occurs.

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
attempts = 6
for i in range(attempts):
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=30) as resp:
            resp_data = json.load(resp)
            embedding = resp_data["data"][0]["embedding"]
            # will help track embedding calls
            plpy.notice("Embedding generated for: %s" % input_text)
            return [float(x) for x in embedding]  # convert to float4 array
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="ignore")
        if e.code in [429, 503]:  # rate limit or service unavailable
            wait_time = 2 ** i  # exponential backoff
            plpy.warning(f"Mistral API error {e.code}. Retrying in {wait_time} seconds. Body: {body[:400]} ...")
            plpy.execute(f"SELECT pg_sleep({wait_time})")  # sleep before retrying
        else:   
            raise Exception(f"Mistral HTTP {e.code}. Body: {body[:400]} ...")
$$;

SELECT * FROM api.mistral_embed('Test embedding with error handling and retry logic');