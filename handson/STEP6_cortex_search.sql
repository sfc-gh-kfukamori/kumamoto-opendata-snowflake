-- ============================================================
-- Snowflake Intelligence Hands-on Lab
-- STEP 6: PDF ドキュメントの Cortex Search 追加
-- ============================================================
--
-- 【このステップでやること】
--   以下の2つの PDF ドキュメントを Snowflake に取り込み、
--   Cortex Search（全文意味検索）サービスを作成し、
--   既存の Snowflake Intelligence Agent に追加します。
--
--   対象 PDF:
--     1. kumamoto_shiseigaiyo_2025.pdf  熊本市市政概要2025
--     2. Kumamoto_sougoukeikaku.pdf     熊本市総合計画
--
-- 【完成後できること】
--   Snowflake Intelligence で以下のような質問が可能になります:
--     「熊本市の重点施策は何ですか?」（総合計画から検索）
--     「熊本市の組織構成を教えて」（市政概要から検索）
--     「熊本市が目指す将来像は?」（両ドキュメントを横断検索）
--
-- 【アーキテクチャ】
--   PDF ファイル（ローカル）
--     │ PUT / Snowsight アップロード
--     ▼
--   内部ステージ（@KUMAMOTO_DOCS_STAGE）
--     │ AI_PARSE_DOCUMENT（テキスト抽出）
--     ▼
--   テーブル（KUMAMOTO_DOCS_CHUNKS）← テキストをチャンク分割して格納
--     │ CREATE CORTEX SEARCH SERVICE
--     ▼
--   Cortex Search Service（KUMAMOTO_DOCS_SEARCH）
--     │ Cortex Agent にツールとして追加
--     ▼
--   Snowflake Intelligence（既存 Agent に検索機能を追加）
--
-- 【前提条件】
--   - STEP1〜STEP4 が完了していること
--   - PDF ファイルがローカルにあること:
--       kumamoto_shiseigaiyo_2025.pdf
--       Kumamoto_sougoukeikaku.pdf
-- 【実行ロール】ACCOUNTADMIN
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE KUMAMOTO_OPENDATA;
USE SCHEMA PUBLIC;
USE WAREHOUSE COMPUTE_WH;


-- ============================================================
-- STEP 6-1: PDF 格納用の内部ステージ作成
-- ============================================================
-- DIRECTORY = TRUE にすることで、ステージ上のファイルを
-- DIRECTORY テーブル関数で一覧取得できるようになります。
-- これが AI_PARSE_DOCUMENT でファイルを参照するために必要です。

CREATE OR REPLACE STAGE KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_STAGE
    DIRECTORY     = (ENABLE = TRUE)
    COMMENT       = '熊本市政策文書（市政概要・総合計画）の PDF 格納ステージ';

-- ステージ作成確認
SHOW STAGES IN SCHEMA KUMAMOTO_OPENDATA.PUBLIC;


-- ============================================================
-- STEP 6-2: PDF ファイルのアップロード
-- ============================================================
-- 以下のいずれかの方法でローカルの PDF ファイルを
-- @KUMAMOTO_DOCS_STAGE にアップロードしてください。
--
-- 【方法 A: Snowsight UI からアップロード（推奨）】
--   1. Snowsight 左メニュー「Data」→「Databases」
--   2. KUMAMOTO_OPENDATA → PUBLIC → Stages → KUMAMOTO_DOCS_STAGE
--   3. 「+ Files」ボタンをクリック
--   4. 以下のファイルをドラッグ＆ドロップまたは選択してアップロード:
--        kumamoto_shiseigaiyo_2025.pdf
--        Kumamoto_sougoukeikaku.pdf
--   5. アップロード完了後、このスクリプトの続きを実行する
--
-- 【方法 B: SnowSQL / Snowflake CLI からアップロード】
--   SnowSQL を使用する場合は以下のコマンドを実行:
--   (このスクリプトではなく、ターミナルから実行してください)
--
--   $ snowsql -a <account> -u <user>
--   > PUT file:///Users/<username>/kumamoto_shiseigaiyo_2025.pdf
--         @KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_STAGE
--         OVERWRITE = TRUE AUTO_COMPRESS = FALSE;
--
--   > PUT file:///Users/<username>/Kumamoto_sougoukeikaku.pdf
--         @KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_STAGE
--         OVERWRITE = TRUE AUTO_COMPRESS = FALSE;
--
-- ⚠️ アップロードが完了してから次のステップに進んでください

-- アップロード後の確認（ファイルが表示されれば OK）
LS @KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_STAGE;


