-- ============================================================
-- Snowflake Intelligence Hands-on Lab
-- STEP 8: メール送信スキルの追加
-- ============================================================
--
-- 【このステップでやること】
--   Snowflake Intelligence で分析した結果を
--   メールで送付できるスキル（generic ツール）を追加します。
--
-- 【完成後できること】
--   Snowflake Intelligence で:
--     「市電の乗車人数分析結果を kenshiro.fukamori@snowflake.com に送って」
--     「有効求人倍率のレポートをメールしたい」
--   → Agent が分析を実行し、結果をそのままメールで送付する
--
-- 【仕組み】
--   Cortex Agent
--     │ 分析結果を生成（query_kumamoto_stats / search_kumamoto_docs）
--     └─ send_analysis_email ツールを呼び出す
--              ↓ 引数: recipient, subject, body
--         SEND_ANALYSIS_EMAIL ストアドプロシージャ
--              ↓
--         SYSTEM$SEND_EMAIL（Snowflake 組み込みメール送信）
--              ↓
--         kenshiro.fukamori@snowflake.com に HTML メールが届く
--
-- 【制約事項】
--   - 送付先は ALLOWED_RECIPIENTS に登録したアドレスのみ送信可能
--   - 送信元は no-reply@snowflake.com 固定（変更不可）
--   - 添付ファイル非対応（分析結果は HTML テキストで送付）
--
-- 【前提条件】STEP1〜STEP4 が完了していること
-- 【実行ロール】ACCOUNTADMIN
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE KUMAMOTO_OPENDATA;
USE SCHEMA PUBLIC;
USE WAREHOUSE COMPUTE_WH;


-- ============================================================
-- STEP 8-1: Email Notification Integration の作成
-- ============================================================
-- Snowflake からメールを送信するための設定オブジェクト。
-- ALLOWED_RECIPIENTS に指定したアドレスのみ送信できる（セキュリティ制約）。
--
-- 【パラメータの説明】
--   TYPE = EMAIL               : メール通知タイプ
--   ENABLED = TRUE             : 有効化
--   ALLOWED_RECIPIENTS         : 送信を許可するメールアドレスのリスト
--                                ※ ドメイン指定は ALLOWED_RECIPIENT_DOMAINS で可能
--
-- ※ 実際のハンズオンでは送付先アドレスを変更してください

CREATE OR REPLACE NOTIFICATION INTEGRATION KUMAMOTO_EMAIL_INTEGRATION
    TYPE               = EMAIL
    ENABLED            = TRUE
    ALLOWED_RECIPIENTS = ('kenshiro.fukamori@snowflake.com')
    COMMENT            = '熊本市統計アナリストからの分析結果メール送信用';

-- 作成確認
SHOW INTEGRATIONS LIKE 'KUMAMOTO_EMAIL_INTEGRATION';


-- ============================================================
-- STEP 8-2: メール送信ストアドプロシージャの作成
-- ============================================================
-- Cortex Agent の generic ツールから呼び出されるプロシージャ。
-- Agent から渡された分析テキストを HTML メールにフォーマットして送信する。
--
-- 【引数】
--   RECIPIENT : 送付先メールアドレス（ALLOWED_RECIPIENTS に含まれるもののみ）
--   SUBJECT   : 件名
--   BODY      : 本文テキスト（Agent が生成した分析結果）
--
-- 【内部処理】
--   1. 本文テキストを Snowflake ブランドの HTML にフォーマット
--   2. SYSTEM$SEND_EMAIL で送信

