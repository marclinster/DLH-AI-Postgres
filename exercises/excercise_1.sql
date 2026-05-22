





-- JSONB excercises
-- make sure you are connected to the database ecommerce

SELECT first_name, phone_numbers FROM customer LIMIT 5;

SELECT first_name, JSONB_PRETTY(phone_numbers) FROM customer LIMIT 5;

SELECT
	first_name,
	phone_numbers,
	phone_numbers ->> 'home' AS home_phone_number,
	phone_numbers ->> 'mobile' AS mobile_phone_number
FROM customer
LIMIT 5;

SELECT first_name, phone_numbers
    FROM customer
    WHERE phone_numbers ? 'mobile'
    LIMIT 5;

SELECT first_name, phone_numbers 
	FROM customer
	WHERE NOT(phone_numbers ? 'home')
	LIMIT 5;

-- simple ways to change and update JSONB data

SELECT  first_name, last_name, phone_numbers FROM customer
    WHERE first_name = 'Daisy' AND last_name = 'Hicks';

Adding to a JSON data element
UPDATE customer
		SET phone_numbers =
			jsonb_insert (phone_numbers, '{new}', '"123 456 789"')
    	WHERE first_name = 'Daisy' AND last_name = 'Hicks';

Removing a JSON data element
UPDATE customer 
		SET phone_numbers = 
			phone_numbers - 'new' 
	WHERE first_name = 'Daisy' AND last_name = 'Hicks'; 


-- simple excercises

    


-- converting JSONB to text the simple way

SELECT product_variant_id,
       product_label,
       'Attributes: ' || product_variant_attributes::text
FROM product_full_details
limit 5;


-- converting JSONB to text using jsonb_each_text to get key value pairs and 
-- string_agg to aggregate them into a single string with a custom format

SELECT first_name, last_name, phone_numbers,
       string_agg(key || ' number is ' || value, '; ') as phone_details
FROM
   customer
   LEFT JOIN
   -- this converts the JSONB attributes into key value pairs, 
jsonb_each_text (phone_numbers) ON TRUE
   WHERE first_name = 'Daisy'
   GROUP BY first_name,last_name, phone_numbers;


-- converting JSONB to text for product attributes
SELECT product_variant_id,
       product_label,
       string_agg(key || ' is ' || value, ', and ') AS attributes
FROM product_full_details
LEFT JOIN jsonb_each_text(product_variant_attributes) ON TRUE
GROUP BY product_variant_id,
         product_label;


-- The Fruit Store Example
-- Make sure you are connected to the database simple_fruit_store

SELECT * FROM fruit_vectors;

SELECT id,
       name,
       description,
       features <-> '[0.95,0.90,0.80]' AS euclidean_distance
FROM fruit_vectors
ORDER BY euclidean_distance ASC;


SELECT id,
       name,
       description,
       features <-> '[0.95,0.90,0.80]' AS euclidean_distance,
       features <#> '[0.95,0.90,0.80]' AS cosine_distance,
       features <=> '[0.95,0.90,0.80]' AS inner_product_distance
FROM fruit_vectors
ORDER BY euclidean_distance ASC;


/* 
    Using CURL to call the Mistral API to generate embeddings for a given input text, and specifying the model 
    and output dimension in the request body. The response will contain the generated embedding vector. 
    $MISTRAL_API_KEY is set as an environmental variable.

Connect to the container shell and run the following command to test the API call:    


-- this produces a 6 dimensional embedding vector for the input text "Embed this sentence." using the codestral-embed model,
-- and prints it immediately to the console
curl -X POST "https://api.mistral.ai/v1/embeddings" \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer ${MISTRAL_API_KEY}" \
     -d '{"model": "codestral-embed", "input": ["Embed this sentence."], "output_dimension":6}'

-- this does the same but saves the output to a file called embedding.json, which we can then parse using jq to 
-- extract the embedding vector and other details
curl -X POST "https://api.mistral.ai/v1/embeddings" \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer ${MISTRAL_API_KEY}" \
     -d '{"model": "codestral-embed", "input": ["Embed this sentence."], "output_dimension":6}' \
     -o embedding6.json     

-- using jq to parse the output JSON file and extract the embedding vector
jq '.' embedding6.json
jq '.id' embedding6.json
jq '.data[0]' embedding6.json
jq '.data[0].embedding' embedding6.json
jq '.data[0].embedding[1]' embedding6.json


curl -X POST "https://api.mistral.ai/v1/chat/completions" \
     -H 'Content-Type: application/json' \
     -H 'Accept: application/json' \
     -H "Authorization: Bearer $MISTRAL_API_KEY" \
     -d '{
    "model": "mistral-large-latest",
    "messages": [
     {
        "role": "user",
        "content": "You are a teacher at the Digital Learning Hub. Explain the CURL API in 200 characters."
      }
    ]
  }'


curl -X POST "https://api.mistral.ai/v1/chat/completions"      -H 'Content-Type: application/json'      -H 'Accept: application/json'      -H "Authorization: Bearer $MISTRAL_API_KEY"      -d '{
    "model": "mistral-large-latest",
    "messages": [
     {
        "role": "user",
        "content": "You are a Postgres DBA. Create a query that selects selects customers and their total purchases from a table with the following DDL. CREATE TABLE customers (id SERIAL PRIMARY KEY, name TEXT NOT NULL, purchase_value NUMERIC(10, 2)); "
      }
    ]
  }' -o query_response.json

jq '.choices[0].message.content' -r query_response.json

*/


