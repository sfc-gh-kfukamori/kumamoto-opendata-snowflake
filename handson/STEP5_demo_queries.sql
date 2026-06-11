-- ============================================================
-- Snowflake Intelligence Hands-on Lab
-- STEP 5: 動作確認・デモクエリ
-- ============================================================
--
-- 【このステップでやること】
--   1. Snowflake Intelligence（Cortex Analyst UI）での動作確認方法を確認
--   2. SQL で直接動作確認できるサンプルクエリを実行
--
-- 【前提条件】
--   - STEP1〜STEP4 がすべて完了していること
-- 【実行ロール】
--   - ACCOUNTADMIN または SYSADMIN
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;


-- ============================================================
-- STEP 5-1: Snowflake Intelligence での確認方法
-- ============================================================
-- 以下の手順で自然言語問い合わせを試してください:
--
--   1. Snowsight の左メニュー下部「Intelligence」をクリック
--   2. 「熊本市統計アナリスト」の Agent が表示されることを確認
--   3. Agent をクリックして会話を開始
--   4. 下記のサンプル質問を入力するか、画面上のサンプル質問をクリック
--
-- 【試してほしいサンプル質問】
--   単一テーブル:
--     "熊本市の月次推計人口の推移を教えて"
--     "熊本市電の年度別乗車人数と収入はどのくらいか"
--     "熊本市の有効求人倍率の最近の推移を見せて"
--     "熊本市の月次ごみ収集量の推移を教えて"
--
--   複数テーブル横断（より高度な分析）:
--     "熊本市の人口・出生数・死亡数を月次で一覧表示して"
--     "熊本市電の乗車人数と熊本空港の乗降客数を月次で比較して"
--     "熊本市の火災件数と交通事故件数を年次で比較して"
--     "博物館と動植物園の年間入館者数を年度別に比較して"
--     "熊本市の人口とごみ収集量の年次推移を合わせて見せて"


-- ============================================================
-- STEP 5-2: SQL でのデータ確認
-- ============================================================
-- Snowflake Intelligence を使う前に、データが正しく入っているかを
-- SQL で直接確認できます。

-- ① 作成されたテーブルの一覧と行数確認
SELECT
    t.TABLE_NAME,
    t.COMMENT AS テーブル説明,
    d.ROW_COUNT AS 行数
FROM KUMAMOTO_OPENDATA.INFORMATION_SCHEMA.TABLES t
LEFT JOIN KUMAMOTO_OPENDATA.PUBLIC.DATASET_CATALOG d
    ON t.TABLE_NAME = d.TABLE_NAME
WHERE t.TABLE_SCHEMA = 'PUBLIC'
  AND t.TABLE_TYPE   = 'BASE TABLE'
  AND t.TABLE_NAME  != 'DATASET_CATALOG'
ORDER BY t.TABLE_NAME;


-- ============================================================
-- 【単一テーブルクエリ例】
-- ============================================================

-- ② 熊本市の月次推計人口（直近 24 ヶ月）
SELECT
    "年次",
    "月次",
    "人数【人】"::INT AS 推計人口
FROM KUMAMOTO_OPENDATA.PUBLIC.T02031_POPULATION_MONTHLY
WHERE "性別" = '総数'       -- '総数'=合計、'男'=男性、'女'=女性
ORDER BY "年次" DESC, "月次" DESC
LIMIT 24;


-- ③ 熊本市電の年度別乗車人数と収入
SELECT
    "年度",
    SUM("乗車人数【人】"::INT) AS 年間乗車人数,
    SUM("乗車料収入【円】"::INT) AS 年間乗車料収入
FROM KUMAMOTO_OPENDATA.PUBLIC.T11051_TRAM_RIDERSHIP_REVENUE_MONTHLY
WHERE "総数/定期/定期外" = '総数'   -- '総数'=合計、'定期'=定期客、'定期外'=定期外客
GROUP BY "年度"
ORDER BY "年度" DESC;


-- ④ 熊本市の有効求人倍率の推移
SELECT
    "年度",
    "年月",
    "比率"::FLOAT AS 有効求人倍率
FROM KUMAMOTO_OPENDATA.PUBLIC.T12055_JOB_VACANCY_RATE_MONTHLY
WHERE "種別" = '有効求人倍率'   -- 注意: '有効求人倍率（季節調整値）' ではなく '有効求人倍率'
ORDER BY "年度" DESC, "年月" DESC
LIMIT 24;


-- ⑤ 熊本市の月次ごみ収集量
SELECT
    "年度",
    "月次",
    SUM("数量【t】"::FLOAT) AS ごみ収集量_t
FROM KUMAMOTO_OPENDATA.PUBLIC.T13180_WASTE_PROCESSING_MONTHLY
WHERE "収集および搬入量/処理量" = '収集および搬入量'  -- 収集量のみ
GROUP BY "年度", "月次"
ORDER BY "年度" DESC, "月次" DESC
LIMIT 24;


-- ============================================================
-- 【複数テーブル横断クエリ例】
-- ============================================================

