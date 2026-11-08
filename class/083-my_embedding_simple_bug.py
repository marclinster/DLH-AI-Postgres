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