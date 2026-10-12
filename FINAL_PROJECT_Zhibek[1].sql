create DATABASE Customers_transaction;
UPDATE customers SET Gender = NULL WHERE Gender ='';
UPDATE customers SET Age = NULL WHERE Age ='';
ALTER TABLE customers MODIFY Age INT NULL;

SELECT * FROM customers;

CREATE TABLE transactions
(date_new DATE,
Id_check INT,
ID_client INT,
Count_products DECIMAL (10,3),
Sum_payment DECIMAL (10,2));

LOAD DATA INFILE "C:\\ProgramData\\MySQL\\MySQL Server 8.0\\Uploads\\TRANSACTIONS_FINAL.csv"
INTO TABLE transactions
FIELDS TERMINATED BY ','
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SHOW variables like 'secure_file_priv';
SELECT * FROM transactions;

SELECT VERSION();

### Tранзакции по месяцам
WITH monthly_tx AS (
    SELECT
        ID_client,
        DATE_FORMAT(date_new, '%Y-%m') AS year_months
    FROM transactions
    WHERE date_new BETWEEN '2015-06-01' AND '2016-05-31'
    GROUP BY ID_client, DATE_FORMAT(date_new, '%Y-%m')
),

### Клиенты с непрерывной историей - транзакции каждый месяц
clients_with_full_history AS (
    SELECT
        ID_client
    FROM (
        SELECT
            ID_client,
            year_months
        FROM monthly_tx
    ) AS sub_months
    GROUP BY ID_client
    HAVING COUNT(DISTINCT year_months) = 12
),


### Расчёты по клиентам
final_result AS (
    SELECT
        t.ID_client,
        COUNT(t.Id_check) AS total_transactions,
        ROUND(SUM(t.Sum_payment), 2) AS total_payment,
        ROUND(SUM(t.Sum_payment) / COUNT(t.Id_check), 2) AS avg_check,
        ROUND(SUM(t.Sum_payment) / 12, 2) AS avg_monthly_payment
    FROM transactions t
    JOIN clients_with_full_history f ON t.ID_client = f.ID_client
    WHERE t.date_new BETWEEN '2015-06-01' AND '2016-05-31'
    GROUP BY t.ID_client
)


### Вывод результата
SELECT * FROM final_result;

### Возрастные группы клиентов
WITH tx AS (
    SELECT
        t.ID_client,
        DATE_FORMAT(t.date_new, '%Y-%m') AS year_months,
        t.Sum_payment,
        c.Gender
    FROM transactions t
    JOIN customers c ON t.ID_client = c.ID_client
    WHERE t.date_new BETWEEN '2015-06-01' AND '2016-05-31'
),

monthly_base AS (
    SELECT
        year_months,
        COUNT(*) AS total_transactions,
        SUM(Sum_payment) AS total_sum,
        COUNT(DISTINCT ID_client) AS active_clients,
        AVG(Sum_payment) AS avg_check
    FROM tx
    GROUP BY year_months
),

gender_stats AS (
    SELECT
        year_months,
        Gender,
        COUNT(*) AS gender_transactions,
        SUM(Sum_payment) AS gender_sum
    FROM tx
    GROUP BY year_months, Gender
),

year_totals AS (
    SELECT
        COUNT(*) AS year_total_transactions,
        SUM(Sum_payment) AS year_total_sum
    FROM tx
),

final AS (
    SELECT
        m.year_months,
        ROUND(m.avg_check, 2) AS avg_check,
        m.total_transactions,
        m.total_sum,
        m.active_clients,
        ROUND(m.total_transactions / 12, 2) AS avg_tx_per_month,
        ROUND(m.active_clients / 12, 2) AS avg_clients_per_month,
        ROUND(m.total_transactions / y.year_total_transactions * 100, 2) AS tx_share_percent,
        ROUND(m.total_sum / y.year_total_sum * 100, 2) AS sum_share_percent
    FROM monthly_base m
    CROSS JOIN year_totals y
)

