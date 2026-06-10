-- =============================================================================
-- 04_run_demo.sql
--
-- 概要: エンドツーエンドのデモ実行スクリプト
--   以下の 3 ステップを順に実行することで、CKAN API からのデータ取込から
--   AI による日本語 Description 生成まで一連の流れを確認できる。
--
-- 前提: 01_setup.sql, 02_ingest_sproc.sql, 03_ai_desc_sproc.sql が実行済み
-- =============================================================================

-- =============================================================================
-- Step 1: データ取込
--   熊本市オープンデータカタログ (data.bodik.jp) の CKAN API から
--   CSV データを取得し、KUMAMOTO_OPENDATA.PUBLIC に 92 テーブルを作成する。
--   ※ 実行時間の目安: 約 5 分 (XSmall WH)
-- =============================================================================
CALL KUMAMOTO_OPENDATA.PUBLIC.INGEST_KUMAMOTO_OPENDATA();

-- 取込結果の確認
SELECT
    INGEST_STATUS,
    COUNT(*)    AS CNT,
    SUM(ROW_COUNT::INT) AS TOTAL_ROWS
FROM KUMAMOTO_OPENDATA.PUBLIC.DATASET_CATALOG
GROUP BY INGEST_STATUS
ORDER BY INGEST_STATUS;

-- データセットカタログの内容を確認
SELECT
    TABLE_NAME,
    PACKAGE_TITLE,
    INGEST_STATUS,
    ROW_COUNT
FROM KUMAMOTO_OPENDATA.PUBLIC.DATASET_CATALOG
ORDER BY TABLE_NAME
LIMIT 20;

-- 作成されたテーブルの一覧を確認
SHOW TABLES IN SCHEMA KUMAMOTO_OPENDATA.PUBLIC;

-- サンプルデータの確認: 熊本市電月次乗車人数
SELECT *
FROM KUMAMOTO_OPENDATA.PUBLIC.T11051_TRAM_RIDERSHIP_REVENUE_MONTHLY
LIMIT 10;

-- サンプルデータの確認: 月次推計人口
SELECT *
FROM KUMAMOTO_OPENDATA.PUBLIC.T02031_POPULATION_MONTHLY
WHERE "年度" = '2023'
ORDER BY "月次"
LIMIT 12;


-- =============================================================================
-- Step 2: AI 説明生成
--   Snowflake Cortex の AI_GENERATE_TABLE_DESC を使って全テーブル・カラムに
--   AI 生成の日本語 Description を付与する。
--   ※ 実行時間の目安: 約 10-15 分 (92 テーブル × 翻訳処理)
-- =============================================================================

-- 未設定のオブジェクトのみ生成（メタデータのみ使用、コスト低）
CALL KUMAMOTO_OPENDATA.PUBLIC.GENERATE_DB_DESCRIPTIONS(
    'KUMAMOTO_OPENDATA',  -- 対象データベース
    FALSE,                -- 既存 Description は上書きしない
    FALSE                 -- メタデータのみ使用（実データはサンプリングしない）
);

-- 全件上書き再生成する場合（実データをサンプリングして精度向上）
-- CALL KUMAMOTO_OPENDATA.PUBLIC.GENERATE_DB_DESCRIPTIONS(
--     'KUMAMOTO_OPENDATA',
--     TRUE,   -- 既存 Description を上書き
--     TRUE    -- 実データをサンプリング（より精度の高い説明を生成）
-- );

-- Description の設定確認: テーブルコメント
SELECT
    TABLE_NAME,
    COMMENT AS TABLE_DESCRIPTION
FROM KUMAMOTO_OPENDATA.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'PUBLIC'
  AND TABLE_TYPE   = 'BASE TABLE'
  AND COMMENT IS NOT NULL
ORDER BY TABLE_NAME
LIMIT 10;

-- Description の設定確認: カラムコメント
SELECT
    COLUMN_NAME,
    COMMENT AS COLUMN_DESCRIPTION
FROM KUMAMOTO_OPENDATA.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'PUBLIC'
  AND TABLE_NAME   = 'T11051_TRAM_RIDERSHIP_REVENUE_MONTHLY'
ORDER BY ORDINAL_POSITION;


-- =============================================================================
-- Step 3: データ活用サンプルクエリ
-- =============================================================================

-- 熊本市電の年間乗車人数推移（年度別集計）
SELECT
    "年度",
    SUM("乗車人数【人】"::INT) AS 年間乗車人数,
    SUM("乗車料収入【円】"::INT) AS 年間収入
FROM KUMAMOTO_OPENDATA.PUBLIC.T11051_TRAM_RIDERSHIP_REVENUE_MONTHLY
WHERE "総数/定期/定期外" = '総数'
GROUP BY "年度"
ORDER BY "年度" DESC
LIMIT 10;

-- 熊本市の月次人口動態（直近 12 ヶ月）
SELECT
    "月次",
    "性別",
    "人数【人】"::INT AS 推計人口
FROM KUMAMOTO_OPENDATA.PUBLIC.T02031_POPULATION_MONTHLY
ORDER BY "月次" DESC
LIMIT 24;

-- フリーWi-Fiスポット一覧
SELECT *
FROM KUMAMOTO_OPENDATA.PUBLIC.FREE_WIFI_SPOTS
LIMIT 10;
