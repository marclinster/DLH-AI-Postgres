
select id,
       first_name,
       last_name,
       since,
       JSONB_PRETTY(phone_numbers)
from customer
where id = 1;


-- Accessing JSONB using ->, ->>, #>, and #>>
-- ->: get a value as JSONB
SELECT phone_numbers->'work'->2 FROM customer WHERE id = 1;

-- ->>: get a value as text
SELECT phone_numbers->'work'->2->>'number' FROM customer WHERE id = 1;

-- #>>: get a value by path as text
SELECT phone_numbers #>> '{work,2,country_code}' FROM customer WHERE id = 1;


SELECT jsonb_path_query_first(phone_numbers, '$.work[2].country_code') #>> '{}' AS country_code
FROM customer
WHERE id = 1;

-- Add a phone number to a customer
UPDATE customer
SET phone_numbers = jsonb_set(
        phone_numbers,
        '{work}',
        (phone_numbers->'work') || jsonb_build_object('country_code', '(+1)', 'number', '555.123.456'))
WHERE id = 1;

-- check that the new number was added
select id,
       first_name,
       last_name,
       since,
       JSONB_PRETTY(phone_numbers)
from customer
where id = 1;

-- Remove a phone number from a customer
UPDATE customer
SET phone_numbers = phone_numbers #- '{work,2}'
WHERE id = 1;

-- update a phone number for a customer
UPDATE customer
SET phone_numbers = jsonb_set(
        phone_numbers,
        '{work,1,number}',
        '"555.987.654"')
WHERE id = 1;



-- Check for the existence of a key in a JSONB column
SELECT 
    phone_numbers ? 'work' AS has_work_number, 
    phone_numbers ? 'home' AS has_home_number,
    phone_numbers ? 'fax' AS has_fax_number 
FROM customer 
WHERE id = 1;

-- Find customers with a German work phone
/*
  What it does: lists every customer with at least one German (+49) work phone,
  plus that German number. The query runs in four steps:

  1. FROM customer
     Start with all customers.

  2. WHERE phone_numbers @> '{"work": [{"country_code": "(+49)"}]}'
     Keep only customers with a German work phone.
     - @> means "the left side contains the right side".
     - For arrays, containment means AT LEAST ONE element matches the pattern.
       Position does not matter, and other fields (like "number") are ignored.
     - A GIN index on phone_numbers can speed this up.

  3. SELECT id, first_name, last_name, ...
     For each remaining customer, return the ID and name plus one computed column.

  4. german_work_number
     jsonb_path_query_first(phone_numbers, '$.work[*] ? (@.country_code == "(+49)").number') #>> '{}'

       $                            the whole phone_numbers document
       .work                        the "work" array
       [*]                          each element in turn
       ? ( ... )                    filter: keep elements where the condition is true
       @.country_code == "(+49)"    @ is the element being tested
       .number                      take that element's "number" field

     - jsonb_path_query_first returns the FIRST match as JSONB (e.g. "101.894.497"),
       or NULL if nothing matches (the row is not dropped).
     - #>> '{}' unwraps the JSONB string into plain text (101.894.497).

  Why both @> and the JSON path?
     - @> in WHERE decides WHICH ROWS to return (quick, can use an index).
     - The JSON path in SELECT pulls out the VALUE from rows that passed the filter.
     - WHERE phone_numbers @? '$.work[*] ? (@.country_code == "(+49)")' gives the same rows.

  Caveat: some customers have more than one German work phone, and
  jsonb_path_query_first shows only the first. To get all of them, use
  jsonb_path_query (one row per number) or jsonb_path_query_array (one JSON array).
*/
SELECT id, first_name, last_name,
       jsonb_path_query_first(phone_numbers,
           '$.work[*] ? (@.country_code == "(+49)").number') #>> '{}' AS german_work_number
FROM customer
WHERE phone_numbers @> '{"work": [{"country_code": "(+49)"}]}';

-- Find customers with a German work phone and list all their work numbers
SELECT id, first_name, last_name,
       jsonb_path_query_array(phone_numbers,
           '$.work[*] ? (@.country_code == "(+49)").number') AS german_work_numbers
FROM customer
WHERE phone_numbers @> '{"work": [{"country_code": "(+49)"}]}';

SELECT phone_numbers @> '{"work":[{"country_code":"(+1)"}]}' FROM customer WHERE id = 1;


-- Add a new private number to customer 1
-- private - make it a sample Luxembourg landline number (6 digits)

SELECT jsonb_pretty(phone_numbers) AS phone_numbers
FROM customer
WHERE id = 1;

UPDATE customer
SET phone_numbers = jsonb_set(
        phone_numbers,
        '{private}',
        (phone_numbers->'private') || jsonb_build_object('country_code', '(+352)', 'number', '123.456'))
WHERE id = 1;

-- Add a new private number to customer 1
-- weekend (a whole new group at the level of work and home) 
-- make it a sample Luxembourg mobile number 
UPDATE customer
SET phone_numbers = jsonb_set(
        phone_numbers,
        '{weekend}',
        jsonb_build_array(jsonb_build_object('country_code', '(+352)', 'number', '555.123.456')))
WHERE id = 1;


-- find all customers with a German phone (home or work) 
SELECT id, first_name, last_name,
       jsonb_pretty(phone_numbers) AS phone_numbers
FROM customer
WHERE phone_numbers @> '{"work": [{"country_code": "(+49)"}]}'
   OR phone_numbers @> '{"private": [{"country_code": "(+49)"}]}';