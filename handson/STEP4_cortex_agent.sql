-- ============================================================
-- Snowflake Intelligence Hands-on Lab
-- STEP 4: Cortex Agent の作成
-- ============================================================
--
-- 【このステップでやること】
--   Snowflake Intelligence の一覧に表示される Cortex Agent を作成します。
--   この Agent が Semantic View と紐付き、自然言語問い合わせを実現します。
--
-- 【Cortex Agent とは?】
--   Snowflake Intelligence のエントリーポイントとなる AI エージェントです。
--   ユーザーの自然言語の質問を受け取り、適切なツール（Cortex Analyst）に
--   処理を委譲して SQL を生成・実行し、結果を日本語で返します。
--
-- 【構成】
--   Snowflake Intelligence
--       └── Cortex Agent: KUMAMOTO_CITY_STATS_AGENT  ← このステップで作成
--               └── Tool: cortex_analyst_text_to_sql
--                       └── Semantic View: KUMAMOTO_CITY_STATISTICS  ← STEP3 で作成済み
--
-- 【前提条件】
--   - STEP3_semantic_view.sql が実行済みで Semantic View が存在すること
-- 【実行ロール】
--   - ACCOUNTADMIN
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE KUMAMOTO_OPENDATA;
USE SCHEMA PUBLIC;
USE WAREHOUSE COMPUTE_WH;


-- ============================================================
-- STEP 4-1: Cortex Agent の作成
-- ============================================================
-- FROM SPECIFICATION $$ ... $$ ブロックに YAML 形式で
-- Agent の設定を記述します。
--
-- 設定項目:
--   models.orchestration    : 使用する LLM モデル（auto = 最適なモデルを自動選択）
--   instructions.orchestration : Agent の振る舞いを指示するプロンプト
--   instructions.sample_questions : Snowflake Intelligence の画面に表示される
--                                   サンプル質問（ユーザーが参考にできる）
--   tools                   : 使用するツールのリスト
--   tool_resources          : 各ツールが参照するリソース（Semantic View）

CREATE OR REPLACE AGENT KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_CITY_STATS_AGENT
    COMMENT = '熊本市オープンデータ統計アナリスト。人口・交通・防災・文化施設・環境・経済など14種類の月次統計データを自然言語で横断分析できる。'
    PROFILE = '{"display_name": "熊本市統計アナリスト", "color": "blue"}'
    FROM SPECIFICATION
    $$
    models:
      orchestration: auto   # Snowflake が最適な LLM を自動選択

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
        - 質問に対して適切なデータソースを選択して SQL を生成する
        - 複数テーブルをまたぐ質問は年次・月次で JOIN して分析する
        - 結果は日本語で分かりやすく説明する
        - グラフや表を使って視覚的に表示する

      # Snowflake Intelligence の画面に表示されるサンプル質問
      # ユーザーがクリックするだけで問い合わせを試せます
      sample_questions:
        # ── Cortex Analyst（統計データ） ─────────────────────────
        # TOTAL_POPULATION metric: 性別='総数'フィルタ込みの推計人口合計
        - question: "月次の推計総人口はどのように推移していますか"
        # TRAM_RIDERSHIP_TOTAL + TRAM_REVENUE_TOTAL metrics: 総数フィルタ込み
        - question: "熊本市電の年度別乗車人数合計と乗車料収入の推移を教えて"
        # museum_to_zoo_monthly relationship + MUSEUM_VISITORS_TOTAL / ZOO_VISITORS_TOTAL metrics
        - question: "博物館と動植物園の月次入館者数を比較して"
        # FIRE_INCIDENTS_TOTAL + FIRE_DAMAGE_YEN metrics: 全種別合計
        - question: "火災件数と損害額の年次推移を見せて"
        # JOB_VACANCY_RATE metric: 有効求人倍率
        - question: "有効求人倍率の最近の推移を教えて"
        # ZONGSHU_DINGQI_DINGQIWAI dimension + JOSHARENSHU fact: 定期・定期外の内訳
        - question: "市電の定期利用者と定期外利用者の割合はどう変化しているか"


    tools:
      - tool_spec:
          type: cortex_analyst_text_to_sql   # 自然言語 → SQL 変換ツール
          name: query_kumamoto_stats
          description: |
            熊本市の公式統計データを自然言語でクエリする。
            人口・交通（市電・空港）・防災（火災・交通事故）・文化施設（博物館・動植物園）・
            環境（ごみ処理・水道）・経済（家計支出・求人倍率）など14テーブルを横断分析できる。
            月次・年次のトレンド分析や複数カテゴリの比較に最適。

    tool_resources:
      query_kumamoto_stats:
        # STEP3 で作成した Semantic View を参照
        semantic_view: KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_CITY_STATISTICS
    $$;


-- ============================================================
-- STEP 4-2: Agent の確認
-- ============================================================
SHOW AGENTS IN SCHEMA KUMAMOTO_OPENDATA.PUBLIC;


-- ============================================================
-- STEP 4-3: Agent へのアクセス権限付与
-- ============================================================
-- Snowflake Intelligence から Agent を使えるよう権限を付与します。
-- GRANT USAGE ON AGENT KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_CITY_STATS_AGENT TO ROLE PUBLIC;


-- -- ============================================================
-- STEP 4 完了
-- ============================================================
-- ✅ Cortex Agent KUMAMOTO_CITY_STATS_AGENT が作成されました
-- ✅ 表示名: 熊本市統計アナリスト
-- ✅ サンプル質問: 10 件登録済み
--
-- 【次のステップ: Snowflake Intelligence で確認】
--   Snowsight の左メニューから「Intelligence」を開き、
--   「熊本市統計アナリスト」が表示されることを確認してください。
--   サンプル質問をクリックするか、自由に質問を入力してみてください。
--
-- 動作確認クエリは STEP5_demo_queries.sql を参照してください。
-- ============================================================