CREATE OR REPLACE PROCEDURE KUMAMOTO_OPENDATA.PUBLIC.SEND_ANALYSIS_EMAIL(
    RECIPIENT VARCHAR,
    SUBJECT   VARCHAR,
    BODY      VARCHAR
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'send_email'
COMMENT = '分析結果を指定のメールアドレスに送付する（Cortex Agent の generic ツール）'
AS
$$
def send_email(session, recipient: str, subject: str, body: str) -> str:
    """
    Cortex Agent から呼び出されるメール送信プロシージャ。
    Agent が生成した分析テキストを HTML メールにフォーマットして送信する。

    引数:
        recipient : 送付先（ALLOWED_RECIPIENTS に登録済みのアドレスのみ）
        subject   : 件名
        body      : 分析結果の本文テキスト（Agent が生成）
    """
    # SQL 埋め込み用にシングルクォートをエスケープ
    esc_recipient = recipient.replace("'", "''")
    esc_subject   = subject.replace("'", "''")

    # HTML 本文を組み立て
    # CSS にシングルクォートを使わない記法で記述（SQL 埋め込み時の干渉を防ぐ）
    body_html = body.replace("'", "''").replace('\n', '<br>')

    html = (
        '<html><body style="font-family: Arial, sans-serif; color: #333; max-width: 700px; margin: 0 auto;">'
        '<div style="background: #29B5E8; padding: 20px 30px;">'
        '<h1 style="color: white; margin: 0; font-size: 22px;">'
        '熊本市統計アナリスト - 分析レポート'
        '</h1></div>'
        '<div style="padding: 30px; background: #f9f9f9; border: 1px solid #e0e0e0;">'
        f'<h2 style="color: #11567F; font-size: 16px; margin-top: 0;">{esc_subject}</h2>'
        '<div style="background: white; padding: 20px; border-radius: 4px;'
        ' border-left: 4px solid #29B5E8; line-height: 1.8;">'
        f'{body_html}'
        '</div></div>'
        '<div style="padding: 15px 30px; background: #f0f0f0;'
        ' font-size: 12px; color: #888; text-align: center;">'
        'このメールは Snowflake Intelligence - 熊本市統計アナリスト から自動送信されました。<br>'
        'データソース: 熊本市オープンデータカタログ (BODIK ODCS)'
        '</div></body></html>'
    )

    session.sql(
        f"CALL SYSTEM$SEND_EMAIL("
        f"'KUMAMOTO_EMAIL_INTEGRATION', "
        f"'{esc_recipient}', "
        f"'{esc_subject}', "
        f"'{html}', "
        f"'text/html')"
    ).collect()

    return f"メールを {recipient} に送信しました。件名: {subject}"
$$;

-- 作成確認
SHOW PROCEDURES LIKE 'SEND_ANALYSIS_EMAIL' IN SCHEMA KUMAMOTO_OPENDATA.PUBLIC;


-- ============================================================
-- STEP 8-3: 動作テスト
-- ============================================================
-- プロシージャを直接呼び出してメールが届くことを確認する。
-- ALLOWED_RECIPIENTS に設定したアドレスを指定すること。

CALL KUMAMOTO_OPENDATA.PUBLIC.SEND_ANALYSIS_EMAIL(
    'kenshiro.fukamori@snowflake.com',     -- 送付先（ALLOWED_RECIPIENTS のアドレス）
    '【テスト】熊本市統計アナリスト メール送信テスト',
    '熊本市統計アナリストからのテストメールです。\n\nメール送信スキルが正常に動作しています。\n\n今後 Snowflake Intelligence から分析結果を直接メールで受け取ることができます。'
);
-- 期待値: "メールを kenshiro.fukamori@snowflake.com に送信しました。" が返ること


-- ============================================================
-- STEP 8-4: Cortex Agent にメール送信ツールを追加
-- ============================================================
-- 既存 Agent を更新し、send_analysis_email を generic ツールとして追加する。
--
-- 【generic ツールの tool_resources 設定】
--   type       : procedure（ストアドプロシージャをツールとして使用）
--   identifier : プロシージャの完全修飾名
--   execution_environment.type : warehouse（ウェアハウスで実行）
--   query_timeout : 60秒（メール送信の最大待機時間）

CREATE OR REPLACE AGENT KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_CITY_STATS_AGENT
    COMMENT = '熊本市統計アナリスト＆政策アシスタント。統計データ分析・PDF検索・メール送信が可能。'
    PROFILE = '{"display_name": "熊本市統計アナリスト", "color": "blue"}'
    FROM SPECIFICATION
    $$
    models:
      orchestration: auto

    instructions:
      orchestration: |
        あなたは熊本市のデータアナリスト兼政策アシスタントです。
        以下のツールを使い分けて質問に答えます。

        【ツール 1: 統計データ (query_kumamoto_stats)】
        熊本市の統計データ（人口・交通・防災・文化・環境・経済）をSQLで分析します。
        数値データのトレンド分析・比較に使用します。

        【ツール 2: 政策文書 (search_kumamoto_docs)】
        熊本市男女共同参画企業意識実態調査の PDF を意味検索します。
        女性活躍・育児休業・男女賃金格差などの質問に使用します。

        【ツール 3: メール送信 (send_analysis_email)】
        分析結果をメールで送付します。
        ユーザーが「〇〇に送って」「メールしたい」と言った場合に使用します。
        送付先は kenshiro.fukamori@snowflake.com のみ許可されています。
        メール送信前に必ず件名と本文を確認してください。
        本文には分析結果の要点を分かりやすく日本語でまとめてください。

        回答は日本語で分かりやすく答えてください。

      sample_questions:
        # ── Cortex Analyst（統計データ） ─────────────────────────
        - question: "月次の推計総人口はどのように推移していますか"
        - question: "熊本市電の年度別乗車人数合計と乗車料収入の推移を教えて"
        - question: "博物館と動植物園の月次入館者数を比較して"
        - question: "火災件数と損害額の年次推移を見せて"
        - question: "有効求人倍率の最近の推移を教えて"
        - question: "市電の定期利用者と定期外利用者の割合はどう変化しているか"
        # ── Cortex Search（政策文書） ────────────────────────────
        - question: "市内事業所の女性管理職数の状況を教えて"
        - question: "男性が育児休業を取得している状況を教えて"
        - question: "市内企業の男女平均賃金の差はどのくらいですか"
        - question: "ポジティブ・アクションに取り組んでいる企業の状況を教えて"

    tools:
      # Tool 1: 統計データへの自然言語 SQL 生成
      - tool_spec:
          type: cortex_analyst_text_to_sql
          name: query_kumamoto_stats
          description: |
            熊本市の公式統計データをSQLで分析する。
            人口・交通・防災・文化施設・環境・経済など14テーブルを横断分析できる。
            数値データのトレンド分析・比較に使用する。

      # Tool 2: 政策文書の全文意味検索
      - tool_spec:
          type: cortex_search
          name: search_kumamoto_docs
          description: |
            熊本市男女共同参画に関する調査報告書を意味検索する。
            女性活躍・育児休業・ワークライフバランス・男女平均賃金などの質問に使用する。

      # Tool 3: 分析結果のメール送付（generic ツール）
      - tool_spec:
          type: generic
          name: send_analysis_email
          description: |
            分析結果をメールで送付する。
            ユーザーが「メールで送って」「〇〇に送信して」と言った場合に使用する。
            送付先は kenshiro.fukamori@snowflake.com のみ許可されている。
            必ず recipient・subject・body の3つを指定すること。
            body には分析結果の要点を日本語でまとめた内容を入れること。
          input_schema:
            type: object
            properties:
              recipient:
                type: string
                description: "送付先メールアドレス（kenshiro.fukamori@snowflake.com のみ許可）"
              subject:
                type: string
                description: "メールの件名（例: 熊本市電 月次乗車人数 分析結果）"
              body:
                type: string
                description: "メールの本文。分析結果の要点を日本語で分かりやすくまとめる。"
            required: [recipient, subject, body]

    tool_resources:
      query_kumamoto_stats:
        semantic_view: KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_CITY_STATISTICS

      search_kumamoto_docs:
        name: KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_SEARCH
        max_results: "5"
        title_column: FILE_NAME
        id_column: CHUNK_ID

      send_analysis_email:
        type: procedure
        identifier: KUMAMOTO_OPENDATA.PUBLIC.SEND_ANALYSIS_EMAIL
        execution_environment:
          type: warehouse
          warehouse: COMPUTE_WH
          query_timeout: 60
    $$;

-- Agent の確認
SHOW AGENTS IN SCHEMA KUMAMOTO_OPENDATA.PUBLIC;


-- ============================================================
-- STEP 8 完了
-- ============================================================
-- ✅ KUMAMOTO_EMAIL_INTEGRATION（Email Notification Integration）
-- ✅ SEND_ANALYSIS_EMAIL（メール送信ストアドプロシージャ）
-- ✅ KUMAMOTO_CITY_STATS_AGENT を3ツール構成に更新
--      Tool 1: cortex_analyst_text_to_sql（統計データ分析）
--      Tool 2: cortex_search（政策文書検索）
--      Tool 3: send_analysis_email（メール送付）← 今回追加
--
-- 【Snowflake Intelligence での確認】
-- 「熊本市統計アナリスト」を開き、以下を試してください:
--   1. まず分析を実行:
--      「有効求人倍率の直近の推移を教えて」
--   2. 続けて送信を依頼:
--      「この結果を kenshiro.fukamori@snowflake.com に送って」
--   → Agent が件名・本文を自動生成してメールを送信します
-- ============================================================
