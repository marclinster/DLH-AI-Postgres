/***************************************************************************************************

Part of the DLH Training Class for AI and Postgres, and is meant for educational purposes to 
demonstrate how to become comfortable with psql and basic SQL commands.

Simple exercise to become comfortable with CTEs in Postgres.

Copyright 2026: Marc Linster
Last Update: 2026-11-15
***************************************************************************************************/


WITH customer_counts AS (
    SELECT localite, COUNT(DISTINCT customer_id) AS nbr_customers
    FROM customer_summary_mv
    GROUP BY localite
)
SELECT * FROM customer_counts
    WHERE nbr_customers > 1
    ORDER BY nbr_customers DESC;


-- What did my top 10 customers buy in 2025? 
-- Show the total quantity purchased per product per customer.
WITH top_10_customers AS (
    SELECT customer_id, COUNT(*) AS nbr_purchases
    FROM customer_summary_mv
    GROUP BY customer_id
    ORDER BY nbr_purchases DESC
    LIMIT 10
)
SELECT customer_id, first_name, last_name, product_name, SUM(quantity) AS total_quantity FROM customer_summary_mv
    JOIN top_10_customers USING (customer_id)
    WHERE date >= '2025-01-01' AND date < '2026-01-01'
    GROUP BY customer_id, first_name, last_name, product_name
    ORDER BY customer_id, product_name;

-- What did my top 10 customers buy from the top 10 products in 2025? 
-- Show the total quantity purchased per product per customer.
WITH top_10_customers AS (
    SELECT customer_id, COUNT(*) AS nbr_purchases
    FROM customer_summary_mv
    GROUP BY customer_id
    ORDER BY nbr_purchases DESC
    LIMIT 10
),
top_10_products AS (
    SELECT product_nbr, COUNT(*) AS nbr_sales
    FROM customer_summary_mv
    GROUP BY product_nbr
    ORDER BY nbr_sales DESC
    LIMIT 10
)
SELECT customer_id, first_name, last_name, product_name, SUM(quantity) AS total_quantity FROM customer_summary_mv
    JOIN top_10_customers USING (customer_id)
    JOIN top_10_products USING (product_nbr)
    WHERE date >= '2025-01-01' AND date < '2026-01-01'
    GROUP BY customer_id, first_name, last_name, product_name
    ORDER BY customer_id, product_name;


-- Create a CTE to find how many of the TOP 10 food items did my customers in Esch and Duedelange buy in 2025?
WITH top_10_products AS (
    SELECT product_nbr, COUNT(*) AS nbr_sales
    FROM customer_summary_mv
    GROUP BY product_nbr
    ORDER BY nbr_sales DESC
    LIMIT 10
)
SELECT commune, product_name, SUM(quantity) AS total_quantity FROM customer_summary_mv
    JOIN top_10_products USING (product_nbr)
    WHERE date >= '2025-01-01' AND date < '2026-01-01'
    AND commune IN ('Esch-sur-Alzette', 'Dudelange')
    GROUP BY commune, product_name
    ORDER BY commune, product_name;