-- ⑥ 人口 × 出生数 × 死亡数（月次）
SELECT
    p."年次",
    p."月次",
    MAX(CASE WHEN p."性別" = '総数' THEN p."人数【人】"::INT END)  AS 推計人口,
    SUM(CASE WHEN bd."種別" = '出生' AND bd."性別" = '総数'
             THEN bd."人数【人】"::INT ELSE 0 END)                 AS 出生数,
    SUM(CASE WHEN bd."種別" = '死亡' AND bd."性別" = '総数'
             THEN bd."人数【人】"::INT ELSE 0 END)                 AS 死亡数
FROM KUMAMOTO_OPENDATA.PUBLIC.T02031_POPULATION_MONTHLY p
LEFT JOIN KUMAMOTO_OPENDATA.PUBLIC.T02040_BIRTHS_DEATHS_MONTHLY bd
    ON p."年次" = bd."年次" AND p."月次" = bd."月次"
WHERE p."性別" = '総数'
GROUP BY p."年次", p."月次"
ORDER BY p."年次" DESC, p."月次" DESC
LIMIT 24;


-- ⑦ 市電乗車人数 × 空港乗降客数（月次比較）
SELECT
    t."年度",
    t."月次",
    SUM(CASE WHEN t."総数/定期/定期外" = '総数'
             THEN t."乗車人数【人】"::INT ELSE 0 END) AS 市電乗車人数,
    SUM(a."人数【人】"::INT)                          AS 空港乗降客数
FROM KUMAMOTO_OPENDATA.PUBLIC.T11051_TRAM_RIDERSHIP_REVENUE_MONTHLY t
LEFT JOIN KUMAMOTO_OPENDATA.PUBLIC.T11031_AIRPORT_PASSENGERS_MONTHLY a
    ON t."年度" = a."年度" AND t."月次" = a."月次"
GROUP BY t."年度", t."月次"
ORDER BY t."年度" DESC, t."月次" DESC
LIMIT 24;


-- ⑧ 火災件数 × 交通事故件数（年次比較）
SELECT
    f."年次",
    SUM(f."件数"::INT)                            AS 火災件数合計,
    SUM(CASE WHEN t."件数/死者/傷者" = '件数'
             THEN t."件数【件】・人数【人】"::INT
             ELSE 0 END)                          AS 交通事故件数
FROM KUMAMOTO_OPENDATA.PUBLIC.T15191_FIRE_INCIDENTS_DAMAGE f
LEFT JOIN KUMAMOTO_OPENDATA.PUBLIC.T15120_TRAFFIC_ACCIDENTS_BY_STATION t
    ON f."年次" = t."年次" AND f."月次" = t."月次"
GROUP BY f."年次"
ORDER BY f."年次" DESC;


-- ⑨ 博物館 × 動植物園（年度別入館者比較）
SELECT
    m."年度",
    SUM(m."人数【人】"::INT)              AS 博物館年間入館者数,
    SUM(z."入園者総数【人】"::INT)        AS 動植物園年間入園者数
FROM KUMAMOTO_OPENDATA.PUBLIC.T18172_MUSEUM_VISITORS_MONTHLY m
LEFT JOIN KUMAMOTO_OPENDATA.PUBLIC.T18201_ZOO_MONTHLY_OVERVIEW z
    ON m."年度" = z."年度" AND m."月次" = z."月次"
GROUP BY m."年度"
ORDER BY m."年度" DESC;


-- ⑩ 人口 × ごみ収集量（年次の関係）
SELECT
    pop."年次",
    SUM(CASE WHEN pop."性別" = '総数'
             THEN pop."人数【人】"::INT ELSE 0 END) / 12  AS 月平均推計人口,
    SUM(CASE WHEN waste."収集および搬入量/処理量" = '収集および搬入量'
             THEN waste."数量【t】"::FLOAT ELSE 0 END)    AS 年間ごみ収集量_t
FROM KUMAMOTO_OPENDATA.PUBLIC.T02031_POPULATION_MONTHLY pop
LEFT JOIN KUMAMOTO_OPENDATA.PUBLIC.T13180_WASTE_PROCESSING_MONTHLY waste
    ON pop."年次" = waste."年度" AND pop."月次" = waste."月次"
GROUP BY pop."年次"
ORDER BY pop."年次" DESC;


-- ============================================================
-- STEP 5 完了 / ハンズオン完了
-- ============================================================
-- ✅ データ確認クエリの実行完了
--
-- 【ハンズオン全体のまとめ】
--   STEP1: インフラ設定（DB / Network Rule / External Access）
--   STEP2: データ取込（CKAN API → Snowflake 92 テーブル）
--   STEP3: Semantic View 作成（自然言語理解のためのメタデータ）
--   STEP4: Cortex Agent 作成（Snowflake Intelligence に表示）
--   STEP5: 動作確認（SQL クエリ）
--
-- 【作成したオブジェクト一覧】
--   データベース : KUMAMOTO_OPENDATA
--   テーブル     : 92 テーブル（熊本市統計データ）+ DATASET_CATALOG
--   Semantic View: KUMAMOTO_CITY_STATISTICS
--   Cortex Agent : KUMAMOTO_CITY_STATS_AGENT（表示名: 熊本市統計アナリスト）
--
-- Snowflake Intelligence から「熊本市統計アナリスト」を開いて
-- 自由に自然言語で問い合わせをお試しください！
-- ============================================================
