


-- JSON exercises

SELECT * FROM customer WHERE first_name = 'Margarita' AND last_name = 'Woods';

SELECT first_name, phone_numbers FROM customer LIMIT 5;


SELECT first_name, JSONB_PRETTY(phone_numbers) FROM customer LIMIT 5;


SELECT
	first_name,
	phone_numbers,
	phone_numbers ->> 'home' AS home_phone_number,
	phone_numbers ->> 'mobile' AS mobile_phone_number
FROM customer
LIMIT 5;


-- has the key 'mobile' in the phone_numbers JSONB column
SELECT first_name, phone_numbers
FROM customer
WHERE phone_numbers ? 'mobile'
LIMIT 5;


-- does not have the key 'home' in the phone_numbers JSONB column
SELECT first_name, phone_numbers 
	FROM customer
	WHERE NOT(phone_numbers ? 'home')
	LIMIT 5;


SELECT  first_name, last_name, phone_numbers FROM customer
    WHERE first_name = 'Daisy' AND last_name = 'Hicks';

-- Adding to a JSON data element
UPDATE customer
		SET phone_numbers =
			jsonb_insert (phone_numbers, '{new}', '"123 456 789"')
    	WHERE first_name = 'Daisy' AND last_name = 'Hicks';

-- Removing a JSON data element
UPDATE customer 
		SET phone_numbers = 
			phone_numbers - 'new' 
	WHERE first_name = 'Daisy' AND last_name = 'Hicks'; 

-- Simple way to convert JSONB to text

SELECT product_variant_id,
      product_label,
      'Attributes: ' || product_variant_attributes::text
FROM product_full_details
limit 5;

-- Try it Out

SELECT first_name, last_name, phone_numbers FROM customer
    WHERE first_name = 'Edward' AND last_name = 'Meyer';

UPDATE customer
		SET phone_numbers =
			jsonb_insert (phone_numbers, '{home}', '"33 45 67"')
    	WHERE first_name = 'Edward' AND last_name = 'Meyer';

UPDATE customer
		SET phone_numbers =
			jsonb_insert (phone_numbers, '{weekend}', '"621 123 456"')
    	WHERE first_name = 'Edward' AND last_name = 'Meyer';  


-- Find all the products that have a the attribute 'size' in the attributes JSONB column, and return the product name and the value of the 'size' attribute
-- join product and product_variant tables to get the product name and the attributes JSONB column, then filter for products that have the 'size' key in the 
-- attributes JSONB column, and return the product name and the value of the 'size' attribute

SELECT DISTINCT p.label, pv.attributes ->> 'size' AS size
FROM product p
JOIN product_variant pv ON p.id = pv.product_id
WHERE pv.attributes ? 'size'
ORDER BY p.label, size ASC;

WITH product_variant AS( 
    SELECT DISTINCT pv.product_id, pv.attributes ->> 'size' AS size FROM product_variant pv
    WHERE pv.attributes ? 'size')
SELECT p.label, pv.size
FROM product p
JOIN product_variant pv ON p.id = pv.product_id
ORDER BY p.label, pv.size ASC;


-- Stored Procedures


DECLARE
   v_poduct_record RECORD; v_old_price NUMERIC; v_new_price NUMERIC;
   -- will hold error details in case of exception
   v_MESSAGE_TEXT TEXT; v_CONSTRAINT_NAME TEXT; v_TABLE_NAME TEXT;
BEGIN
   IF p_percentage_increase > 0.10 THEN -- trigger an error if the price increase is more than 50%
       RAISE EXCEPTION 'Price increase of % is too high, needs to be 10 %% or less, aborting transaction', TO_CHAR (p_percentage_increase * 100, '999.0%');
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

CALL increase_price_w_check ('Pants', 0.11);


-- excercise 2: Allow 20% increase for sportswear category, but only 10% for other categories

CREATE OR REPLACE PROCEDURE increase_price_w_check (IN p_category_label TEXT, IN p_percentage_increase NUMERIC)
LANGUAGE PLPGSQL
AS
$$
DECLARE
   v_poduct_record RECORD; v_old_price NUMERIC; v_new_price NUMERIC;
   -- will hold error details in case of exception
   v_MESSAGE_TEXT TEXT; v_CONSTRAINT_NAME TEXT; v_TABLE_NAME TEXT;
