/*
This SQL script sets up the database schema for a sportscar database, which includes tables for
brands, countries, colors, models, configurations (model + color combinations), and embeddings for the configurations.

This should be run inside the database sportscars, which is created in the master_setup.sql script. 
The master_setup.sql script also sets the MISTRAL_API_KEY environment variable, which is required for generating the embeddings using the Mistral API.


This is part of the DLH Training Class for AI and Postgres, and is meant for educational purposes to 
demonstrate how to set up a database schema for vector embeddings and how to integrate with an 
external API for generating those embeddings.

Last Update: 2026-04-30
*/

-- Add the vector extension, which is required for storing vector embeddings in Postgres
CREATE EXTENSION IF NOT EXISTS vector;
-- Add the PL/Python extension, which is required for creating stored procedures and functions in Python, 
-- which we will use to call the Mistral API to generate embeddings
CREATE EXTENSION IF NOT EXISTS plpython3u;


-- Create brands table
CREATE TABLE brand (
    id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    name VARCHAR(100) NOT NULL UNIQUE,
    founded_year INT
);

-- Create countries table (for country of origin)
CREATE TABLE country (
    id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    name VARCHAR(100) NOT NULL UNIQUE,
    code VARCHAR(2) NOT NULL UNIQUE
);

-- Create colors table
CREATE TABLE color (
    id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY, 
    name VARCHAR(50) NOT NULL UNIQUE,
    hex_code VARCHAR(7)
);

-- Create models table (main table linking all the above)
CREATE TABLE model (
    id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    name VARCHAR(100) NOT NULL,
    brand_id INT NOT NULL REFERENCES brand(id) ON DELETE CASCADE,
    country_of_origin_id INT NOT NULL REFERENCES country(id),
    number_of_seats INT NOT NULL CHECK (number_of_seats > 0),
    production_year INT,
    price DECIMAL(12, 2),
    description TEXT, -- the description of the model which will be used for generating embeddings
    UNIQUE(brand_id, name)
);

-- Create the list of available configurations (model + color combinations)
CREATE TABLE configuration (
    id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    model_id INT NOT NULL REFERENCES model(id) ON DELETE CASCADE,
    color_id INT NOT NULL REFERENCES color(id) ON DELETE CASCADE,
    UNIQUE(model_id, color_id)
);

CREATE TABLE IF NOT EXISTS embedding (
    configuration_id INT PRIMARY KEY REFERENCES configuration(id) ON DELETE CASCADE,
    embedding_vector vector
);



-- Insert sample data
INSERT INTO brand (name, founded_year) VALUES
    ('Ferrari', 1947),
    ('Lamborghini', 1963),
    ('Porsche', 1931),
    ('McLaren', 1985),
    ('Bugatti', 1909),
    ('Koenigsegg', 1994),
    ('Aston Martin', 1913),
    ('Jaguar', 1935),
    ('Chevrolet', 1911),
    ('Pagani', 1992),
    ('Lotus', 1948),
    ('Maserati', 1914),
    ('Volkswagen', 1937);

INSERT INTO country (name, code) VALUES
    ('Italy', 'IT'),
    ('Germany', 'DE'),
    ('United Kingdom', 'GB'),
    ('United States', 'US'),
    ('France', 'FR'),
    ('Sweden', 'SE'),
    ('Japan', 'JP');

INSERT INTO color (name, hex_code) VALUES
    ('Red', '#FF0000'),
    ('Yellow', '#FFFF00'),
    ('Black', '#000000'),
    ('Silver', '#C0C0C0'),
    ('White', '#FFFFFF'),
    ('Blue', '#0000FF'),
    ('Green', '#008000'),
    ('Orange', '#FFA500'),
    ('Purple', '#800080'),
    ('Gray', '#808080'),
    ('Gold', '#FFD700'),
    ('Pearl White', '#FDEEF4');