-- Stored Procedures and Triggers

-- simple stored procedure that takes a category label and a percentage increase as input, and 
-- increases the price of all products in that category by the given percentage, while printing 
-- the old and new price for each updated product variant

CREATE OR REPLACE PROCEDURE increase_price (
IN p_category_label TEXT, 
IN p_percentage_increase NUMERIC)
LANGUAGE PLPGSQL
AS
$$
DECLARE
   v_poduct_record RECORD;
   v_old_price NUMERIC;
   v_new_price NUMERIC;
BEGIN
   -- get all relevant products and product variants
   FOR v_poduct_record IN SELECT * FROM product_full_details WHERE category_label = p_category_label
       LOOP
           UPDATE product_variant
           SET price = price * (1 + p_percentage_increase)
           WHERE id = v_poduct_record.product_variant_id
           RETURNING OLD.price, NEW.price INTO v_old_price, v_new_price;
           RAISE NOTICE 'Updated price for product variant % (%): old price %, new price is %',
               v_poduct_record.product_variant_id, v_poduct_record.product_label, v_old_price, v_new_price;
       END LOOP;
END;
$$;

CALL increase_price ('Pants', 0.05); 

CALL increase_price ('Panties', 0.05); 

-- modified procedure that checks if the category exists before trying to update the prices, and 
-- raises a notice if the category does not exist, otherwise it increases the price and returns the new price
CREATE OR REPLACE PROCEDURE increase_price (
IN p_category_label TEXT, 
IN p_percentage_increase NUMERIC)
LANGUAGE PLPGSQL
AS
$$
DECLARE
   v_poduct_record RECORD;
   v_old_price NUMERIC;
   v_new_price NUMERIC;
BEGIN
    -- if the category does not exist, raise an exception and exit the procedure
    IF NOT EXISTS (SELECT 1 FROM product_full_details WHERE category_label = p_category_label) THEN
        RAISE NOTICE 'Category with label % does not exist', p_category_label;
    ELSE
        -- get all relevant products and product variants
        FOR v_poduct_record IN SELECT * FROM product_full_details WHERE category_label = p_category_label
            LOOP
                UPDATE product_variant
                SET price = price * (1 + p_percentage_increase)
                WHERE id = v_poduct_record.product_variant_id
                RETURNING OLD.price, NEW.price INTO v_old_price, v_new_price;
                RAISE NOTICE 'Updated price for product variant % (%): old price %, new price is %',
                    v_poduct_record.product_variant_id, v_poduct_record.product_label, v_old_price, v_new_price;
            END LOOP;
    END IF;
END;
$$;

-- modified procedure that checks if the category exists before trying to update the prices, and 
-- raises a **exception** if the category does not exist, otherwise it increases the price and returns the new price
CREATE OR REPLACE PROCEDURE increase_price (
IN p_category_label TEXT, 
IN p_percentage_increase NUMERIC)
LANGUAGE PLPGSQL
AS
$$
DECLARE
   v_poduct_record RECORD;
   v_old_price NUMERIC;
   v_new_price NUMERIC;
