-- =============================================================================
-- 01_setup.sql
--
-- 概要: Snowflake インフラのセットアップ
--   1. データ格納先データベース / スキーマの作成
--   2. External Network Access の設定
--      → Snowflake から data.bodik.jp への外部 HTTP リクエストを許可
--   3. 権限付与
--
-- 実行ロール: ACCOUNTADMIN
--   Network Rule と External Access Integration の作成には
--   ACCOUNTADMIN 権限が必要。
--
-- 実行順序: このファイルを最初に実行すること。
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- =============================================================================
-- 1. データベース & スキーマ
-- =============================================================================
CREATE DATABASE IF NOT EXISTS KUMAMOTO_OPENDATA;
CREATE SCHEMA  IF NOT EXISTS KUMAMOTO_OPENDATA.PUBLIC;

-- =============================================================================
-- 2. Network Rule
--
-- Snowflake から外部ホスト data.bodik.jp へのアウトバウンド通信を許可する
-- ルールを定義する。
--
-- TYPE = HOST_PORT  : ホスト名とポートで接続先を特定
-- MODE = EGRESS     : Snowflake → 外部方向の通信
-- VALUE_LIST        : 許可するホスト（CKAN API サーバー）
-- =============================================================================
CREATE OR REPLACE NETWORK RULE KUMAMOTO_OPENDATA.PUBLIC.BODIK_NETWORK_RULE
    TYPE       = HOST_PORT
    MODE       = EGRESS
    VALUE_LIST = ('data.bodik.jp');

-- =============================================================================
-- 3. External Access Integration
--
-- Network Rule をまとめて、ストアドプロシージャが外部ネットワークに
-- アクセスする際に参照する統合オブジェクトを作成する。
-- Python ストアドプロシージャの EXTERNAL_ACCESS_INTEGRATIONS に指定する。
-- =============================================================================
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION BODIK_EXTERNAL_ACCESS
    ALLOWED_NETWORK_RULES = (KUMAMOTO_OPENDATA.PUBLIC.BODIK_NETWORK_RULE)
    ENABLED = TRUE;

-- =============================================================================
-- 4. 権限付与
--
-- ストアドプロシージャの実行ロール (SYSADMIN) に必要な権限を付与する。
-- ACCOUNTADMIN のままで作業する場合はこの手順は不要。
-- =============================================================================
GRANT USAGE ON DATABASE   KUMAMOTO_OPENDATA         TO ROLE SYSADMIN;
GRANT ALL   ON SCHEMA     KUMAMOTO_OPENDATA.PUBLIC   TO ROLE SYSADMIN;
GRANT USAGE ON INTEGRATION BODIK_EXTERNAL_ACCESS     TO ROLE SYSADMIN;