-- ============================================================
-- STEP 6-3: PDF テキスト抽出とチャンク分割テーブルの作成
-- ============================================================
-- AI_PARSE_DOCUMENT で PDF からテキストを抽出し、
-- テキストを適切なサイズ（1000文字程度）のチャンクに分割して
-- テーブルに格納します。
--
-- 【チャンク分割の必要性】
--   Cortex Search はテキストの断片（チャンク）単位で意味検索を行います。
--   1つの PDF をそのまま1レコードにすると検索精度が落ちるため、
--   段落・セクション単位に分割することで精度が上がります。
--
-- 【AI_PARSE_DOCUMENT の処理モード】
--   LAYOUT モード（推奨）: 文書の構造（見出し・表・段落）を保持して抽出
--   OCR モード           : 画像ベースの PDF（スキャン文書）に使用
--
-- SPLIT_TEXT_RECURSIVE_CHARACTER の引数:
--   第1引数: 分割するテキスト
--   第2引数: セパレータの種類（'markdown' = 改行等で分割）
--   第3引数: チャンクサイズ（文字数）
--   第4引数: チャンクのオーバーラップ（前後の文脈を保持）

CREATE OR REPLACE TABLE KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_CHUNKS (
    CHUNK_ID        VARCHAR                    COMMENT 'チャンクの一意ID（ファイル名_番号）',
    FILE_NAME       VARCHAR                    COMMENT 'PDFファイル名（拡張子なし）',
    FILE_PATH       VARCHAR                    COMMENT 'ステージ上のファイルパス',
    CHUNK_INDEX     INT                        COMMENT 'ドキュメント内のチャンク番号',
    CHUNK_TEXT      VARCHAR                    COMMENT 'チャンクのテキスト内容（Cortex Search で検索対象）',
    CREATED_AT      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = '熊本市政策文書（市政概要・総合計画）のテキストチャンク';

-- ステージのメタデータを最新化
ALTER STAGE KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_STAGE REFRESH;

-- PDF を解析してチャンクを挿入
-- AI_PARSE_DOCUMENT で全テキストを抽出 → SPLIT_TEXT_RECURSIVE_CHARACTER でチャンク分割
INSERT INTO KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_CHUNKS (
    CHUNK_ID, FILE_NAME, FILE_PATH, CHUNK_INDEX, CHUNK_TEXT
)
WITH
-- Step 1: ステージ上の PDF ファイル一覧を取得
pdf_files AS (
    SELECT
        RELATIVE_PATH                                     AS file_path,
        REGEXP_REPLACE(RELATIVE_PATH, '\\.pdf$', '')      AS file_name
    FROM DIRECTORY(@KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_STAGE)
    WHERE RELATIVE_PATH ILIKE '%.pdf'
),
-- Step 2: AI_PARSE_DOCUMENT で PDF テキストを抽出
--         BUILD_SCOPED_FILE_URL でステージ上のファイルへの URL を生成
--         LAYOUT モードは文書構造（見出し・段落）を保持して抽出
parsed AS (
    SELECT
        file_path,
        file_name,
        AI_PARSE_DOCUMENT(
            BUILD_SCOPED_FILE_URL(@KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_STAGE, file_path),
            {'mode': 'LAYOUT'}
        ):content::VARCHAR AS full_text
    FROM pdf_files
),
-- Step 3: テキストをチャンクに分割
--         SPLIT_TEXT_RECURSIVE_CHARACTER: 段落・改行でテキストを分割
--         チャンクサイズ=1000文字、オーバーラップ=100文字（前後の文脈を保持）
chunked AS (
    SELECT
        p.file_path,
        p.file_name,
        c.index::INT                 AS chunk_index,
        c.value::VARCHAR             AS chunk_text
    FROM parsed p,
    LATERAL FLATTEN(
        input => SNOWFLAKE.CORTEX.SPLIT_TEXT_RECURSIVE_CHARACTER(
            p.full_text,
            'markdown',  -- 改行・見出し等の Markdown 区切り文字で分割
            1000,         -- チャンクサイズ（文字数）
            100           -- オーバーラップ（文字数）
        )
    ) c
    WHERE c.value::VARCHAR IS NOT NULL
      AND LENGTH(TRIM(c.value::VARCHAR)) > 50  -- 短すぎるチャンクを除外
)
SELECT
    file_name || '_' || LPAD(chunk_index::VARCHAR, 4, '0')  AS chunk_id,
    file_name,
    file_path,
    chunk_index,
    chunk_text
FROM chunked;

-- チャンク作成結果の確認
SELECT
    FILE_NAME,
    COUNT(*)         AS チャンク数,
    AVG(LENGTH(CHUNK_TEXT))::INT AS 平均チャンク文字数
FROM KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_CHUNKS
GROUP BY FILE_NAME
ORDER BY FILE_NAME;

-- サンプルチャンクの確認（最初の3件）
SELECT CHUNK_ID, FILE_NAME, CHUNK_INDEX, LEFT(CHUNK_TEXT, 200) AS テキスト冒頭
FROM KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_CHUNKS
ORDER BY FILE_NAME, CHUNK_INDEX
LIMIT 6;


-- ============================================================
-- STEP 6-4: Cortex Search Service の作成
-- ============================================================
-- KUMAMOTO_DOCS_CHUNKS テーブルの CHUNK_TEXT 列を対象に
-- 意味検索（セマンティック検索）サービスを作成します。
--
-- 【Cortex Search の仕組み】
--   テキストをベクトル（埋め込み）に変換して保存し、
--   自然言語クエリも同様にベクトル化して最も近いチャンクを返します。
--   キーワード一致だけでなく「意味的に近い」テキストも検索できます。
--
-- 【パラメータ説明】
--   ON CHUNK_TEXT  : 検索対象の列
--   WAREHOUSE      : サービスが使用するウェアハウス
--   TARGET_LAG     : データ更新の頻度（テーブルが更新された場合の同期間隔）
--   AS (SELECT ...) : 検索対象のデータ定義

CREATE OR REPLACE CORTEX SEARCH SERVICE KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_SEARCH
    ON CHUNK_TEXT
    ATTRIBUTES FILE_NAME, CHUNK_INDEX    -- フィルタリング・結果表示に使用する列
    WAREHOUSE   = COMPUTE_WH
    TARGET_LAG  = '1 day'
    COMMENT     = '熊本市政策文書（市政概要・総合計画）の全文意味検索サービス'
    AS (
        SELECT
            CHUNK_ID,
            FILE_NAME,
            CHUNK_INDEX,
            CHUNK_TEXT
        FROM KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_CHUNKS
        WHERE CHUNK_TEXT IS NOT NULL
    );

-- Cortex Search Service の作成確認
SHOW CORTEX SEARCH SERVICES IN SCHEMA KUMAMOTO_OPENDATA.PUBLIC;

-- 動作テスト: 検索クエリを実行して結果が返ることを確認
SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_SEARCH',
        '{
            "query": "熊本市の重点施策",
            "columns": ["FILE_NAME", "CHUNK_TEXT"],
            "limit": 3
        }'
    )
)['results'] AS 検索結果;


