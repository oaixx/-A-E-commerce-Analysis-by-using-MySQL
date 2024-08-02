-- Use the database 'alibaba'
USE alibaba;

-- View the data from the table 'ecommerce_new' (showing a limited number of rows for quick inspection)
SELECT * FROM ecommerce_new LIMIT 10;

-- Describe the table structure and check data types
DESCRIBE ecommerce_new;

-- Drop the old table 'ecommerce_backup' if it exists
DROP TABLE IF EXISTS ecommerce_backup;

-- Create a new table 'ecommerce_backup' with separated date and time columns
CREATE TABLE ecommerce_backup AS 
SELECT 
    userid, 
    SessionID, 
    QUARTER(timestamp) AS quarter,   -- Extract quarter from the timestamp
    DATE(timestamp) AS dates,        -- Extract date from the timestamp
    TIME(timestamp) AS hours,        -- Extract time from the timestamp
    eventtype,
    ProductID,
    Amount,
    Outcome
FROM ecommerce_new;

-- Add indexes to optimize queries
CREATE INDEX idx_eventtype ON ecommerce_backup(eventtype);
CREATE INDEX idx_dates ON ecommerce_backup(dates);

-- Check the newly created table
SELECT * FROM ecommerce_backup LIMIT 10;

-- Analyze user behavior from a time perspective by counting user actions per hour
DROP TABLE IF EXISTS date_hour_eventtype;
CREATE TABLE date_hour_eventtype AS
SELECT 
    quarter,                      -- Directly use quarter extracted from ecommerce_backup
    dates, 
    TIME_FORMAT(hours, '%H:%i') AS hours, 
    COUNT(IF(eventtype = 'product_view', 1, NULL)) AS product_view, 
    COUNT(IF(eventtype = 'add_to_cart', 1, NULL)) AS add_to_cart,
    COUNT(IF(eventtype = 'purchase', 1, NULL)) AS purchase
FROM ecommerce_backup
GROUP BY quarter, dates, hours   -- Ensure correct grouping
ORDER BY dates, hours;

-- View the data in the table
SELECT * FROM date_hour_eventtype LIMIT 10;

-- Count the occurrence and number of users for each type of user action
DROP TABLE IF EXISTS eventtype_user_num;
CREATE TABLE eventtype_user_num AS
SELECT
    eventtype,
    COUNT(DISTINCT userid) AS users_num
FROM ecommerce_backup
GROUP BY eventtype
ORDER BY eventtype;

SELECT * FROM eventtype_user_num;

-- Create a user event analysis table to calculate purchase rate and cart conversion rate
DROP TABLE IF EXISTS user_event_analysis;
CREATE TABLE user_event_analysis AS
SELECT 
    eventtype,
    COUNT(*) AS total_events,
    COUNT(DISTINCT userid) AS unique_users,
    (SUM(IF(eventtype = 'purchase', 1, 0)) / COUNT(*)) * 100 AS purchase_rate,
    (SUM(IF(eventtype = 'purchase', 1, 0)) / NULLIF(SUM(IF(eventtype = 'add_to_cart', 1, 0)), 0)) * 100 AS cart_conversion_rate
FROM ecommerce_backup
GROUP BY eventtype
ORDER BY eventtype;

-- View the data in the user event analysis table
SELECT * FROM user_event_analysis;

-- Create a view to form a product purchase funnel and analyze conversion paths
DROP VIEW IF EXISTS user_eventtype_view;
CREATE VIEW user_eventtype_view AS 
SELECT 
    userid,
    ProductID,
    COUNT(IF(eventtype = 'product_view', 1, 0)) AS product_view,
    COUNT(IF(eventtype = 'add_to_cart', 1, 0)) AS add_to_cart,
    COUNT(IF(eventtype = 'purchase', 1, 0)) AS purchase
FROM ecommerce_backup
GROUP BY userid, ProductID;

-- Standardize user behavior into a view
DROP VIEW IF EXISTS user_eventtype_standard;
CREATE VIEW user_eventtype_standard AS 
SELECT 
    userid, 
    ProductID,
    (CASE WHEN COUNT(IF(eventtype = 'product_view', 1, 0)) > 0 THEN 1 ELSE 0 END) AS viewed,
    (CASE WHEN COUNT(IF(eventtype = 'add_to_cart', 1, 0)) > 0 THEN 1 ELSE 0 END) AS fav,
    (CASE WHEN COUNT(IF(eventtype = 'purchase', 1, 0)) > 0 THEN 1 ELSE 0 END) AS purchased
FROM ecommerce_backup
GROUP BY userid, ProductID;

-- Create a view for purchase paths to identify types of purchase paths
DROP VIEW IF EXISTS user_purchased_path_view;
CREATE VIEW user_purchased_path_view AS 
SELECT *,
    CONCAT(viewed, fav, purchased) AS purchase_path_type
FROM user_eventtype_standard
WHERE purchased > 0;

-- Count the number of each type of purchase behavior path
SELECT purchase_path_type,
    COUNT(*) AS purchase_path_type_num
FROM user_purchased_path_view
GROUP BY purchase_path_type;

-- Create a path explanation table if not exists
CREATE TABLE IF NOT EXISTS explaination (
    path_type CHAR(3),         -- Path type code
    description VARCHAR(50)    -- Path type description
);

