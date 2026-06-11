-- ============================================================
-- Snowflake Intelligence Hands-on Lab
-- 熊本市オープンデータ × Snowflake Intelligence
-- ============================================================
--
-- 【ハンズオンの概要】
--   熊本市が公開しているオープンデータ（人口・交通・防災・文化など）を
--   Snowflake に取り込み、Snowflake Intelligence から
--   「熊本市電の乗車人数は？」「火災件数と交通事故を比較して」など
--   自然言語で問い合わせできる環境を構築します。
--
-- 【実行するファイルの順番】
--   STEP1_setup.sql          ← このファイル（インフラ設定）
--   STEP2_ingest_data.sql    データ取込ストアドプロシージャの作成と実行
--   STEP3_semantic_view.sql  Semantic View の作成
--   STEP4_cortex_agent.sql   Cortex Agent の作成
--   STEP5_demo_queries.sql   動作確認・デモクエリ
--
-- 【前提条件】
--   - 実行ロール: ACCOUNTADMIN
--     （Network Rule / External Access Integration の作成に必要）
--   - Cortex AI 機能が使用可能なリージョンであること
-- ============================================================

-- ============================================================
-- STEP 1-1: ロールの切り替え
-- ============================================================
-- ACCOUNTADMIN ロールに切り替えます。
-- このロールは Network Rule と External Access Integration の
-- 作成に必要です。
USE ROLE ACCOUNTADMIN;


-- ============================================================
-- STEP 1-2: データベース・スキーマの作成
-- ============================================================
-- 熊本市オープンデータ用のデータベースを作成します。
-- IF NOT EXISTS を使うため、既に存在していてもエラーになりません。
CREATE DATABASE IF NOT EXISTS KUMAMOTO_OPENDATA
    COMMENT = '熊本市オープンデータカタログから取り込んだ統計データ';

CREATE SCHEMA IF NOT EXISTS KUMAMOTO_OPENDATA.PUBLIC
    COMMENT = '熊本市統計データ・Semantic View・Cortex Agent を格納するスキーマ';

-- 作成を確認
SHOW DATABASES LIKE 'KUMAMOTO_OPENDATA';


-- ============================================================
-- STEP 1-3: ウェアハウスの確認・作成
-- ============================================================
-- 既存のウェアハウスを使用する場合は以下を変更してください。
-- デフォルトは COMPUTE_WH を使用します。
USE WAREHOUSE COMPUTE_WH;

-- 現在のウェアハウスを確認
SELECT CURRENT_WAREHOUSE();


-- ============================================================
-- STEP 1-4: Network Rule の作成
-- ============================================================
-- Snowflake のストアドプロシージャ（Python）から
-- 外部の CKAN API サーバー（data.bodik.jp）へのアクセスを
-- 許可するルールを定義します。
--
-- 【ポイント】
--   通常、Snowflake 内部のコードは外部ネットワークにアクセスできません。
--   Network Rule で許可するホストを明示的に指定することで、
--   セキュアな外部アクセスが可能になります。
--
-- TYPE = HOST_PORT : ホスト名とポートで接続先を指定
-- MODE = EGRESS   : Snowflake から外部方向の通信を許可
CREATE OR REPLACE NETWORK RULE KUMAMOTO_OPENDATA.PUBLIC.BODIK_NETWORK_RULE
    TYPE       = HOST_PORT
    MODE       = EGRESS
    VALUE_LIST = ('data.bodik.jp')
    COMMENT    = 'BODIK ODCS CKAN API (熊本市オープンデータ) へのアクセスを許可';

-- 作成を確認
SHOW NETWORK RULES IN SCHEMA KUMAMOTO_OPENDATA.PUBLIC;


-- ============================================================
-- STEP 1-5: External Access Integration の作成
-- ============================================================
-- Network Rule をまとめた統合オブジェクトを作成します。
-- Python ストアドプロシージャはこのオブジェクトを参照することで
-- 外部通信が許可されます。
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION BODIK_EXTERNAL_ACCESS
    ALLOWED_NETWORK_RULES = (KUMAMOTO_OPENDATA.PUBLIC.BODIK_NETWORK_RULE)
    ENABLED               = TRUE
    COMMENT               = 'BODIK ODCS へのアクセスを許可する External Access Integration';

-- 作成を確認
SHOW INTEGRATIONS LIKE 'BODIK_EXTERNAL_ACCESS';


-- ============================================================
-- STEP 1-6: 権限の付与
-- ============================================================
-- SYSADMIN ロールにデータベース・スキーマ・統合オブジェクトへの
-- 権限を付与します。
-- （ACCOUNTADMIN のまま作業する場合はこの手順は不要ですが、
--   実運用では最小権限の原則に従い SYSADMIN で作業することを推奨します）
-- GRANT USAGE  ON DATABASE   KUMAMOTO_OPENDATA         TO ROLE SYSADMIN;
-- GRANT ALL    ON SCHEMA     KUMAMOTO_OPENDATA.PUBLIC   TO ROLE SYSADMIN;
-- GRANT USAGE  ON INTEGRATION BODIK_EXTERNAL_ACCESS     TO ROLE SYSADMIN;

-- -- Snowflake Intelligence が参照できるよう PUBLIC ロールにも権限を付与
-- GRANT USAGE  ON DATABASE   KUMAMOTO_OPENDATA         TO ROLE PUBLIC;
-- GRANT USAGE  ON SCHEMA     KUMAMOTO_OPENDATA.PUBLIC   TO ROLE PUBLIC;


-- ============================================================
-- STEP 1 完了
-- ============================================================
-- ✅ データベース KUMAMOTO_OPENDATA が作成されました
-- ✅ Network Rule BODIK_NETWORK_RULE が作成されました
-- ✅ External Access Integration BODIK_EXTERNAL_ACCESS が作成されました
--
-- 次は STEP2_ingest_data.sql を実行してください。
-- ============================================================