-- ============================================================
-- STEP 6-5: Cortex Search Service へのアクセス権限付与
-- ============================================================
GRANT USAGE ON CORTEX SEARCH SERVICE KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_SEARCH TO ROLE PUBLIC;


-- ============================================================
-- STEP 6-6: 既存 Cortex Agent に Cortex Search ツールを追加
-- ============================================================
-- STEP4 で作成した KUMAMOTO_CITY_STATS_AGENT を更新し、
-- 新しく作成した Cortex Search Service をツールとして追加します。
--
-- 【Agent の構成（更新後）】
--   Tool 1: cortex_analyst_text_to_sql  ← 統計テーブルへの SQL 生成（既存）
--   Tool 2: cortex_search               ← 政策文書の全文検索（新規追加）
--
-- 【Agent の振る舞い】
--   - 数値データ・統計に関する質問 → Tool 1（Semantic View 経由で SQL 生成）
--   - 政策・施策・計画に関する質問 → Tool 2（PDF ドキュメントを意味検索）
--   - 両方にまたがる質問           → Agent が自動で両ツールを組み合わせて回答

CREATE OR REPLACE AGENT KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_CITY_STATS_AGENT
    COMMENT = '熊本市統計アナリスト＆政策アシスタント。統計データの分析（Cortex Analyst）と政策文書の全文検索（Cortex Search）を組み合わせた総合的な問い合わせが可能。'
    PROFILE = '{"display_name": "熊本市統計アナリスト", "color": "blue"}'
    FROM SPECIFICATION
    $$
    models:
      orchestration: auto

    instructions:
      orchestration: |
        あなたは熊本市のデータアナリスト兼政策アシスタントです。
        以下の2種類のデータソースを使い分けて質問に答えます。

        【データソース 1: 統計データ (query_kumamoto_stats)】
        - 人口統計: 月次推計人口・出生死亡・転入転出・婚姻離婚
        - 交通: 熊本市電（乗車人数・収入）・熊本空港（乗降客数）
        - 防災・安全: 火災件数・損害額、交通事故件数・死傷者数
        - 文化施設: 熊本博物館・動植物園の入館者数
        - 環境: 月次ごみ収集処理量・上水道使用量
        - 経済・労働: 世帯家計支出・有効求人倍率

        【データソース 2: 政策文書 (search_kumamoto_docs)】
        - 熊本市市政概要2025: 市の組織・行政サービス・施設概要
        - 熊本市総合計画: 市の長期ビジョン・重点施策・将来像

        ツールの使い分け指針:
        - 数値・統計・グラフが必要な質問 → query_kumamoto_stats を使用
        - 政策・施策・計画・組織の説明が必要な質問 → search_kumamoto_docs を使用
        - 両方にまたがる質問（例: 「火災が多い地域の対策は?」） → 両方のツールを組み合わせる

        回答は日本語で、分かりやすく丁寧に答えてください。
        数値データはグラフや表で視覚化することを推奨します。

      sample_questions:
        - question: "熊本市の月次推計人口の推移を教えて"
        - question: "熊本市電の年度別乗車人数と収入はどのくらいか"
        - question: "熊本市の重点施策は何ですか"
        - question: "熊本市が目指す将来像を教えて"
        - question: "熊本市の火災件数の推移と防災対策を教えて"
        - question: "熊本市の組織構成を教えて"
        - question: "熊本市の人口・出生数・死亡数を月次で見せて"
        - question: "市電の乗車人数と空港の乗降客数を月次で比較して"
        - question: "熊本市総合計画の概要を教えて"
        - question: "熊本市の有効求人倍率と雇用施策を教えて"

    tools:
      # Tool 1: 統計テーブルへの自然言語 SQL 生成
      # 熊本市の数値データ・統計に関する質問に使用
      - tool_spec:
          type: cortex_analyst_text_to_sql
          name: query_kumamoto_stats
          description: |
            熊本市の公式統計データを SQL で分析する。
            人口・交通（市電・空港）・防災（火災・交通事故）・文化施設（博物館・動植物園）・
            環境（ごみ処理・水道）・経済（家計支出・求人倍率）など14テーブルを横断分析できる。
            数値データのトレンド分析や比較に使用する。
            政策・計画・組織の説明には使用しない。

      # Tool 2: 政策文書の全文意味検索
      # 熊本市の政策・施策・計画・組織に関する質問に使用
      - tool_spec:
          type: cortex_search
          name: search_kumamoto_docs
          description: |
            熊本市の政策文書（市政概要2025・総合計画）を意味検索する。
            市の重点施策・将来ビジョン・組織構成・行政サービスに関する質問に使用する。
            キーワード検索ではなく意味的に近い文書を検索できる。
            数値・統計データの取得には使用しない。

    tool_resources:
      query_kumamoto_stats:
        semantic_view: KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_CITY_STATISTICS

      search_kumamoto_docs:
        name: KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_SEARCH
        max_results: "5"        # 返す検索結果の最大件数
        title_column: FILE_NAME  # 検索結果のタイトルとして表示する列
        id_column: CHUNK_ID      # 検索結果のIDとして使用する列
    $$;