BEGIN
    -- if the category does not exist, raise an exception and exit the procedure
    IF NOT EXISTS (SELECT 1 FROM product_full_details WHERE category_label = p_category_label) THEN
        RAISE EXCEPTION 'Category with label % does not exist', p_category_label;
    ELSE
        -- get all relevant products and product variants
        FOR v_poduct_record IN SELECT * FROM product_full_details WHERE category_label = p_category_label
            LOOP
                UPDATE product_variant
                SET price = price * (1 + p_percentage_increase)
                WHERE id = v_poduct_record.product_variant_id
                RETURNING OLD.price, NEW.price INTO v_old_price, v_new_price;
                RAISE NOTICE 'Updated price for product variant % (%): old price %, new price is %',
                    v_poduct_record.product_variant_id, v_poduct_record.product_label, v_old_price, v_new_price;
            END LOOP;
    END IF;
END;
$$;

-- PLPGSQL Error Handling

UPDATE product_variant SET price = -0.99 WHERE id = 1; -- will trigger a check constraint violation error 


DO $$
BEGIN
    -- this will fail as table constraint requires prices > 0, 
    -- but we are not catching the specific error, so it will just print the error message in the console
    UPDATE product_variant SET price = -0.99 WHERE id = 1;
    EXCEPTION WHEN OTHERS THEN   
        RAISE NOTICE 'Update failed';
END;
$$;

-- modified version that catches the specific check constraint violation error and prints the details of the error,
-- and also catches any other errors that might occur and prints a generic error message with the error details
DO $$
    DECLARE 
    v_MESSAGE_TEXT TEXT;
    v_CONSTRAINT_NAME TEXT; 
    v_TABLE_NAME TEXT;
BEGIN
    -- this will fail as table constraint requires prices > 0
    UPDATE product_variant SET price = -0.99 WHERE id = 1;
    EXCEPTION 
        WHEN check_violation THEN
            RAISE NOTICE 'Violated check constraint; Details below';
            GET STACKED DIAGNOSTICS 
                v_CONSTRAINT_NAME = CONSTRAINT_NAME,
                v_MESSAGE_TEXT = MESSAGE_TEXT,
                v_TABLE_NAME = TABLE_NAME;
            RAISE NOTICE 'CONSTRAINT_NAME %', v_CONSTRAINT_NAME;
            RAISE NOTICE 'MESSAGE_TEXT %',v_MESSAGE_TEXT;
            RAISE NOTICE 'TABLE_NAME %', v_TABLE_NAME;
        WHEN OTHERS THEN
            RAISE NOTICE 'An error occurred: %', SQLERRM;
END;
$$;

-- now uses the generic error handler to catch a different error that is not a check constraint violation, 
-- and prints the error details in the console

DO $$
    DECLARE 
    v_MESSAGE_TEXT TEXT;
    v_CONSTRAINT_NAME TEXT; 
    v_TABLE_NAME TEXT;
BEGIN
    -- this will fail as table requires prices to be numeric, but we are trying to set it to a text value, 
    -- so it will trigger a different error than the previous example, which we will catch with the OTHERS exception handler
    UPDATE product_variant SET price = 'axc' WHERE id = 1;
    EXCEPTION 
        WHEN check_violation THEN
            RAISE NOTICE 'Violated check constraint; Details below';
            GET STACKED DIAGNOSTICS 
                v_CONSTRAINT_NAME = CONSTRAINT_NAME,
                v_MESSAGE_TEXT = MESSAGE_TEXT,
                v_TABLE_NAME = TABLE_NAME;
            RAISE NOTICE 'CONSTRAINT_NAME %', v_CONSTRAINT_NAME;
            RAISE NOTICE 'MESSAGE_TEXT %',v_MESSAGE_TEXT;
            RAISE NOTICE 'TABLE_NAME %', v_TABLE_NAME;
        WHEN OTHERS THEN
            RAISE NOTICE 'An error occurred: %', SQLERRM;
END;
$$;

-- modified version of the increase_price procedure that checks if the price increase is more than 50%, and 
-- if so, it raises an exception and rolls back the transaction, otherwise it increases the price and returns 
-- the new price, and also includes error handling to catch any check constraint violations or other errors 
-- that might occur during the update process, and prints the error details in the console
CREATE OR REPLACE PROCEDURE increase_price_w_check (IN p_category_label TEXT, IN p_percentage_increase NUMERIC)
LANGUAGE PLPGSQL
AS
$$
DECLARE
   v_poduct_record RECORD; v_old_price NUMERIC; v_new_price NUMERIC;
   -- will hold error details in case of exception
   v_MESSAGE_TEXT TEXT; v_CONSTRAINT_NAME TEXT; v_TABLE_NAME TEXT;
