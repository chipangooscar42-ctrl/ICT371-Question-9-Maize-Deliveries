
/* ============================================================
   ICT371 - ADVANCED DATABASE
   QUESTION 9: FARMER COOPERATIVE MAIZE DELIVERIES

   Student Name: [Enter your full name]
   Student Number: [Enter your student number]

   Complete PostgreSQL implementation.
   ============================================================ */


/* ============================================================
   PART 1: CLEAN UP OLD QUESTION 9 OBJECTS
   ============================================================ */

DROP VIEW IF EXISTS v_farmer_amount_due CASCADE;

DROP TABLE IF EXISTS daily_purchases CASCADE;
DROP TABLE IF EXISTS deliveries CASCADE;
DROP TABLE IF EXISTS farmers CASCADE;


/* ============================================================
   PART 2: CREATE THE REQUIRED TABLES
   ============================================================ */

CREATE TABLE farmers (
    farmer_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    farmer_number VARCHAR(20) NOT NULL UNIQUE,
    full_name VARCHAR(100) NOT NULL
);


CREATE TABLE deliveries (
    delivery_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    farmer_id INTEGER NOT NULL,
    grade VARCHAR(1) NOT NULL,
    weight_kg NUMERIC(12,2) NOT NULL,
    unit_rate NUMERIC(10,2) NOT NULL DEFAULT 0,
    total_value NUMERIC(14,2) NOT NULL DEFAULT 0,
    delivered_on DATE NOT NULL,
    is_paid BOOLEAN NOT NULL DEFAULT FALSE,

    CONSTRAINT fk_delivery_farmer
        FOREIGN KEY (farmer_id)
        REFERENCES farmers(farmer_id),

    CONSTRAINT chk_delivery_grade
        CHECK (grade IN ('A', 'B', 'C')),

    CONSTRAINT chk_delivery_weight
        CHECK (weight_kg > 0),

    CONSTRAINT chk_delivery_rate
        CHECK (unit_rate >= 0),

    CONSTRAINT chk_delivery_total
        CHECK (total_value >= 0)
);


CREATE TABLE daily_purchases (
    purchase_date DATE PRIMARY KEY,
    total_weight NUMERIC(14,2) NOT NULL DEFAULT 0,
    total_value NUMERIC(14,2) NOT NULL DEFAULT 0,

    CONSTRAINT chk_purchase_weight
        CHECK (total_weight >= 0),

    CONSTRAINT chk_purchase_value
        CHECK (total_value >= 0)
);


/* ============================================================
   PART 3: INSERT THREE FARMERS
   ============================================================ */

INSERT INTO farmers (farmer_number, full_name)
VALUES
    ('F001', 'John Banda'),
    ('F002', 'Mary Phiri'),
    ('F003', 'Peter Zulu');


/* Check the farmers */

SELECT *
FROM farmers
ORDER BY farmer_id;


/* ============================================================
   PART 4: CREATE THE MAIZE PRICING FUNCTION

   Grade A = K5 per kg
   Grade B = K4 per kg
   Grade C = K3 per kg
   ============================================================ */

CREATE OR REPLACE FUNCTION fn_maize_rate(
    p_grade VARCHAR
)
RETURNS NUMERIC(10,2)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_grade IS NULL THEN
        RAISE EXCEPTION
            'Maize grade cannot be NULL';
    END IF;

    CASE UPPER(TRIM(p_grade))
        WHEN 'A' THEN
            RETURN 5.00;

        WHEN 'B' THEN
            RETURN 4.00;

        WHEN 'C' THEN
            RETURN 3.00;

        ELSE
            RAISE EXCEPTION
                'Invalid maize grade: %. Grade must be A, B or C',
                p_grade;
    END CASE;
END;
$$;


/* Test the pricing function */

SELECT
    'A' AS grade,
    fn_maize_rate('A') AS rate_per_kg

UNION ALL

SELECT
    'B',
    fn_maize_rate('B')

UNION ALL

SELECT
    'C',
    fn_maize_rate('C');


/* ============================================================
   PART 5: CREATE THE DELIVERY VALIDATION AND PRICING TRIGGER

   This trigger:
   1. Rejects non-positive weights.
   2. Gets the correct grade price from the function.
   3. Calculates total delivery value.
   4. Applies to direct INSERT and UPDATE statements.
   ============================================================ */

CREATE OR REPLACE FUNCTION fn_set_delivery_value()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.weight_kg IS NULL OR NEW.weight_kg <= 0 THEN
        RAISE EXCEPTION
            'Delivery weight must be greater than zero';
    END IF;

    IF NEW.delivered_on IS NULL THEN
        RAISE EXCEPTION
            'Delivery date cannot be NULL';
    END IF;

    NEW.grade := UPPER(TRIM(NEW.grade));

    NEW.unit_rate := fn_maize_rate(NEW.grade);

    NEW.total_value := ROUND(
        NEW.weight_kg * NEW.unit_rate,
        2
    );

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_set_delivery_value
ON deliveries;


