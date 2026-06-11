-- ============================================================
-- Snowflake Intelligence Hands-on Lab
-- STEP 7: Streamlit in Snowflake ダッシュボードの作成
-- ============================================================
--
-- 【このステップでやること】
--   External Network Access で取り込んだ 92 テーブルのデータを
--   Streamlit in Snowflake (SiS) ダッシュボードで可視化する。
--
-- 【ダッシュボードで見れるもの】
--   Tab 1: 人口動態  - 月次推計人口・出生死亡・転入転出
--   Tab 2: 交通      - 市電乗車人数・定期別内訳・空港乗降客数
--   Tab 3: 防災・安全 - 火災件数・種別内訳・交通事故・損害額
--   Tab 4: 文化施設  - 博物館・動植物園・現代美術館入館者数比較
--   Tab 5: 経済・労働 - 有効求人倍率・就職率・家計支出費目別
--   Tab 6: 環境      - ごみ収集量・上水道用途別使用量
--   サイドバー: 年度スライダー（2011〜2021）で全チャートを同時フィルタリング
--
-- 【実装方法】2通り
--   方法 A: Snowsight UI から作成（コード貼り付け）← 初心者向け
--   方法 B: SQL で作成（ステージ経由）← SQL に慣れた方向け
--
-- 【前提条件】STEP1〜STEP2 が完了していること（92テーブルが存在すること）
-- 【実行ロール】ACCOUNTADMIN
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE KUMAMOTO_OPENDATA;
USE SCHEMA PUBLIC;
USE WAREHOUSE COMPUTE_WH;


-- ============================================================
-- STEP 7-1: 方法 A - Snowsight UI からアプリを作成（推奨）
-- ============================================================
-- ファイルのアップロード不要。コードを貼り付けるだけで動く。
--
-- 手順:
--   1. Snowsight 左メニュー「Streamlit」をクリック
--   2. 右上「+ Streamlit App」をクリック
--   3. 以下を設定して「Create」
--        App title : 熊本市オープンデータ ダッシュボード
--        Database  : KUMAMOTO_OPENDATA
--        Schema    : PUBLIC
--        Warehouse : COMPUTE_WH
--   4. エディタ画面でデフォルトコードを全選択して削除
--   5. GitHub リポジトリの streamlit/kumamoto_dashboard.py の
--      内容をコピーして貼り付け
--      （URL: https://github.com/sfc-gh-kfukamori/kumamoto-opendata-snowflake）
--   6. 「Run」ボタンで実行して動作確認


-- ============================================================
-- STEP 7-2: 方法 B - SQL でアプリを作成
-- ============================================================
-- ステージにファイルをアップロードし、CREATE STREAMLIT で作成する。
-- アップロードは Snowsight のステージブラウザか SnowSQL の PUT コマンドを使う。

-- Step B-1: Streamlit アプリ用のステージを作成
CREATE OR REPLACE STAGE KUMAMOTO_OPENDATA.PUBLIC.STREAMLIT_STAGE
    COMMENT = 'Streamlit アプリ（kumamoto_dashboard.py）格納用ステージ';

-- Step B-2: Python ファイルをステージにアップロード
-- 【Snowsight から】
--   Data → Databases → KUMAMOTO_OPENDATA → PUBLIC → Stages → STREAMLIT_STAGE
--   → + Files → kumamoto_dashboard.py を選択してアップロード
--
-- 【SnowSQL / Snowflake CLI から】（ターミナルで実行）
--   PUT file:///path/to/kumamoto_dashboard.py
--       @KUMAMOTO_OPENDATA.PUBLIC.STREAMLIT_STAGE
--       OVERWRITE=TRUE AUTO_COMPRESS=FALSE;

-- Step B-3: アップロード確認
LS @KUMAMOTO_OPENDATA.PUBLIC.STREAMLIT_STAGE;
-- 期待値: kumamoto_dashboard.py が表示されること

-- Step B-4: Streamlit アプリ作成
--   ROOT_LOCATION : アプリファイルが格納されているステージのパス
--   MAIN_FILE     : エントリポイントとなる Python ファイル名
--   QUERY_WAREHOUSE: データ取得に使用するウェアハウス
CREATE OR REPLACE STREAMLIT KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DASHBOARD
    ROOT_LOCATION = '@KUMAMOTO_OPENDATA.PUBLIC.STREAMLIT_STAGE'
    MAIN_FILE     = 'kumamoto_dashboard.py'
    QUERY_WAREHOUSE = COMPUTE_WH
    TITLE   = '熊本市オープンデータ ダッシュボード'
    COMMENT = '熊本市の統計データ（92テーブル）を6カテゴリで可視化するダッシュボード';


-- ============================================================
-- STEP 7-3: 権限付与
-- ============================================================
-- 他のロールとダッシュボードを共有する場合に実行する。
GRANT USAGE ON STREAMLIT KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DASHBOARD TO ROLE PUBLIC;


-- ============================================================
-- STEP 7-4: 作成確認とアプリの起動
-- ============================================================
SHOW STREAMLITS IN SCHEMA KUMAMOTO_OPENDATA.PUBLIC;

-- Snowsight でアプリを開く:
--   左メニュー「Streamlit」→ KUMAMOTO_DASHBOARD をクリック


-- ============================================================
-- STEP 7 完了
-- ============================================================
-- ✅ KUMAMOTO_DASHBOARD Streamlit アプリが作成されました
--
-- 【ダッシュボードの構成】
--   Tab 1: 人口動態  (月次推計人口・男女別・出生死亡・転入転出) 4チャート
--   Tab 2: 交通      (市電乗車人数・定期別・空港乗降客・収入)   4チャート
--   Tab 3: 防災・安全 (火災件数・種別内訳・交通事故・損害額)    5チャート
--   Tab 4: 文化施設  (博物館・動植物園・現代美術館 比較)        3チャート
--   Tab 5: 経済・労働 (有効求人倍率・就職率・家計支出費目別)    4チャート
--   Tab 6: 環境      (ごみ収集量・種別内訳・上水道用途別)       4チャート
--   サイドバー: 年度フィルタ（2011〜2021）で全チャートを同時フィルタリング
-- ============================================================