-- Insert data for path type descriptions, ignoring duplicates
INSERT IGNORE INTO explaination 
VALUES
    ('001', 'directly purchase'),
    ('010', 'fav but not purchase'),
    ('100', 'just viewed'),
    ('111', 'viewed and fav and purchased'),
    ('110', 'viewed and fav but not purchase');

-- View the data in the explanation table
SELECT * FROM explaination;

-- Count the path numbers and store them in the path_count table
DROP TABLE IF EXISTS path_count;
CREATE TABLE path_count AS
SELECT purchase_path_type AS path_type,
    COUNT(*) AS path_count
FROM user_purchased_path_view
GROUP BY purchase_path_type;

-- View the statistics results
SELECT * FROM path_count;

-- Combine the statistical results with the explanation table
SELECT 
    p.path_type, 
    p.path_count, 
    e.description
FROM path_count AS p
JOIN explaination AS e
ON p.path_type = e.path_type;

-- Save the statistical results to the path_results table
DROP TABLE IF EXISTS path_results;
CREATE TABLE path_results AS
SELECT 
    p.path_type, 
    e.description, 
    p.path_count AS num
FROM path_count AS p
JOIN explaination AS e
ON p.path_type = e.path_type;

-- View the saved results
SELECT * FROM path_results;

-- Calculate the number of users who purchased without adding to the cart
SELECT COUNT(DISTINCT userid) AS users_without_cart_but_purchased
FROM user_eventtype_view
WHERE purchase > 0 AND add_to_cart = 0;

-- Use a CTE to calculate the number of direct purchase users who did not add to the cart
WITH direct_purchase_users AS (
    SELECT userid, 
           COUNT(DISTINCT ProductID) AS num_purchases
    FROM user_eventtype_view
    WHERE purchase > 0 AND add_to_cart = 0
    GROUP BY userid
),

-- Use a CTE to calculate the total number of purchase users
total_purchase_users AS (
    SELECT userid,
           COUNT(DISTINCT ProductID) AS total_purchases
    FROM user_eventtype_view
    WHERE purchase > 0
    GROUP BY userid
)

-- Calculate the number and proportion of direct purchase users
SELECT 
    SUM(d.num_purchases) AS direct_purchases,
    SUM(t.total_purchases) AS total_purchases,
    (SUM(d.num_purchases) / NULLIF(SUM(t.total_purchases), 0)) * 100 AS direct_purchase_percentage
FROM 
    direct_purchase_users d
JOIN 
    total_purchase_users t ON d.userid = t.userid;

-- Classify products by popularity based on view counts and select the top 10
SELECT productid,
    COUNT(IF(eventtype = 'product_view', 1, NULL)) AS num_of_view
FROM ecommerce_backup
GROUP BY ProductID 
ORDER BY num_of_view DESC
LIMIT 10;

-- Analyze product conversion rates
SELECT productid,
    COUNT(IF(eventtype = 'product_view', 1, 0)) AS product_view,
    COUNT(IF(eventtype = 'add_to_cart', 1, 0)) AS add_to_cart,
    COUNT(IF(eventtype = 'purchase', 1, 0)) AS purchase,
    COUNT(DISTINCT IF(eventtype = 'purchase', userid, NULL)) / NULLIF(COUNT(DISTINCT userid), 0) AS product_purchase_rate
FROM ecommerce_backup
GROUP BY productid
ORDER BY product_purchase_rate DESC;




-- In this case, some statistical descriptions can also be applied
-- Time-based Analysis: Evaluate trends and patterns over time to identify peak activity periods.
-- Daily activity trend analysis
SELECT 
    DATE(timestamp) AS activity_date,
    COUNT(*) AS total_events,
    COUNT(DISTINCT userid) AS unique_users,
    COUNT(IF(eventtype = 'purchase', 1, NULL)) AS total_purchases
FROM ecommerce_new
GROUP BY activity_date
ORDER BY activity_date;

-- Weekly activity trend analysis
SELECT 
    YEAR(timestamp) AS activity_year,
    WEEK(timestamp) AS activity_week,
    COUNT(*) AS total_events,
    COUNT(DISTINCT userid) AS unique_users,
    COUNT(IF(eventtype = 'purchase', 1, NULL)) AS total_purchases
FROM ecommerce_new
GROUP BY activity_year, activity_week
ORDER BY activity_year, activity_week;

-- Monthly activity trend analysis
SELECT 
    YEAR(timestamp) AS activity_year,
    MONTH(timestamp) AS activity_month,
    COUNT(*) AS total_events,
    COUNT(DISTINCT userid) AS unique_users,
    COUNT(IF(eventtype = 'purchase', 1, NULL)) AS total_purchases
FROM ecommerce_new
GROUP BY activity_year, activity_month
ORDER BY activity_year, activity_month;

-- Frequency distribution of event types
SELECT 
    eventtype,
    COUNT(*) AS event_count,
    (COUNT(*) / (SELECT COUNT(*) FROM ecommerce_backup)) * 100 AS percentage
FROM ecommerce_backup
GROUP BY eventtype
ORDER BY event_count DESC;

-- Summary statistics for Amount and Outcome
-- Summary statistics for Amount and Outcome

-- Total transactions and average, min, max, stddev of Amount and Outcome
SELECT 
    COUNT(*) AS total_transactions,
    AVG(Amount) AS average_amount,
    STDDEV(Amount) AS stddev_amount,
    MIN(Amount) AS min_amount,
    MAX(Amount) AS max_amount,
    AVG(Outcome) AS average_outcome
FROM ecommerce_backup
WHERE Amount IS NOT NULL;