INSERT INTO model (name, brand_id, country_of_origin_id, number_of_seats, production_year, price) VALUES
    ('F8 Tributo', 1, 1, 2, 2019, 280000),
    ('Aventador', 2, 1, 2, 2011, 400000),
    ('911 Turbo', 3, 2, 4, 2020, 200000),
    ('P1', 4, 3, 2, 2013, 915000),
    ('LaFerrari', 1, 1, 2, 2013, 1400000),
    ('Roma', 1, 1, 2, 2020, 220000),
    ('Revuelto', 2, 1, 2, 2024, 500000),
    ('Huracán', 2, 1, 2, 2014, 250000),
    ('918 Spyder', 3, 2, 2, 2013, 845000),
    ('Taycan Turbo', 3, 2, 2, 2020, 180000),
    ('GT', 4, 3, 2, 2016, 385000),
    ('720S', 4, 3, 2, 2017, 315000),
    ('Chiron', 5, 5, 2, 2016, 2900000),
    ('Bolide', 5, 5, 1, 2022, 5000000),
    ('Gemera', 6, 6, 2, 2021, 1700000),
    ('CC850', 6, 6, 2, 2024, 2800000),
    ('DBS Superleggera', 7, 3, 2, 2018, 300000),
    ('Vantage', 7, 3, 2, 2018, 150000),
    ('F-Type', 8, 3, 2, 2013, 95000),
    ('C8 Corvette', 9, 4, 2, 2020, 56000),
    ('Huayra', 10, 1, 2, 2012, 1300000),
    ('Emira', 11, 3, 2, 2021, 67000),
    ('MC20', 12, 1, 2, 2021, 1400000),
    ('750LT', 4, 3, 2, 2019, 380000);

INSERT INTO model (name, brand_id, country_of_origin_id, number_of_seats, production_year, price) VALUES    
    ('Golf R', 13, 2, 4, 2022, 45000);

INSERT INTO configuration (model_id, color_id) VALUES
    (1, 1), (1, 2), (1, 5),  -- F8 Tributo: Red, Yellow, White
    (2, 1), (2, 3),           -- Aventador: Red, Black
    (3, 4), (3, 5),           -- 911 Turbo: Silver, White
    (4, 3), (4, 5),           -- P1: Black, White
    (5, 1), (5, 4), (5, 11),  -- LaFerrari: Red, Silver, Gold
    (6, 1), (6, 5), (6, 2),   -- Roma: Red, White, Yellow
    (7, 1), (7, 3), (7, 4),   -- Revuelto: Red, Black, Silver
    (8, 2), (8, 4), (8, 6),   -- Huracán: Yellow, Silver, Blue
    (9, 3), (9, 6), (9, 11),  -- 918 Spyder: Black, Blue, Gold
    (10, 5), (10, 3), (10, 4),-- Taycan Turbo: White, Black, Silver
    (11, 3), (11, 5), (11, 11),-- GT: Black, White, Gold
    (12, 4), (12, 5), (12, 2), -- 720S: Silver, White, Yellow
    (13, 1), (13, 11), (13, 3), -- Chiron: Red, Gold, Black
    (14, 1), (14, 5), (14, 8), -- Bolide: Red, White, Orange
    (15, 6), (15, 4), (15, 9), -- Gemera: Blue, Silver, Purple
    (16, 1), (16, 3), (16, 10),-- CC850: Red, Black, Gray
    (17, 4), (17, 5), (17, 6), -- DBS Superleggera: Silver, White, Blue
    (18, 1), (18, 4), (18, 12),-- Vantage: Red, Silver, Pearl White
    (19, 1), (19, 2), (19, 5), -- F-Type: Red, Yellow, White
    (20, 1), (20, 6), (20, 5), -- C8 Corvette: Red, Blue, White
    (21, 1), (21, 11), (21, 3),-- Huayra: Red, Gold, Black
    (22, 6), (22, 4), (22, 5), -- Emira: Blue, Silver, White
    (23, 3), (23, 11), (23, 5),-- MC20: Black, Gold, White
    (24, 4), (24, 6), (24, 11);-- 750LT: Silver, Blue, Gold


-- Populate descriptions for existing models
UPDATE model SET description = 'A stunning mid-engine sports car featuring a twin-turbocharged V12 engine with 710 horsepower. Known for its aggressive styling and exceptional performance.' 
WHERE name = 'F8 Tributo';

UPDATE model SET description = 'An iconic Italian supercar powered by a naturally aspirated V12 engine. The Aventador represents Lamborghini''s commitment to luxury and extreme performance.' 
WHERE name = 'Aventador';

UPDATE model SET description = 'A German performance machine with a 6-cylinder engine and distinctive design. Offers both speed and practicality with 4 seats, making it ideal for daily driving.' 
WHERE name = '911 Turbo';

UPDATE model SET description = 'A hybrid hypercar from McLaren combining a V8 engine with electric motors for 903 horsepower. Features groundbreaking aerodynamics and technology.' 
WHERE name = 'P1';

UPDATE model SET description = 'Ferrari''s hybrid limited production hypercar with a V12 engine and electric motor producing 950 horsepower. Only 499 units were produced.' 
WHERE name = 'LaFerrari';

UPDATE model SET description = 'A modern grand tourer from Ferrari with a V12 engine, 612 horsepower, and 2+2 seating. Combines classical design with contemporary technology.' 
WHERE name = 'Roma';