BEGIN
   IF p_percentage_increase > 0.5 THEN -- trigger an error if the price increase is more than 50%
       RAISE EXCEPTION 'Price increase of % is too high, aborting transaction', TO_CHAR (p_percentage_increase * 100, '999.0%');
   END IF;
   FOR v_poduct_record IN SELECT * FROM product_full_details WHERE category_label = p_category_label
       LOOP
           UPDATE product_variant
               SET price = price * (1 + p_percentage_increase)
               WHERE id = v_poduct_record.product_variant_id
               RETURNING OLD.price, NEW.price INTO v_old_price, v_new_price;
           RAISE NOTICE 'Updated price for product variant % (%): old price %, new price is %',
               v_poduct_record.product_variant_id, v_poduct_record.product_label, v_old_price, v_new_price;
       END LOOP;
   EXCEPTION
       WHEN check_violation THEN
           RAISE NOTICE 'Violated check constraint; Details below';
           GET STACKED DIAGNOSTICS
               v_CONSTRAINT_NAME = CONSTRAINT_NAME,
               v_MESSAGE_TEXT = MESSAGE_TEXT,
               v_TABLE_NAME = TABLE_NAME;
           RAISE NOTICE 'Violated constraint % in table %. Message: %', v_CONSTRAINT_NAME, v_TABLE_NAME, v_MESSAGE_TEXT;
       WHEN OTHERS THEN
           RAISE NOTICE 'An error occurred: %', SQLERRM;
       ROLLBACK;   
END;
$$;

CALL increase_price_w_check ('Pants', 0.05); -- should work and increase price by 5%
CALL increase_price_w_check ('Pants', 0.6); -- should trigger error and rollback
CALL increase_price_w_check ('Pants', -1.1); -- should trigger error and rollback

-- excercise 1: 10% increase with changed message

CREATE OR REPLACE PROCEDURE increase_price_w_check (IN p_category_label TEXT, IN p_percentage_increase NUMERIC)
LANGUAGE PLPGSQL
AS
$$




-- generating embeddings using the Mistral API in a PL/Python stored procedure

/* CURL example

curl -X POST "https://api.mistral.ai/v1/embeddings" \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer ${MISTRAL_API_KEY}" \
     -d '{"model": "codestral-embed", "input": ["Embed this sentence."], "output_dimension":6}'


*/

/*
 Python example
Check my_embedding_simple.py for a simple example of how to call the Mistral API from a PL/Python stored procedure
my_embedding.py includes error handling to catch any errors that might occur during the API call and prints the error details in the console, 
and also includes an example of how to parse the response from the API to extract the embedding vector and other details.
*/







-- add the embeddings as vectors
UPDATE fruit_store.fruit 
    SET embedding = api.mistral_embed (FORMAT('%s has the properties %s', name, description));

         
















-------- Drafts below ----

DO
$$
DECLARE 
    v_test INTEGER;
    b_test BOOLEAN;
BEGIN
SELECT COUNT(*) INTO v_test FROM fruit_store.fruit;
RAISE NOTICE 'Nbr of records: %', v_test;
GET DIAGNOSTICS v_test = ROW_COUNT;
RAISE NOTICE 'ROW COUNT: %', v_test;
RAISE NOTICE 'FOUND: %', FOUND;
END;
$$;


SELECT api.mistral_embed('This is a test sentence to generate an embedding for.'); -- should return a 6 dimensional embedding vector as a float4 array

DROP FUNCTION IF EXISTS api.mistral_test_key();
CREATE OR REPLACE FUNCTION api.mistral_test_key()
RETURNS TEXT
LANGUAGE plpython3u
AS $$
import json
import ssl
import urllib.request
import urllib.error
import plpy, os

rv = plpy.execute("SELECT current_setting('api.mistral_api_key', true) AS apikey")
apikey = rv[0]["apikey"] 
if not apikey:
    plpy.notice("Mistral API key is not set. Please set the api.mistral_api_key configuration variable.")
else:
    plpy.notice("mistral_api_key: %s" % apikey)
    plpy.notice("Response from plpy.execute(): %s" % rv)
    return apikey
$$;

SELECT api.mistral_test_key(); -- should print the API key in the console