CREATE TRIGGER trg_set_delivery_value
BEFORE INSERT OR UPDATE
ON deliveries
FOR EACH ROW
EXECUTE FUNCTION fn_set_delivery_value();


/* ============================================================
   PART 6: CREATE THE DELIVERY RECORDING PROCEDURE

   The procedure validates the farmer and delivery details.
   It inserts the basic delivery information.
   The trigger calculates unit_rate and total_value.
   ============================================================ */

CREATE OR REPLACE PROCEDURE pr_receive_delivery(
    p_farmer_id INTEGER,
    p_grade VARCHAR,
    p_weight NUMERIC,
    p_date DATE
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM farmers
        WHERE farmer_id = p_farmer_id
    ) THEN
        RAISE EXCEPTION
            'Farmer ID % does not exist',
            p_farmer_id;
    END IF;

    IF p_grade IS NULL OR UPPER(TRIM(p_grade))
        NOT IN ('A', 'B', 'C') THEN
        RAISE EXCEPTION
            'Invalid maize grade. Grade must be A, B or C';
    END IF;

    IF p_weight IS NULL OR p_weight <= 0 THEN
        RAISE EXCEPTION
            'Delivery weight must be greater than zero';
    END IF;

    IF p_date IS NULL THEN
        RAISE EXCEPTION
            'Delivery date cannot be NULL';
    END IF;

    INSERT INTO deliveries (
        farmer_id,
        grade,
        weight_kg,
        delivered_on,
        is_paid
    )
    VALUES (
        p_farmer_id,
        UPPER(TRIM(p_grade)),
        p_weight,
        p_date,
        FALSE
    );

END;
$$;


/* ============================================================
   PART 7: INSERT SIX DELIVERIES THROUGH THE PROCEDURE

   All deliveries are dated yesterday so the daily purchase
   summary can demonstrate the previous day's totals.
   ============================================================ */

-- John Banda: Grade A, 100 kg
CALL pr_receive_delivery(
    1, 'A', 100, CURRENT_DATE - 1
);

-- John Banda: Grade B, 50 kg
CALL pr_receive_delivery(
    1, 'B', 50, CURRENT_DATE - 1
);

-- Mary Phiri: Grade B, 80 kg
CALL pr_receive_delivery(
    2, 'B', 80, CURRENT_DATE - 1
);

-- Mary Phiri: Grade C, 100 kg
CALL pr_receive_delivery(
    2, 'C', 100, CURRENT_DATE - 1
);

-- Peter Zulu: Grade C, 60 kg
CALL pr_receive_delivery(
    3, 'C', 60, CURRENT_DATE - 1
);

-- Peter Zulu: Grade A, 40 kg
CALL pr_receive_delivery(
    3, 'A', 40, CURRENT_DATE - 1
);


/* ============================================================
   PART 8: UPDATE PAYMENT STATUS

   Mark three deliveries as paid.
   The other three remain unpaid.
   ============================================================ */

UPDATE deliveries
SET is_paid = TRUE
WHERE delivery_id IN (1, 4, 6);


/* Check all deliveries and calculated values */

SELECT
    d.delivery_id,
    f.farmer_number,
    f.full_name,
    d.grade,
    d.weight_kg,
    d.unit_rate,
    d.total_value,
    d.delivered_on,
    d.is_paid
FROM deliveries d
JOIN farmers f
    ON d.farmer_id = f.farmer_id
ORDER BY d.delivery_id;


/* ============================================================
   PART 9: CREATE THE FARMER AMOUNT DUE VIEW

   Include every farmer, even if they have no unpaid
   deliveries. Such farmers must show zero amount due.
   ============================================================ */

CREATE OR REPLACE VIEW v_farmer_amount_due AS
SELECT
    f.farmer_number,
    f.full_name,
    COALESCE(
        SUM(
            CASE
                WHEN d.is_paid = FALSE
                THEN d.total_value
                ELSE 0
            END
        ),
        0
    ) AS total_amount_due
FROM farmers f
LEFT JOIN deliveries d
    ON f.farmer_id = d.farmer_id
GROUP BY
    f.farmer_id,
    f.farmer_number,
    f.full_name;


/* Display amounts owed to farmers */

SELECT *
FROM v_farmer_amount_due
ORDER BY farmer_number;


/* ============================================================
   PART 10: CREATE THE INDEX FOR FARMER DELIVERY HISTORY

   The index supports searching deliveries for one farmer
   within a date range.
   ============================================================ */

CREATE INDEX IF NOT EXISTS idx_deliveries_farmer_date
ON deliveries (farmer_id, delivered_on);


/* Matching query */

SELECT
    delivery_id,
    farmer_id,
    grade,
    weight_kg,
    total_value,
    delivered_on
