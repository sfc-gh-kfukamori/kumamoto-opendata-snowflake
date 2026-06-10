-- =============================================================================
-- 05_deploy_semantic_view.sql
--
-- 概要: Snowflake Intelligence (Cortex Analyst) 用セマンティックビューのデプロイ
--   自然言語でデータを問い合わせるための Semantic View を作成する。
--
-- 実行前提: 01_setup.sql から 04_run_demo.sql が実行済みであること
-- 実行ロール: ACCOUNTADMIN または SYSADMIN
--
-- 対象テーブル (14テーブル):
--   人口統計   : T02031, T02040, T02050
--   交通       : T11051, T11052, T11031
--   文化施設   : T18172, T18201
--   防災・安全 : T15191, T15120
--   環境       : T13180, T08080
--   経済・労働 : T09011, T12055
-- =============================================================================

-- Python コネクタ経由でデプロイする場合:
--   python3 -c "
--     import snowflake.connector
--     yaml = open('semantic_view/kumamoto_city_statistics_semantic_model.yaml').read()
--     conn = snowflake.connector.connect(connection_name='<接続名>')
--     cur = conn.cursor()
--     cur.execute(\"CALL SYSTEM\$CREATE_SEMANTIC_VIEW_FROM_YAML('KUMAMOTO_OPENDATA.PUBLIC', %s, FALSE)\", (yaml,))
--     print(cur.fetchone()[0])
--   "

-- Snowsight の SQL エディタからデプロイする場合は:
--   YAML ファイルの内容を $$ ... $$ 形式で埋め込んで実行。

-- =============================================================================
-- デプロイ確認クエリ
-- =============================================================================

-- セマンティックビューの存在確認
SHOW SEMANTIC VIEWS IN SCHEMA KUMAMOTO_OPENDATA.PUBLIC;

-- DDL の確認
SELECT GET_DDL('SEMANTIC_VIEW', 'KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_CITY_STATISTICS');

-- =============================================================================
-- Cortex Analyst で自然言語問い合わせ（サンプル）
-- =============================================================================

-- Snowsight の Cortex Analyst UI から以下の質問を試せます:
--
-- 【単一テーブル】
--   - 熊本市の月次推計人口の推移を教えて
--   - 熊本市電の年度別乗車人数と収入はどのくらいか
--   - 熊本市の火災件数の年次推移を教えて
--   - 有効求人倍率の推移を見せて
--   - 月次ごみ収集量の推移を教えて
--
-- 【複数テーブル横断（クロステーブル）】
--   - 熊本市の人口・出生数・死亡数を月次で見せて
--   - 市電の乗車人数と空港の乗降客数を月次で比較して
--   - 火災件数と交通事故件数を年次で比較して
--   - 博物館と動植物園の年間入館者数を年度別に比較して
--   - 人口とごみ収集量の年次推移を合わせて教えて
--   - 市電の定期利用者と定期外利用者の割合はどう変化しているか