-- create a CTE that shows whet the top 10 customers buy from the top 10 products using sales_transaction, sales_transaction_items, customers and products tables   

WITH top_customers AS (
    -- top 10 customers by spending
    SELECT c.id, SUM(stl.qty * stl.price) AS total_spent
    FROM sales_transaction st
    JOIN customer c ON st.customer_id = c.id
    JOIN sales_transaction_line stl ON st.id = stl.sales_transaction_id
    GROUP BY c.id
    ORDER BY total_spent DESC
    LIMIT 10
),
top_products AS (
    -- top 10 products by quantity sold
    SELECT p.id, 
    FROM product p
    JOIN product_variant pv
    JOIN sales_tra

 
)


--- simple stored procedure that increases the price of a product by a given percentage, and returns the new price
DROP PROCEDURE IF EXISTS increase_price(TEXT, NUMERIC);

CREATE OR REPLACE PROCEDURE increase_price (IN p_category_label TEXT, IN p_percentage_increase NUMERIC)
LANGUAGE PLPGSQL
AS 
$$
DECLARE 
    v_poduct_record RECORD;
    v_old_price NUMERIC;
    v_new_price NUMERIC;
BEGIN
    -- get all relevant products and product variants
    FOR v_poduct_record IN SELECT * FROM product_full_details WHERE category_label = p_category_label
        LOOP
            UPDATE product_variant
            SET price = price * (1 + p_percentage_increase)
            WHERE id = v_poduct_record.product_variant_id
            RETURNING OLD.price, NEW.price INTO v_old_price, v_new_price;
            RAISE NOTICE 'Updated price for product variant % (%): old price %, new price is %', 
                v_poduct_record.product_variant_id, v_poduct_record.product_label, v_old_price, v_new_price;
        END LOOP;
END;
$$; 

SELECT * FROM product_full_details WHERE category_label = 'Pants';

CALL increase_price ('Pants', 0.05);

-- modified procedure that triggers and error if the price increase is more than 50% and rolls back the transaction, otherwise it increases the price and returns the new price
DROP PROCEDURE IF EXISTS increase_price_w_check(TEXT, NUMERIC);
CREATE OR REPLACE PROCEDURE increase_price_w_check (IN p_category_label TEXT, IN p_percentage_increase NUMERIC)
LANGUAGE PLPGSQL
AS 
$$
DECLARE 
    v_poduct_record RECORD; v_old_price NUMERIC; v_new_price NUMERIC;
    -- will hold error details in case of exception
    v_MESSAGE_TEXT TEXT; v_CONSTRAINT_NAME TEXT; v_TABLE_NAME TEXT;
BEGIN
    IF p_percentage_increase > 0.5 THEN -- trigger an error if the price increase is more than 50%
        RAISE EXCEPTION 'Price increase of % is too high, aborting transaction', TO_CHAR (p_percentage_increase * 100, '999.0%');
    END IF;
    FOR v_poduct_record IN SELECT * FROM product_full_details WHERE category_label = p_category_label
        LOOP
            UPDATE product_variant
                SET price = price * (1 + p_percentage_increase)
                WHERE id = v_poduct_record.product_variant_id
                RETURNING OLD.price, NEW.price INTO v_old_price, v_new_price;
            RAISE NOTICE 'Updated price for product variant % (%): old price %, new price is %', 
                v_poduct_record.product_variant_id, v_poduct_record.product_label, v_old_price, v_new_price;
        END LOOP;
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'Violated check constraint; Details below';
            GET STACKED DIAGNOSTICS 
                v_CONSTRAINT_NAME = CONSTRAINT_NAME,
                v_MESSAGE_TEXT = MESSAGE_TEXT,
                v_TABLE_NAME = TABLE_NAME;
            RAISE NOTICE 'Violated constraint % in table %. Message: %', v_CONSTRAINT_NAME, v_TABLE_NAME, v_MESSAGE_TEXT;
        WHEN OTHERS THEN
            RAISE NOTICE 'An error occurred: %', SQLERRM;
        ROLLBACK;    
END;
$$; 

CALL increase_price_w_check ('Pants', 0.05); -- should work and increase price by 5%
CALL increase_price_w_check ('Pants', 0.6); -- should trigger error and rollback
CALL increase_price_w_check ('Pants', -1.1); -- should trigger error and rollback


-- PLPython

CREATE EXTENSION plpython3u;


