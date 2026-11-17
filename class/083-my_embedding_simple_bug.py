# ****************************************************************************************************
# This is part of the DLH Training Class for AI and Postgres, and is meant for educational purposes to
# demonstrate how to use Python to call the Mistral API and generate embeddings for a simple text input.
#
# This example uses the codesral-embed model to generate a 6-dimensional embedding vector for the input text.
# It adds a bug (wrong environment variable name) to the previous example, so that if the API call fails, 
# it will trigger an unhandled error.
# 
# Copyright 2026: Marc Linster
# Last Update: 2026-11-17
# ************************************************************************************************




import json, ssl, time, random, os, urllib.request, urllib.error

# Your Mistral API key should be set as an environment variable
api_key = os.environ.get('MISTRAL_API_KEYX')

# The text you want to embed
input_text = "Here is the text I want to turn into an embedding."

# The endpoint and headers
url = "https://api.mistral.ai/v1/embeddings"
headers = {
    "Authorization": f"Bearer {api_key}",
    "Content-Type": "application/json"
}

# The data payload
data = {
    "model": "codestral-embed",
    "output_dimension":6,
    "input": input_text
}

# Make the request
request = urllib.request.Request(url, data=json.dumps(data).encode('utf-8'), headers=headers, method='POST')
resp = urllib.request.urlopen(request)
resp_data = json.load(resp)
print ("Response:", json.dumps(resp_data, indent=2))