SELECT
    f.year_months,
    f.avg_check,
    f.total_transactions,
    f.active_clients,
    f.tx_share_percent,
    f.sum_share_percent,

   ### % по количеству операций
    ROUND(SUM(CASE WHEN g.Gender = 'M' THEN g.gender_transactions ELSE 0 END) / f.total_transactions * 100, 2) AS male_tx_percent,
    ROUND(SUM(CASE WHEN g.Gender = 'F' THEN g.gender_transactions ELSE 0 END) / f.total_transactions * 100, 2) AS female_tx_percent,
    ROUND(SUM(CASE WHEN g.Gender = 'NA' THEN g.gender_transactions ELSE 0 END) / f.total_transactions * 100, 2) AS na_tx_percent,

   ### % по сумме операций
    ROUND(SUM(CASE WHEN g.Gender = 'M' THEN g.gender_sum ELSE 0 END) / f.total_sum * 100, 2) AS male_sum_percent,
    ROUND(SUM(CASE WHEN g.Gender = 'F' THEN g.gender_sum ELSE 0 END) / f.total_sum * 100, 2) AS female_sum_percent,
    ROUND(SUM(CASE WHEN g.Gender = 'NA' THEN g.gender_sum ELSE 0 END) / f.total_sum * 100, 2) AS na_sum_percent

FROM final f
LEFT JOIN gender_stats g ON f.year_months = g.year_months
GROUP BY f.year_months, f.avg_check, f.total_transactions, f.total_sum,
         f.active_clients, f.tx_share_percent, f.sum_share_percent
ORDER BY f.year_months;

WITH clients_age_grouped AS (
    SELECT
        c.ID_client,
        CASE
            WHEN c.birth_date IS NULL THEN 'Unknown'
            WHEN TIMESTAMPDIFF(YEAR, c.birth_date, '2016-06-01') < 20 THEN '10-19'
            WHEN TIMESTAMPDIFF(YEAR, c.birth_date, '2016-06-01') BETWEEN 20 AND 29 THEN '20-29'
            WHEN TIMESTAMPDIFF(YEAR, c.birth_date, '2016-06-01') BETWEEN 30 AND 39 THEN '30-39'
            WHEN TIMESTAMPDIFF(YEAR, c.birth_date, '2016-06-01') BETWEEN 40 AND 49 THEN '40-49'
            WHEN TIMESTAMPDIFF(YEAR, c.birth_date, '2016-06-01') BETWEEN 50 AND 59 THEN '50-59'
            ELSE '60+'
        END AS age_group
    FROM customers c
),

tx_with_age AS (
    SELECT
        t.ID_client,
        DATE_FORMAT(t.date_new, '%Y-%m') AS year_months,
        QUARTER(t.date_new) AS quarter,
        YEAR(t.date_new) AS year,
        t.Sum_payment,
        a.age_group
    FROM transactions t
    JOIN clients_age_grouped a ON t.ID_client = a.ID_client
    WHERE t.date_new BETWEEN '2015-06-01' AND '2016-05-31'
),

total_stats AS (
    SELECT
        age_group,
        COUNT(*) AS total_transactions,
        SUM(Sum_payment) AS total_sum
    FROM tx_with_age
    GROUP BY age_group
),

quarterly_stats AS (
    SELECT
        age_group,
        CONCAT(year, '-Q', quarter) AS quarter_label,
        COUNT(*) AS tx_count,
        SUM(Sum_payment) AS sum_total,
        ROUND(AVG(Sum_payment), 2) AS avg_sum,
        COUNT(DISTINCT ID_client) AS active_clients
    FROM tx_with_age
    GROUP BY age_group, year, quarter
),

quarter_totals AS (
    SELECT
        CONCAT(year, '-Q', quarter) AS quarter_label,
        COUNT(*) AS total_tx_quarter,
        SUM(Sum_payment) AS total_sum_quarter
    FROM tx_with_age
    GROUP BY year, quarter
)

###  Квартальная разбивка по возрастным группам + % от квартала
SELECT
    q.age_group,
    q.quarter_label,
    q.tx_count,
    q.sum_total,
    q.avg_sum,
    ROUND(q.tx_count / qt.total_tx_quarter * 100, 2) AS tx_share_percent,
    ROUND(q.sum_total / qt.total_sum_quarter * 100, 2) AS sum_share_percent
FROM quarterly_stats q
JOIN quarter_totals qt ON q.quarter_label = qt.quarter_label
ORDER BY q.quarter_label, q.age_group;