CREATE OR REPLACE PROCEDURE product.ensure_description_uppercase()
AS $$
import plpy
rows = plpy.execute("SELECT id, description FROM category")
for row in rows:
    desc = row['description']
    if desc and not desc[0].isupper():
        # Print the description that needs to be fixed
        plpy.notice("This description needs to be fixed: %s" % desc)
        # Capitalize the first letter of the description
        new_desc = desc[0].upper() + desc[1:]
        plpy.notice("Fixed: %s" % new_desc)
        # Use % formatting and escape single quotes to create query string
        update_sql = (
            "UPDATE category "
            "SET description = '%s' WHERE id = %d"
        ) % (new_desc.replace("'", "''"), row['id'])
        plpy.notice("Update query: %s" % update_sql)
        plpy.execute(update_sql)
$$ LANGUAGE plpython3u;

CALL product.ensure_description_uppercase();


CREATE OR REPLACE FUNCTION product.insert_category(
    p_id INTEGER,
    p_label TEXT,
    p_description TEXT
)
RETURNS TEXT
AS $$
import plpy
from plpy import spiexceptions
try:
    sql = (
        "INSERT INTO product.category (id, label, description) "
        "VALUES (%d, '%s', '%s')"
    ) % (
        p_id,
        p_label.replace("'", "''"),
        p_description.replace("'", "''")
    )
    plpy.notice("Insert query: %s" % sql)
    plpy.execute(sql)
    return "Insert successful"
except spiexceptions.UniqueViolation as e:
    return "Unique constraint violation: " + str(e)
except spiexceptions.PrimaryKeyViolation as e:
    return "Primary constraint violation: " + str(e)
except plpy.SPIError as e:
    return "other error, SQLSTATE %s" % e.sqlstate
except Exception as e:
        return "Unknown error: " + str(e)
$$ LANGUAGE plpython3u;

SELECT * FROM product.insert_category(999, 'Test Category', 'This is a test category'); -- should work
SELECT * FROM product.insert_category(1000, 'Test Category', 'This is a test category'); -- should trigger unique constraint violation error
SELECT * FROM product.insert_category(1, 'Test for PK violation', 'This is a test category'); -- should trigger primary key violation error


--- trigger example that updates a last_updated timestamp column on the product table whenever a product is updated
ALTER TABLE category ADD COLUMN last_updated TIMESTAMPTZ DEFAULT NOW();


CREATE OR REPLACE FUNCTION category_last_updated()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE INFO 'Updating category ''%'' with new description and setting the value of last_updated to % inside trigger ''%''', NEW.label, NOW(), TG_NAME;
    NEW.last_updated = NOW();
    RETURN NEW;
END;
$$; 

DROP TRIGGER IF EXISTS update_category_last_updated ON category;
CREATE TRIGGER update_category_last_updated
BEFORE UPDATE ON category
FOR EACH ROW
EXECUTE FUNCTION category_last_updated();

-- should update last_updated column and print notice with new description
UPDATE category 
    SET description = 'updated description for test category' 
    WHERE id = 999; 


-- trigger example that creates a SCD Type 2 history table for the category table, 
-- and inserts a new record into the history table whenever a category is updated, with the old values and a validity period defined by valid_from and valid_to timestamps    
DROP TABLE IF EXISTS category_history;
CREATE TABLE category_history (
    id INTEGER,
    label TEXT,
    description TEXT,
    action TEXT,   -- INSERT, UPDATE, DELETE
    time TIMESTAMPTZ DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION maintain_category_history()
RETURNS TRIGGER
LANGUAGE PLPGSQL
AS $$
BEGIN
    IF (OLD.label IS DISTINCT FROM NEW.label) OR (OLD.description IS DISTINCT FROM NEW.description) THEN
        INSERT INTO category_history (id, label, description, action, time)
        VALUES (COALESCE(OLD.id, NEW.id), NEW.label, NEW.description, TG_OP, NOW());
        RAISE INFO 'Inserted history record for category id % with label %, description %, and operation type %', COALESCE(OLD.id, NEW.id), NEW.label, NEW.description, TG_OP;
    END IF;
    RETURN NEW;
END;
$$; 

DROP TRIGGER IF EXISTS category_scd_type2_trigger ON category;
CREATE TRIGGER category_scd_type2_trigger
AFTER INSERT OR UPDATE OR DELETE ON category
FOR EACH ROW
EXECUTE FUNCTION maintain_category_history();  