BEGIN
   IF p_percentage_increase > 0.20 AND p_category_label = 'Sportswear' THEN -- allow 20% increase for sportswear
       RAISE EXCEPTION 'Price increase of % is too high, needs to be 20 %% or less, aborting transaction', TO_CHAR (p_percentage_increase * 100, '999.0%');
   ELSIF p_percentage_increase > 0.10 AND p_category_label != 'Sportswear' THEN -- trigger an error if the price increase is more than 10% and the category is not Sportswear
       RAISE EXCEPTION 'Price increase of % is too high, needs to be 10 %% or less, aborting transaction', TO_CHAR (p_percentage_increase * 100, '999.0%');
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

CALL increase_price_w_check ('Pants', 0.11);
CALL increase_price_w_check ('Sportswear', 0.15);
CALL increase_price_w_check ('Sportswear', 0.21);

-- PL/Python

-- PL/Python3U stored procedures

-- add the extension if it is not already added to the database, so we can create PL/Python stored procedures and functions
CREATE EXTENSION IF NOT EXISTS plpython3u;

-- Find all categories where the description is not capitalized, and print the id and description in the console
-- this uses SQL only - no PL/Pyton
SELECT id, description FROM category
    WHERE description = LOWER(description);

-- Find all categories where the description is not capitalized, and print the id and description in the console 
-- using a PL/Python stored procedure 
CREATE OR REPLACE PROCEDURE product.ensure_description_uppercase()
AS $$
import plpy
rows = plpy.execute("SELECT id, description FROM category")
for row in rows:
    desc = row['description']
    if desc and not desc[0].isupper():
        plpy.notice("This description needs to be fixed: %s" % desc)
$$ LANGUAGE plpython3u;    

-- Find all categories with lowercase descriptions and capitalize them

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

-- lowercase all category descriptions to test the procedure again

CREATE OR REPLACE PROCEDURE product.ensure_description_lowercase()
AS $$
import plpy
rows = plpy.execute("SELECT id, description FROM category")
for row in rows:
   desc = row['description']
   if desc and not desc[0].islower():
       # Print the description that needs to be fixed
       plpy.notice("This description needs to be fixed: %s" % desc)
       # Capitalize the first letter of the description
       new_desc = desc[0].lower() + desc[1:]
       plpy.notice("Fixed: %s" % new_desc)
       # Use % formatting and escape single quotes to create query string
       update_sql = (
           "UPDATE category "
           "SET description = '%s' WHERE id = %d"
       ) % (new_desc.replace("'", "''"), row['id'])
       plpy.notice("Update query: %s" % update_sql)
       plpy.execute(update_sql)
$$ LANGUAGE plpython3u;

CALL product.ensure_description_lowercase();

-- simpler way to do it in PL/Python

CREATE OR REPLACE PROCEDURE product.ensure_description_lowercase()
AS $$
import plpy
plpy.execute("UPDATE category SET description = LOWER(description)")
$$ LANGUAGE plpython3u;

CALL product.ensure_description_lowercase();

CALL product.ensure_description_uppercase();


-- Error Handling in PL/Python3u

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
   plpy.execute(sql)
   return "Insert successful"
except spiexceptions.UniqueViolation as e:
   return "Unique constraint violation: " + str(e)
except spiexceptions.PrimaryKeyViolation as e:
   return "Unique constraint violation: " + str(e)
except plpy.SPIError as e:
   return "other error, SQLSTATE %s" % e.sqlstate
except Exception as e:
       return "Unknown error: " + str(e)
$$ LANGUAGE plpython3u;

SELECT product.insert_category(999, 'Test Category', 'This is a test category'); -- should work
SELECT product.insert_category(1000, 'Test Category', 'This is a test category'); -- should trigger unique constraint violation error
SELECT product.insert_category(1, 'Test for PK violation', 'This is a test category'); -- should trigger primary key violation error