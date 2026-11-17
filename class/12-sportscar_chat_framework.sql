/***************************************************************************************************

Part of the DLH Training Class for AI and Postgres, and is meant for educational purposes to 
demonstrate how to integrate with an external API for generating those embeddings.


This has the high-level framework for the sportscar chat bot exercise, which is meant to demonstrate how to set up a 
database schema for vector embeddings and how to integrate with an external API for generating those embeddings, 
as well as how to implement a simple retriever-narrator-coordinator architecture for a chatbot that can answer 
questions about sports cars based on the data in the database and the embeddings generated from that data.

Instructions:
1) Set this up in the schema called API inside the sportscars database, which is created in the master_setup.sql script.
2) Use the template below and fill in the functiona dn procedure bodiesby looking at the code in the fruit_store examples, 
   which contains similar functionality but for a fruit store example.
3) The code will include:
   a) A function to generate the complete description text for a given car configuration, which will combine the brand name, model name, country of origin, price, description, and color into a single text string that can be used for embedding generation.
   b) A function to call the Mistral API and generate the embedding vector based on a given text input.
   c) A function to generate the embedding vector for a given car configuration ID by first generating the description text and then calling the Mistral API to get the embedding vector.
   d) A function to generate embedding vectors for all car configurations in the database by iterating over all configuration IDs, calling the embedding generation function for each, and storing the results in the embedding table.
   e) A trigger that automatically generates the embedding vector for a car configuration whenever a new configuration is inserted or an existing one is updated, by calling the appropriate embedding generation function with the configuration ID.
   f) Retriever, Narrator, and Coordinator functions to implement the full chatbot functionality, allowing users to ask questions about the cars and receive detailed responses based on the data in the database and the embeddings generated from that data.  

Copyright 2026: Marc Linster
Last Update: 2026-11-17

***************************************************************************************************/



-- we will generate all the code in the api schema, just like the fruits example
CREATE SCHEMA IF NOT EXISTS api;

CREATE OR REPLACE FUNCTION api.generate_embedding_text(id INTEGER
) RETURNS TEXT AS $$
-- fill this in by looking at the fruit_store example, which contains a similar function for generating the description text for a given fruit ID. This function should generate a text description for a given car configuration ID by combining the relevant data from the vw_sportscars view, such as brand name, model name, country of origin, price, model description, and color, into a single text string that can be used for embedding generation.
$$ LANGUAGE plpgsql;

/*
Test function to see if it generates the correct description text for a given configuration ID. You can run the following query to test it:
SELECT api.generate_embedding_text(66);
*/



CREATE OR REPLACE FUNCTION api.mistral_embed (input_text text)
RETURNS vector
LANGUAGE plpython3u
AS $$
-- fill this in by looking at the fruit_store example, which contains a similar function for calling the Mistral API to generate embeddings based on a text input.
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
-- fill this in by looking at the fruit_store example, which contains a similar function for generating embeddings in batches. This function should generate embedding vectors for all car configurations in the database by iterating over all configuration IDs that do not yet have an embedding, calling the embedding generation function for each, and storing the results in the embedding table. The function should return the number of embeddings that were generated in each batch, and return 0 when all embeddings have been generated.
END;
$$;

/*
Test function to generate embeddings for all configurations in the database. You can run the following query to test it:

SELECT * FROM api.batch_sportscar_embedding(); -- run the batch embedding generation until it returns 0, which means all embeddings have been generated
TRUNCATE TABLE embedding; -- truncate the embedding table to reset it for testing

*/


CREATE OR REPLACE FUNCTION api.sportscar_embedding_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE 
    v_embedding_vector vector;
BEGIN
-- fill this in by looking at the fruit_store example, which contains a similar trigger function for automatically 
-- generating embeddings when new fruit data is inserted or updated. This trigger function should automatically generate the embedding vector for a car configuration whenever a new configuration is inserted or an existing one is updated, by calling the appropriate embedding generation function with the configuration ID and storing the result in the embedding table.
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
INSERT INTO configuration (model_id, color_id) VALUES
    (25, 6), (25, 10), (25, 5);-- Golf R: Blue, Gray, White

*/


/* Test the embedding generation by running a query that selects a car and calculates the similarity to a target embedding generated from a text description. 
   You can run the following query to test it:

WITH q AS
    (SELECT api.mistral_embed ('A white supercar from Germany or the UK')::vector AS target_embedding)
SELECT vw_sc.configuration_id, vw_sc.brand_name, vw_sc.model_name, vw_sc.country_of_origin, vw_sc.price, vw_sc.model_description, vw_sc.color_name,
       e.embedding_vector::vector <=> q.target_embedding::vector as likeness
FROM embedding e
JOIN q ON true
JOIN vw_sportscars vw_sc ON e.configuration_id = vw_sc.configuration_id
ORDER BY likeness ASC;

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
-- fill this in by looking at the fruit_store example, which contains a similar function for
-- retrieving similar fruits based on a target text query. This function should take a user query as input, generate an 
-- embedding for that query using the Mistral API, and then perform a similarity search against the embeddings of the car 
-- configurations in the database to find the top N most similar cars. The results should be returned in JSONB format, including relevant details about each car and the similarity score.
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
import json, ssl, urllib.error, urllib.request
-- fill this in by looking at the fruit_store example, which contains a similar function for generating a 
-- narration based on the selected fruits. This function should take the user question and the JSONB output from the retriever function as input, and then generate a detailed text description for each of the similar cars using the generate_embedding_text function to get the relevant details about each car. The function should then combine these descriptions into a single response that can be returned to the user.
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
-- fill this in by looking at the fruit_store example, which contains a similar function for coordinating the retriever and 
-- narrator functions. This function should take the user question as input, call the retriever function to get the similar cars, and then call the narrator function to generate a detailed description for the user based on the retrieved cars. The final response should be returned as text.
$$;

/*
-- Test the coordinator function by providing a sample user question. You can run the following query to test it:
SELECT api.sf_coordinator('I am looking for a red sports car from Italy with a powerful engine. What are my best options?') AS coordinator_response;

-- once you add the Golf R configurations, you can test the coordinator function with a question about a white sports car from Germany, which should return the Golf R as one of the top options. You can run the following query to test it:
SELECT api.sf_coordinator('I am looking for a white sports car from Germany or the UK with a sleek design and good performance. What are my best options?') AS coordinator_response;
*/