UPDATE model SET description = 'Lamborghini''s groundbreaking hybrid flagship featuring a V12 engine with electric assistance and 1001 horsepower. Represents the future of supercars.' 
WHERE name = 'Revuelto';

UPDATE model SET description = 'A mid-engine supercar from Lamborghini with a V10 engine producing 640 horsepower. Known for its dramatic styling and aggressive performance.' 
WHERE name = 'Huracán';

UPDATE model SET description = 'Porsche''s flagship hybrid hypercar with a V8 engine and dual electric motors producing 918 horsepower. Limited to 918 units worldwide.' 
WHERE name = '918 Spyder';

UPDATE model SET description = 'Porsche''s first fully electric sportscar offering impressive acceleration and handling. Designed as a daily-use performance machine.' 
WHERE name = 'Taycan Turbo';

UPDATE model SET description = 'McLaren''s grand touring supercar with a twin-turbo V8 producing 625 horsepower. Combines speed with luxury and practicality.' 
WHERE name = 'GT';

UPDATE model SET description = 'McLaren''s mid-engine supercar with a twin-turbo V8 engine delivering 710 horsepower. Known for exceptional handling and performance.' 
WHERE name = '720S';

UPDATE model SET description = 'Bugatti''s quad-turbo hypercar with an 8.0L W16 engine producing 1,500 horsepower. One of the fastest and most powerful production cars ever.' 
WHERE name = 'Chiron';

UPDATE model SET description = 'Bugatti''s single-seater track-only hypercar with a modified W16 engine pushing 1,850 horsepower. A limited production extreme performance vehicle.' 
WHERE name = 'Bolide';

UPDATE model SET description = 'Koenigsegg''s innovative hypercar with a twin-turbo V8 and hybrid assist producing 1,373 horsepower. Features cutting-edge Swedish engineering.' 
WHERE name = 'Gemera';

UPDATE model SET description = 'Koenigsegg''s ultimate hypercar evolution with twin-turbo V8 producing 1,280 horsepower. The most exclusive and powerful Koenigsegg ever built.' 
WHERE name = 'CC850';

UPDATE model SET description = 'Aston Martin''s GT supercar powered by a twin-turbo V12 with 715 horsepower. Combines British luxury with superb performance.' 
WHERE name = 'DBS Superleggera';

UPDATE model SET description = 'Aston Martin''s modern grand tourer with a twin-turbo V8 engine. Offers a perfect blend of luxury, performance, and elegance.' 
WHERE name = 'Vantage';

UPDATE model SET description = 'Jaguar''s stylish sports car with a supercharged V8 engine and 575 horsepower. Known for its beautiful design and exhilarating driving experience.' 
WHERE name = 'F-Type';

UPDATE model SET description = 'Chevrolet''s mid-engine American supercar featuring a 6.2L naturally aspirated V8 with 495 horsepower. Offers supercar performance at an accessible price.' 
WHERE name = 'C8 Corvette';

UPDATE model SET description = 'Pagani''s Italian handcrafted hypercar with a twin-turbo V12 producing 627 horsepower. Combines Art, Engineering, and Passion.' 
WHERE name = 'Huayra';

UPDATE model SET description = 'Lotus'' modern sportscar successor with a supercharged V6 engine and 400 horsepower. Built with carbon fiber for lightweight performance.' 
WHERE name = 'Emira';

UPDATE model SET description = 'Maserati''s mid-engine supercar with a twin-turbo V8 producing 630 horsepower. Features Italian styling and precision engineering.' 
WHERE name = 'MC20';

UPDATE model SET description = 'McLaren''s limited-production LT variant with enhanced performance and weight reduction. Twin-turbo V8 delivers 765 horsepower of pure speed.' 
WHERE name = '750LT';

UPDATE model SET description = 'Volkswagen''s high-performance hot hatchback featuring a turbocharged 2.0-liter engine producing 315 horsepower. The Golf R delivers exceptional handling and all-wheel drive capability.' 
WHERE name = 'Golf R';




-- Create a comprehensive view for easy querying

DROP VIEW IF EXISTS vw_sportscars;
CREATE VIEW vw_sportscars AS
SELECT
    c.id AS configuration_id,
    b.name AS brand_name,
    m.name AS model_name,
    m.id AS model_id,
    m.description AS model_description,
    co.name AS country_of_origin,
    m.price,
    col.name AS color_name
FROM configuration c
JOIN model m ON c.model_id = m.id
JOIN color col ON c.color_id = col.id
JOIN brand b ON m.brand_id = b.id
JOIN country co ON m.country_of_origin_id = co.id
ORDER BY brand_name, model_name DESC;

