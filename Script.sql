CREATE TABLE IF NOT EXISTS dm.dm_f101_round_f (
    FROM_DATE          DATE,
    TO_DATE            DATE,
    CHAPTER            CHAR(1),
    LEDGER_ACCOUNT     CHAR(5),
    CHARACTERISTIC     CHAR(1),
    BALANCE_IN_RUB     NUMERIC(23,8),
    R_BALANCE_IN_RUB   NUMERIC(23,8),
    BALANCE_IN_VAL     NUMERIC(23,8),
    R_BALANCE_IN_VAL   NUMERIC(23,8),
    BALANCE_IN_TOTAL   NUMERIC(23,8),
    R_BALANCE_IN_TOTAL NUMERIC(23,8),
    TURN_DEB_RUB       NUMERIC(23,8),
    R_TURN_DEB_RUB     NUMERIC(23,8),
    TURN_DEB_VAL       NUMERIC(23,8),
    R_TURN_DEB_VAL     NUMERIC(23,8),
    TURN_DEB_TOTAL     NUMERIC(23,8),
    R_TURN_DEB_TOTAL   NUMERIC(23,8),
    TURN_CRE_RUB       NUMERIC(23,8),
    R_TURN_CRE_RUB     NUMERIC(23,8),
    TURN_CRE_VAL       NUMERIC(23,8),
    R_TURN_CRE_VAL     NUMERIC(23,8),
    TURN_CRE_TOTAL     NUMERIC(23,8),
    R_TURN_CRE_TOTAL   NUMERIC(23,8),
    BALANCE_OUT_RUB    NUMERIC(23,8),
    R_BALANCE_OUT_RUB  NUMERIC(23,8),
    BALANCE_OUT_VAL    NUMERIC(23,8),
    R_BALANCE_OUT_VAL  NUMERIC(23,8),
    BALANCE_OUT_TOTAL  NUMERIC(23,8),
    R_BALANCE_OUT_TOTAL NUMERIC(23,8)
);

CREATE OR REPLACE FUNCTION dm.fill_f101_round_f(i_OnDate DATE)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_start_time   TIMESTAMP;
    v_end_time     TIMESTAMP;
    v_rows         INT;
    v_FROM_DATE    DATE;
    v_TO_DATE      DATE;
