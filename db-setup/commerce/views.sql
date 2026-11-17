/***************************************************************************************************

Sets up a simple view summarizing customer information, including their address and purchase history.

2026 Copyright: Marc Linster
Last Update: 2026-11-17

****************************************************************************************************/






CREATE MATERIALIZED VIEW customer_summary_mv AS
SELECT c.id as customer_id,
       c.first_name,
       c.last_name,
       c.since,
       a.localite,
       a.commune,
       p.product_nbr,
       p.name product_name,
       p.price,
       cat.id category_id,
       cat.name category_name,
       pu.date,
       pu.quantity
FROM customer c
JOIN address a ON c.address_id = a.id
LEFT JOIN purchase pu ON c.id = pu.customer_id
LEFT JOIN product p ON pu.product_nbr = p.product_nbr
LEFT JOIN category cat ON p.category_id = cat.id
ORDER BY pu.date,
         c.last_name,
         c.first_name;