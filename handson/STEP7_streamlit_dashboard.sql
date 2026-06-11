-- ============================================================
-- Snowflake Intelligence Hands-on Lab
-- STEP 7: Streamlit in Snowflake ダッシュボードの作成
-- ============================================================
--
-- このステップでやること」
--   External Network Access で取り込んだ 92 テーブルのデータを
--   Streamlit in Snowflake (SiS) ダッシュボードで可視化する。
--
-- このダッシュボードで見れるもの：
--   Tab 1: 人口動態  - 月次推計人口・出生死亡・転入転出
--   Tab 2: 交通      - 市電乗車人数・空港乗降客数
--   Tab 3: 防災・安全 - 火災件数・交通事故件数
--   Tab 4: 文化施設  - 博物館・動植物園の入館者数
--   Tab 5: 経済・労働 - 家計支出・有効求人倍率
--   Tab 6: 環境      - ごみ収集量・上水道使用量
--
-- 実装方法：方法 A（Snowsight UI）と方法 B（SQL）の 2 通り
--
-- 前提条件： STEP1～STEP2 が完了していること（92 テーブルが存在すること
-- 実行ロール：ACCOUNTADMIN
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE KUMAMOTO_OPENDATA;
USE SCHEMA PUBLIC;
USE WAREHOUSE COMPUTE_WH;


-- ============================================================
-- STEP 7-1: 方法 A - Snowsight UI から作成（推奨）
-- ============================================================
-- 以下の手順で Snowsight からダッシュボードを作成する。
-- ファイルのアップロード不要。コードをペーストするだけ。
--
-- 1. Snowsight 左メニュー「Streamlit」をクリック
-- 2. 「+ Streamlit App」をクリック
-- 3. 以下を設定して「Create」
--      App title : 熊本市オープンデータ ダッシュボード
--      Database  : KUMAMOTO_OPENDATA
--      Schema    : PUBLIC
--      Warehouse : COMPUTE_WH
-- 4. エディタ画面でデフォルトコードを全選択して削除
-- 5. streamlit/kumamoto_dashboard.py の内容をペースト
-- 6. 「Run」ボタンで実行して動作確認


-- ============================================================
-- STEP 7-2: 方法 B - SQL でデプロイ（上級者向け）
-- ============================================================
-- ステージにファイルをアップロードして CREATE STREAMLIT で作成する。
--
-- 注意: 下記の PUT コマンドは Worksheets では実行不可。
--        SnowSQL / Snowflake CLI から実行すること。

-- Step B-1: ステージ作成
CREATE OR REPLACE STAGE KUMAMOTO_OPENDATA.PUBLIC.STREAMLIT_STAGE
    COMMENT = 'Streamlit アプリ用ステージ';

-- Step B-2: ファイルをアップロード（SnowSQL または Snowflake CLI から実行）
-- PUT file:///path/to/kumamoto_dashboard.py
--     @KUMAMOTO_OPENDATA.PUBLIC.STREAMLIT_STAGE
--     OVERWRITE=TRUE AUTO_COMPRESS=FALSE;

-- Step B-3: Streamlit アプリ作成
-- CREATE OR REPLACE STREAMLIT KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DASHBOARD
--     MAIN_FILE = '/kumamoto_dashboard.py'
--     QUERY_WAREHOUSE = COMPUTE_WH
--     FROM @KUMAMOTO_OPENDATA.PUBLIC.STREAMLIT_STAGE;


-- ============================================================
-- STEP 7-3: 権限付与（他のユーザーに共有する場合）
-- ============================================================
-- GRANT USAGE ON STREAMLIT KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DASHBOARD
--     TO ROLE <共有したいロール>;


-- ============================================================
-- STEP 7-4: ダッシュボードの確認
-- ============================================================
SHOW STREAMLITS IN SCHEMA KUMAMOTO_OPENDATA.PUBLIC;


-- ============================================================
-- STEP 7 完了
-- ============================================================
-- ダッシュボードの構成:
--   Tab 1: 人口動態  (月次推計人口・出生死亡・転入転出) - 4チャート
--   Tab 2: 交通      (市電・空港・定期内訳)              - 4チャート
--   Tab 3: 防災・安全 (火災件数・交通事故)                - 5チャート
--   Tab 4: 文化施設  (博物館・動植物園・現代美術館)        - 3チャート
--   Tab 5: 経済・労働 (有効求人倍率・就職率・家計支出)      - 4チャート
--   Tab 6: 環境      (ごみ収集量・上水道)                  - 4チャート
--
--   サイドバー: 年度フィルタ（2011～2021）で全チャートを同時フィルタリング
-- ============================================================