BEGIN
    v_start_time := clock_timestamp();
    v_FROM_DATE := date_trunc('month', i_OnDate) - INTERVAL '1 month';  -- первый день предыдущего месяца
    v_TO_DATE   := i_OnDate - INTERVAL '1 day';                        -- последний день предыдущего месяца

    -- Логируем старт
    INSERT INTO logs.etl_log (process_name, start_time, status, message)
    VALUES ('FILL_F101_ROUND', v_start_time, 'STARTED', 
            'i_OnDate=' || i_OnDate::TEXT || ', period: ' || v_FROM_DATE::TEXT || ' - ' || v_TO_DATE::TEXT);

    -- Удаляем старые записи за этот период (для возможности перезапуска)
    DELETE FROM dm.dm_f101_round_f
    WHERE FROM_DATE = v_FROM_DATE AND TO_DATE = v_TO_DATE;

    -- Основной INSERT
    INSERT INTO dm.dm_f101_round_f (
        FROM_DATE, TO_DATE, CHAPTER, LEDGER_ACCOUNT, CHARACTERISTIC,
        BALANCE_IN_RUB, R_BALANCE_IN_RUB,
        BALANCE_IN_VAL, R_BALANCE_IN_VAL,
        BALANCE_IN_TOTAL, R_BALANCE_IN_TOTAL,
        TURN_DEB_RUB, R_TURN_DEB_RUB,
        TURN_DEB_VAL, R_TURN_DEB_VAL,
        TURN_DEB_TOTAL, R_TURN_DEB_TOTAL,
        TURN_CRE_RUB, R_TURN_CRE_RUB,
        TURN_CRE_VAL, R_TURN_CRE_VAL,
        TURN_CRE_TOTAL, R_TURN_CRE_TOTAL,
        BALANCE_OUT_RUB, R_BALANCE_OUT_RUB,
        BALANCE_OUT_VAL, R_BALANCE_OUT_VAL,
        BALANCE_OUT_TOTAL, R_BALANCE_OUT_TOTAL
    )
    SELECT
        v_FROM_DATE,
        v_TO_DATE,
        ls.CHAPTER,
        CAST(LEFT(act.account_number, 5) AS CHAR(5)) AS LEDGER_ACCOUNT,
        act.char_type AS CHARACTERISTIC,

        -- Входящие остатки в рублях
        SUM(CASE WHEN act.is_rub THEN COALESCE(bal_in.balance_out_rub, 0) ELSE 0 END) AS BALANCE_IN_RUB,
        SUM(CASE WHEN act.is_rub THEN COALESCE(bal_in.balance_out, 0) ELSE 0 END) AS R_BALANCE_IN_RUB,

        -- Входящие остатки по валютным счетам (в рублях и в валюте)
        SUM(CASE WHEN NOT act.is_rub THEN COALESCE(bal_in.balance_out_rub, 0) ELSE 0 END) AS BALANCE_IN_VAL,
        SUM(CASE WHEN NOT act.is_rub THEN COALESCE(bal_in.balance_out, 0) ELSE 0 END) AS R_BALANCE_IN_VAL,

        -- Входящие остатки итого
        SUM(COALESCE(bal_in.balance_out_rub, 0)) AS BALANCE_IN_TOTAL,
        SUM(COALESCE(bal_in.balance_out, 0))    AS R_BALANCE_IN_TOTAL,

        -- Дебетовые обороты за период
        SUM(CASE WHEN act.is_rub THEN COALESCE(turn.deb_rub, 0) ELSE 0 END) AS TURN_DEB_RUB,
        SUM(CASE WHEN act.is_rub THEN COALESCE(turn.deb_val, 0) ELSE 0 END) AS R_TURN_DEB_RUB,

        SUM(CASE WHEN NOT act.is_rub THEN COALESCE(turn.deb_rub, 0) ELSE 0 END) AS TURN_DEB_VAL,
        SUM(CASE WHEN NOT act.is_rub THEN COALESCE(turn.deb_val, 0) ELSE 0 END) AS R_TURN_DEB_VAL,

        SUM(COALESCE(turn.deb_rub, 0)) AS TURN_DEB_TOTAL,
        SUM(COALESCE(turn.deb_val, 0)) AS R_TURN_DEB_TOTAL,

        -- Кредитовые обороты за период
        SUM(CASE WHEN act.is_rub THEN COALESCE(turn.cre_rub, 0) ELSE 0 END) AS TURN_CRE_RUB,
        SUM(CASE WHEN act.is_rub THEN COALESCE(turn.cre_val, 0) ELSE 0 END) AS R_TURN_CRE_RUB,

        SUM(CASE WHEN NOT act.is_rub THEN COALESCE(turn.cre_rub, 0) ELSE 0 END) AS TURN_CRE_VAL,
        SUM(CASE WHEN NOT act.is_rub THEN COALESCE(turn.cre_val, 0) ELSE 0 END) AS R_TURN_CRE_VAL,

        SUM(COALESCE(turn.cre_rub, 0)) AS TURN_CRE_TOTAL,
        SUM(COALESCE(turn.cre_val, 0)) AS R_TURN_CRE_TOTAL,

        -- Исходящие остатки в рублях
        SUM(CASE WHEN act.is_rub THEN COALESCE(bal_out.balance_out_rub, 0) ELSE 0 END) AS BALANCE_OUT_RUB,
        SUM(CASE WHEN act.is_rub THEN COALESCE(bal_out.balance_out, 0) ELSE 0 END) AS R_BALANCE_OUT_RUB,

        -- Исходящие остатки по валютным счетам
        SUM(CASE WHEN NOT act.is_rub THEN COALESCE(bal_out.balance_out_rub, 0) ELSE 0 END) AS BALANCE_OUT_VAL,
        SUM(CASE WHEN NOT act.is_rub THEN COALESCE(bal_out.balance_out, 0) ELSE 0 END) AS R_BALANCE_OUT_VAL,

        -- Исходящие остатки итого
        SUM(COALESCE(bal_out.balance_out_rub, 0)) AS BALANCE_OUT_TOTAL,
        SUM(COALESCE(bal_out.balance_out, 0))    AS R_BALANCE_OUT_TOTAL

    FROM
        (
            -- Список счетов, действовавших в отчётном периоде,
            -- с их актуальными атрибутами
            SELECT DISTINCT ON (account_rk)
                account_rk,
                account_number,
                char_type,
                currency_code,
                (currency_code IN ('810', '643')) AS is_rub
            FROM ds.md_account_d
            WHERE data_actual_date <= v_TO_DATE
              AND data_actual_end_date >= v_FROM_DATE
            ORDER BY account_rk, data_actual_date DESC   -- берём наиболее позднюю запись
        ) act

        -- Справочник балансовых счетов второго порядка
        LEFT JOIN ds.md_ledger_account_s ls
            ON ls.ledger_account = CAST(LEFT(act.account_number, 5) AS INTEGER)
            AND v_TO_DATE BETWEEN ls.start_date AND COALESCE(ls.end_date, '2050-12-31')

        -- Остатки на начало периода (31.12 пред. года)
        LEFT JOIN dm.dm_account_balance_f bal_in
            ON bal_in.account_rk = act.account_rk
            AND bal_in.on_date = v_FROM_DATE - INTERVAL '1 day'

        -- Остатки на конец периода
        LEFT JOIN dm.dm_account_balance_f bal_out
            ON bal_out.account_rk = act.account_rk
            AND bal_out.on_date = v_TO_DATE

        -- Обороты за период (агрегированные по счёту)
        LEFT JOIN (
            SELECT
                account_rk,
                SUM(debet_amount_rub) AS deb_rub,
                SUM(debet_amount)     AS deb_val,
                SUM(credit_amount_rub) AS cre_rub,
                SUM(credit_amount)     AS cre_val
            FROM dm.dm_account_turnover_f
            WHERE on_date BETWEEN v_FROM_DATE AND v_TO_DATE
            GROUP BY account_rk
        ) turn ON turn.account_rk = act.account_rk

    GROUP BY
        ls.CHAPTER,
        CAST(LEFT(act.account_number, 5) AS CHAR(5)),
        act.char_type;

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    v_end_time := clock_timestamp();

    INSERT INTO logs.etl_log (process_name, start_time, end_time, status, rows_processed, message)
    VALUES ('FILL_F101_ROUND', v_start_time, v_end_time, 'SUCCESS', v_rows,
            'i_OnDate=' || i_OnDate::TEXT || ', rows=' || v_rows);

END;
$$;

SELECT * FROM dm.dm_f101_round_f;