-- Agent の更新確認
SHOW AGENTS IN SCHEMA KUMAMOTO_OPENDATA.PUBLIC;


-- ============================================================
-- STEP 6-7: 動作確認
-- ============================================================

-- Cortex Search でテスト検索
-- 統計データとは異なる「定性的」な質問が答えられることを確認

-- テスト 1: 政策文書を検索
SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_SEARCH',
        '{
            "query": "熊本市の将来ビジョン 都市計画",
            "columns": ["FILE_NAME", "CHUNK_TEXT"],
            "limit": 3
        }'
    )
)['results'] AS 検索結果_将来ビジョン;

-- テスト 2: ドキュメント別フィルタリング
SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_SEARCH',
        '{
            "query": "組織 行政区",
            "columns": ["FILE_NAME", "CHUNK_TEXT"],
            "filter": {"@eq": {"FILE_NAME": "kumamoto_shiseigaiyo_2025"}},
            "limit": 3
        }'
    )
)['results'] AS 検索結果_市政概要のみ;

-- チャンク数の確認
SELECT FILE_NAME, COUNT(*) AS チャンク数
FROM KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_CHUNKS
GROUP BY FILE_NAME;


-- ============================================================
-- STEP 6 完了
-- ============================================================
-- ✅ PDF ステージ KUMAMOTO_DOCS_STAGE が作成されました
-- ✅ PDF テキストがチャンク分割されて KUMAMOTO_DOCS_CHUNKS に格納されました
-- ✅ Cortex Search Service KUMAMOTO_DOCS_SEARCH が作成されました
-- ✅ Cortex Agent が更新され、統計検索＋文書検索の両方が可能になりました
--
-- 【Snowflake Intelligence での確認】
--   「熊本市統計アナリスト」を開き、以下の質問を試してください:
--     - 「熊本市の重点施策は何ですか?」（政策文書から回答）
--     - 「熊本市総合計画の概要を教えて」（政策文書から回答）
--     - 「火災件数の推移と防災対策は?」（統計 + 政策文書を組み合わせて回答）
-- ============================================================