FROM deliveries
WHERE farmer_id = 1
  AND delivered_on BETWEEN CURRENT_DATE - 30 AND CURRENT_DATE
ORDER BY delivered_on;


/* EXPLAIN query plan */

EXPLAIN
SELECT
    delivery_id,
    farmer_id,
    grade,
    weight_kg,
    total_value,
    delivered_on
FROM deliveries
WHERE farmer_id = 1
  AND delivered_on BETWEEN CURRENT_DATE - 30 AND CURRENT_DATE
ORDER BY delivered_on;


/* ============================================================
   PART 11: CREATE THE DAILY PURCHASE REFRESH PROCEDURE

   The procedure stores the total weight and total value
   purchased on a specified date.

   ON CONFLICT replaces that date's totals when rerun.
   ============================================================ */

CREATE OR REPLACE PROCEDURE pr_refresh_purchases(
    p_day DATE
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_total_weight NUMERIC(14,2);
    v_total_value NUMERIC(14,2);
BEGIN
    IF p_day IS NULL THEN
        RAISE EXCEPTION
            'Purchase date cannot be NULL';
    END IF;

    SELECT
        COALESCE(SUM(weight_kg), 0),
        COALESCE(SUM(total_value), 0)
    INTO
        v_total_weight,
        v_total_value
    FROM deliveries
    WHERE delivered_on = p_day;

    INSERT INTO daily_purchases (
        purchase_date,
        total_weight,
        total_value
    )
    VALUES (
        p_day,
        v_total_weight,
        v_total_value
    )
    ON CONFLICT (purchase_date)
    DO UPDATE SET
        total_weight = EXCLUDED.total_weight,
        total_value = EXCLUDED.total_value;

END;
$$;


/* Run the procedure for yesterday */

CALL pr_refresh_purchases(CURRENT_DATE - 1);


/* Display the daily purchase summary */

SELECT *
FROM daily_purchases
ORDER BY purchase_date;


/* ============================================================
   PART 12: TEST THAT RERUNNING DOES NOT DUPLICATE TOTALS
   ============================================================ */

CALL pr_refresh_purchases(CURRENT_DATE - 1);

SELECT *
FROM daily_purchases
WHERE purchase_date = CURRENT_DATE - 1;


/* ============================================================
   PART 13: SCHEDULE THE DAILY JOB AT 01:30

   The job refreshes the previous day's purchase totals.
   pg_cron must be installed and configured by the server.
   ============================================================ */

DO $$
BEGIN
    EXECUTE 'CREATE EXTENSION IF NOT EXISTS pg_cron';

    EXECUTE $schedule$
        SELECT cron.unschedule(jobid)
        FROM cron.job
        WHERE jobname = 'ict371_daily_purchases'
    $schedule$;

    EXECUTE $schedule$
        SELECT cron.schedule(
            'ict371_daily_purchases',
            '30 1 * * *',
            'CALL pr_refresh_purchases(CURRENT_DATE - 1);'
        )
    $schedule$;

    RAISE NOTICE
        'Daily purchase job scheduled for 01:30';

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE
            'Automatic scheduling was not configured: %',
            SQLERRM;
END;
$$;


/* ============================================================
   PART 14: FINAL VERIFICATION QUERIES
   ============================================================ */


/* 1. Confirm the number of farmers */

SELECT COUNT(*) AS total_farmers
FROM farmers;


/* 2. Confirm the number of deliveries */

SELECT COUNT(*) AS total_deliveries
FROM deliveries;


/* 3. Display all farmers */

SELECT *
FROM farmers
ORDER BY farmer_id;


/* 4. Display all deliveries with calculated values */

SELECT
    f.full_name,
    d.grade,
    d.weight_kg,
    d.unit_rate,
    d.total_value,
    d.delivered_on,
    d.is_paid
FROM deliveries d
JOIN farmers f
    ON d.farmer_id = f.farmer_id
ORDER BY d.delivery_id;


/* 5. Display the amount due to each farmer */

SELECT *
FROM v_farmer_amount_due
ORDER BY farmer_number;


/* 6. Display the daily purchase totals */

SELECT *
FROM daily_purchases
ORDER BY purchase_date;


/* 7. Confirm the index exists */

SELECT
    indexname,
    indexdef
FROM pg_indexes
WHERE tablename = 'deliveries';


/* 8. Confirm the trigger exists */

SELECT
    trigger_name,
    event_manipulation,
    action_timing
FROM information_schema.triggers
WHERE event_object_table = 'deliveries';


/* 9. Confirm the function and procedures exist */

SELECT
    routine_name,
    routine_type
FROM information_schema.routines
WHERE routine_name IN (
    'fn_maize_rate',
    'fn_set_delivery_value',
    'pr_receive_delivery',
    'pr_refresh_purchases'
)
ORDER BY routine_name;
