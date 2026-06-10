-- =============================================================================
-- 06_create_cortex_agent.sql
--
-- 概要: Snowflake Intelligence 用 Cortex Agent の作成
--   Snowflake Intelligence の一覧に表示されるエージェントを作成し、
--   Semantic View を Cortex Analyst ツールとして紐付ける。
--
-- 実行前提: 05_deploy_semantic_view.sql が実行済みであること
-- 実行ロール: ACCOUNTADMIN（CREATE AGENT 権限が必要）
--
-- Snowflake Intelligence での使い方:
--   1. Snowsight → Intelligence を開く
--   2. 「熊本市統計アナリスト」が一覧に表示されることを確認
--   3. 自然言語で質問を入力する
-- =============================================================================

CREATE OR REPLACE AGENT KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_CITY_STATS_AGENT
  COMMENT = '熊本市オープンデータ統計アナリスト。人口・交通・防災・文化施設・環境・経済など14種類の月次統計データを自然言語で横断分析できる。'
  PROFILE = '{"display_name": "熊本市統計アナリスト", "color": "blue"}'
  FROM SPECIFICATION
  $$
  models:
    orchestration: auto

  instructions:
    orchestration: |
      あなたは熊本市のオープンデータアナリストです。
      熊本市の各種統計データについて日本語で質問に答えます。

      利用できるデータカテゴリ:
      - 人口統計: 月次推計人口・出生死亡・転入転出・婚姻離婚
      - 交通: 熊本市電（乗車人数・収入）・熊本空港（乗降客数）
      - 防災・安全: 火災件数・損害額、交通事故件数・死傷者数
      - 文化施設: 熊本博物館・動植物園の入館者数
      - 環境: 月次ごみ収集処理量・上水道使用量
      - 経済・労働: 世帯家計支出・有効求人倍率

      回答方針:
      - 質問に対して適切なデータソースを選択してSQLを生成する
      - 複数テーブルをまたぐ質問は年次・月次でJOINして分析する
      - 結果は日本語で分かりやすく説明する
      - グラフや表を使って視覚的に表示する

    sample_questions:
      - question: "熊本市の月次推計人口の推移を教えて"
      - question: "熊本市電の年度別乗車人数と収入はどのくらいか"
      - question: "熊本市の人口・出生数・死亡数を月次で一覧表示して"
      - question: "熊本市電の乗車人数と熊本空港の乗降客数を月次で比較して"
      - question: "熊本市の火災件数と交通事故件数を年次で比較して"
      - question: "熊本博物館と動植物園の年間入館者数を年度別に比較して"
      - question: "熊本市の有効求人倍率の直近の推移を教えて"
      - question: "熊本市の月次ごみ収集量の推移を教えて"
      - question: "熊本市の人口とごみ収集量の年次推移を合わせて教えて"
      - question: "熊本市の費目別家計支出を教えて"

  tools:
    - tool_spec:
        type: cortex_analyst_text_to_sql
        name: query_kumamoto_stats
        description: |
          熊本市の公式統計データを自然言語でクエリする。
          人口・交通（市電・空港）・防災（火災・交通事故）・文化施設（博物館・動植物園）・
          環境（ごみ処理・水道）・経済（家計支出・求人倍率）など14テーブルを横断分析できる。
          月次・年次のトレンド分析や複数カテゴリの比較に最適。

  tool_resources:
    query_kumamoto_stats:
      semantic_view: KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_CITY_STATISTICS
  $$;

-- =============================================================================
-- 確認クエリ
-- =============================================================================
SHOW AGENTS IN SCHEMA KUMAMOTO_OPENDATA.PUBLIC;
