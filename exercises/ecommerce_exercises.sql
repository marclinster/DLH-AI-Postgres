
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