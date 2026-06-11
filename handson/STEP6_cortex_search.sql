-- ============================================================
-- Snowflake Intelligence Hands-on Lab
-- STEP 6: PDF ドキュメントの Cortex Search 追加（発展編）
-- ============================================================
--
-- 【このステップでやること】
--   PDF ドキュメントを Snowflake に取り込み、Cortex Search（全文意味検索）
--   サービスを作成し、既存の Snowflake Intelligence Agent に追加します。
--
-- 【対象 PDF】
--   Kumamoto_kyoudousankaku.pdf
--   （熊本市 男女共同参画社会実現に向けた企業意識・実態調査 令和5年度）
--
-- 【完成後できること（統計データとの組み合わせ）】
--   - 「市内企業の女性管理職の状況を教えて」（PDF 検索）
--   - 「育児休業の取得状況はどうですか」（PDF 検索）
--   - 「有効求人倍率の推移と市内企業の取組は?」（統計 + PDF 組み合わせ）
--
-- 【2段階のパイプライン構成】
--   STAGE 1: AI_PARSE_DOCUMENT でPDF→テキスト抽出
--            PDF 1ファイル = 1レコード（KUMAMOTO_DOCS_PARSED テーブル）
--
--   STAGE 2: SPLIT_TEXT_RECURSIVE_CHARACTER でテキスト→チャンク分割
--            1チャンク = 1レコード（KUMAMOTO_DOCS_CHUNKS テーブル）
--            → CREATE CORTEX SEARCH SERVICE（意味検索サービス）
--
-- 【なぜ2段階に分けるのか?】
--   - STAGE 1 は処理時間がかかる（PDFサイズに比例）
--   - 再チャンク・再インデックスの際に STAGE 1 を省略できる
--   - 各段階の中間結果を確認しながら進められる
--
-- 【PDFファイルのサイズと処理時間の目安】
--   〜 5MB:  約30〜60秒  ← ハンズオン推奨サイズ
--   〜20MB:  約5〜10分
--   〜30MB+: 約10〜20分以上（ハンズオンには不向き）
--
-- 【前提条件】
--   - STEP1〜STEP4 が完了していること
--   - PDF ファイルをステージにアップロード済みであること
--     （アップロード方法は STEP 6-2 を参照）
-- 【実行ロール】ACCOUNTADMIN
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE KUMAMOTO_OPENDATA;
USE SCHEMA PUBLIC;
USE WAREHOUSE COMPUTE_WH;


-- ============================================================
-- STEP 6-1: PDF 格納用の内部ステージ作成
-- ============================================================
-- ENCRYPTION = SNOWFLAKE_SSE（サーバーサイド暗号化）が必須。
-- デフォルトのクライアントサイド暗号化では AI_PARSE_DOCUMENT が動作しない。
-- DIRECTORY = TRUE でステージ上のファイルを一覧取得できるようになる。

CREATE OR REPLACE STAGE KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_STAGE
    DIRECTORY  = (ENABLE = TRUE)
    ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')   -- ← AI_PARSE_DOCUMENT に必須
    COMMENT    = '熊本市政策文書 PDF 格納ステージ';

SHOW STAGES IN SCHEMA KUMAMOTO_OPENDATA.PUBLIC;


-- ============================================================
-- STEP 6-2: PDF ファイルのアップロード
-- ============================================================
-- 以下のいずれかの方法でPDFをアップロードしてください。
--
-- 【方法 A: Snowsight UI（推奨）】
--   1. 左メニュー「Data」→「Databases」
--   2. KUMAMOTO_OPENDATA → PUBLIC → Stages → KUMAMOTO_DOCS_STAGE
--   3. 「+ Files」をクリックし、PDF をドラッグ＆ドロップ
--
-- 【方法 B: SnowSQL の PUT コマンド】
--   PUT file:///path/to/Kumamoto_kyoudousankaku.pdf
--       @KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_STAGE
--       OVERWRITE=TRUE AUTO_COMPRESS=FALSE;
--
-- ⚠️ アップロード後、必ず REFRESH を実行してから次へ進むこと

ALTER STAGE KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_STAGE REFRESH;
LS @KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_STAGE;
-- 期待値: Kumamoto_kyoudousankaku.pdf が表示されること


-- ============================================================
-- STEP 6-3: [STAGE 1] AI_PARSE_DOCUMENT でテキスト抽出
-- ============================================================
-- AI_PARSE_DOCUMENT: PDF からテキスト・レイアウト情報を抽出する Cortex AI 関数
--
-- 【重要】ファイルの指定方法:
--   TO_FILE('@ステージ名', 'ファイル名') を使う
--   ※ BUILD_SCOPED_FILE_URL は AI_PARSE_DOCUMENT では使用不可
--
-- 【処理モード】
--   LAYOUT モード: 文書の構造（見出し・段落・表）を保持してテキスト抽出
--                  通常の文書はこちらを使用（推奨）
--   OCR モード   : スキャン画像の PDF に使用
--
-- 【KUMAMOTO_DOCS_PARSED テーブル】
--   PDF 1ファイル = 1レコードで全文テキストを格納する中間テーブル
--   STAGE 1 の結果をここに保存し、STAGE 2 で再利用できる

CREATE OR REPLACE TABLE KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_PARSED (
    FILE_NAME  VARCHAR            COMMENT 'PDFファイル名（拡張子なし）',
    FILE_PATH  VARCHAR            COMMENT 'ステージ上のファイルパス',
    FULL_TEXT  VARCHAR            COMMENT 'AI_PARSE_DOCUMENT で抽出した全文テキスト',
    PARSED_AT  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = '熊本市政策文書 PDF のテキスト抽出結果（1ファイル = 1レコード）';

-- AI_PARSE_DOCUMENT でテキストを抽出して挿入
-- ⏱ 処理時間の目安: 約30〜60秒（3MBのPDFの場合）
INSERT INTO KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_PARSED
    (FILE_NAME, FILE_PATH, FULL_TEXT)
SELECT
    'Kumamoto_kyoudousankaku'                                   AS FILE_NAME,
    'Kumamoto_kyoudousankaku.pdf'                               AS FILE_PATH,
    AI_PARSE_DOCUMENT(
        TO_FILE('@KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_STAGE',
                'Kumamoto_kyoudousankaku.pdf'),
        {'mode': 'LAYOUT'}                  -- 文書構造を保持して抽出
    ):content::VARCHAR                                          AS FULL_TEXT;

-- 抽出結果の確認
-- 期待値: 1行、数万文字のテキストが抽出されていること
SELECT
    FILE_NAME,
    LENGTH(FULL_TEXT)    AS total_chars,
    LEFT(FULL_TEXT, 300) AS text_preview
FROM KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_PARSED;


-- ============================================================
-- STEP 6-4: [STAGE 2] テキストをチャンクに分割
-- ============================================================
-- Cortex Search は「チャンク（テキストの断片）」単位で意味検索を行う。
-- 1つの PDF をそのまま1レコードにすると検索精度が落ちるため、
-- 段落・セクション単位に分割する。
--
-- 【SPLIT_TEXT_RECURSIVE_CHARACTER の引数】
--   第1引数: 分割対象のテキスト
--   第2引数: 'markdown' = 見出し(##)・改行などで区切って分割
--   第3引数: チャンクサイズ（最大文字数）
--   第4引数: オーバーラップ（前後のチャンクと共有する文字数）
--            → 文脈の連続性を保つために前後で少し重ねる
--
-- 【KUMAMOTO_DOCS_CHUNKS テーブル】
--   1チャンク = 1レコード。Cortex Search の検索インデックスの元データ。

CREATE OR REPLACE TABLE KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_CHUNKS (
    CHUNK_ID    VARCHAR    COMMENT 'チャンクの一意ID（ファイル名_連番）',
    FILE_NAME   VARCHAR    COMMENT 'PDFファイル名（拡張子なし）',
    CHUNK_INDEX INT        COMMENT 'ドキュメント内のチャンク番号',
    CHUNK_TEXT  VARCHAR    COMMENT 'チャンクのテキスト（Cortex Search の検索対象列）'
)
COMMENT = '熊本市政策文書のテキストチャンク（Cortex Search 用）';

-- KUMAMOTO_DOCS_PARSED のテキストを分割してチャンクを挿入
INSERT INTO KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_CHUNKS
    (CHUNK_ID, FILE_NAME, CHUNK_INDEX, CHUNK_TEXT)
SELECT
    p.FILE_NAME || '_' || LPAD(c.index::VARCHAR, 4, '0') AS CHUNK_ID,
    p.FILE_NAME,
    c.index::INT                                          AS CHUNK_INDEX,
    c.value::VARCHAR                                      AS CHUNK_TEXT
FROM KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_PARSED p,
LATERAL FLATTEN(
    input => SNOWFLAKE.CORTEX.SPLIT_TEXT_RECURSIVE_CHARACTER(
        p.FULL_TEXT,
        'markdown',  -- Markdown 形式の区切り文字（見出し・改行）で分割
        500,         -- 1チャンク最大500文字
        50           -- 前後50文字のオーバーラップ（文脈の連続性を保持）
    )
) c
WHERE c.value::VARCHAR IS NOT NULL
  AND LENGTH(TRIM(c.value::VARCHAR)) > 30;  -- 短すぎるチャンクを除外

-- チャンク結果の確認
-- 期待値: 100〜200チャンク程度
SELECT
    COUNT(*)                     AS chunk_count,
    AVG(LENGTH(CHUNK_TEXT))::INT AS avg_chars,
    MIN(LENGTH(CHUNK_TEXT))      AS min_chars,
    MAX(LENGTH(CHUNK_TEXT))      AS max_chars
FROM KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_CHUNKS;

-- 最初の3チャンクを確認
SELECT CHUNK_ID, CHUNK_INDEX, LEFT(CHUNK_TEXT, 150) AS chunk_preview
FROM KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_CHUNKS
ORDER BY CHUNK_INDEX
LIMIT 3;


-- ============================================================
-- STEP 6-5: Cortex Search Service の作成
-- ============================================================
-- KUMAMOTO_DOCS_CHUNKS テーブルをもとに意味検索サービスを作成する。
-- Cortex Search はテキストをベクトル（埋め込み）に変換して保存し、
-- クエリも同様にベクトル化して意味的に近いチャンクを返す。
--
-- 【パラメータ】
--   ON CHUNK_TEXT    : 検索・ベクトル化の対象列
--   ATTRIBUTES       : フィルタリングや結果表示に使用する列
--   TARGET_LAG       : ソーステーブルが更新された際の同期間隔

CREATE OR REPLACE CORTEX SEARCH SERVICE KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_SEARCH
    ON CHUNK_TEXT
    ATTRIBUTES FILE_NAME, CHUNK_INDEX
    WAREHOUSE  = COMPUTE_WH
    TARGET_LAG = '1 day'
    COMMENT    = '熊本市男女共同参画企業意識実態調査の全文意味検索サービス'
    AS (
        SELECT CHUNK_ID, FILE_NAME, CHUNK_INDEX, CHUNK_TEXT
        FROM KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_CHUNKS
    );

SHOW CORTEX SEARCH SERVICES IN SCHEMA KUMAMOTO_OPENDATA.PUBLIC;

-- アクセス権限付与
GRANT USAGE ON CORTEX SEARCH SERVICE KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_SEARCH TO ROLE PUBLIC;

-- 動作テスト: SEARCH_PREVIEW で意味検索が機能することを確認
SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_SEARCH',
        '{
            "query": "女性管理職の状況",
            "columns": ["FILE_NAME", "CHUNK_TEXT"],
            "limit": 2
        }'
    )
)['results'] AS search_results;


-- ============================================================
-- STEP 6-6: Cortex Agent に Cortex Search ツールを追加
-- ============================================================
-- 既存の Agent を更新し、Cortex Search ツールを追加する。
-- 更新後は Tool 1（統計データ）と Tool 2（文書検索）の2ツール構成になる。

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
        - 熊本市男女共同参画企業意識・実態調査（令和5年度）:
          市内事業所の女性活躍・ワーク・ライフ・バランスの実態

        ツールの使い分け指針:
        - 数値・統計・グラフが必要な質問 → query_kumamoto_stats を使用
        - 女性活躍・男女共同参画・育休・管理職に関する質問 → search_kumamoto_docs を使用

        回答は日本語で分かりやすく答えてください。

      sample_questions:
        - question: "熊本市の月次推計人口の推移を教えて"
        - question: "熊本市電の年度別乗車人数と収入はどのくらいか"
        - question: "熊本市内企業の女性管理職の状況を教えて"
        - question: "育児休業の取得状況はどうなっていますか"
        - question: "熊本市の火災件数と交通事故件数を年次で比較して"
        - question: "市内事業所のワーク・ライフ・バランスへの取組は"
        - question: "市電の乗車人数と空港の乗降客数を月次で比較して"
        - question: "熊本市内企業の男女平均賃金の状況を教えて"
        - question: "有効求人倍率の直近の推移を教えて"
        - question: "ポジティブ・アクションに取り組んでいる企業はどのくらいか"

    tools:
      # Tool 1: 統計テーブルへの自然言語 SQL 生成
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
            市内事業所の女性活躍推進・育児休業・ワークライフバランス・
            男女平均賃金・ポジティブアクションに関する質問に使用する。

    tool_resources:
      query_kumamoto_stats:
        semantic_view: KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_CITY_STATISTICS

      search_kumamoto_docs:
        name: KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DOCS_SEARCH
        max_results: "5"
        title_column: FILE_NAME
        id_column: CHUNK_ID
    $$;

SHOW AGENTS IN SCHEMA KUMAMOTO_OPENDATA.PUBLIC;


-- ============================================================
-- STEP 6 完了
-- ============================================================
-- ✅ KUMAMOTO_DOCS_STAGE  : PDF 格納ステージ（SSE暗号化）
-- ✅ KUMAMOTO_DOCS_PARSED : テキスト抽出結果テーブル（1ファイル1レコード）
-- ✅ KUMAMOTO_DOCS_CHUNKS : チャンク分割テーブル（約150チャンク）
-- ✅ KUMAMOTO_DOCS_SEARCH : Cortex Search Service
-- ✅ KUMAMOTO_CITY_STATS_AGENT: Cortex Analyst + Cortex Search の2ツール構成
--
-- 【Snowflake Intelligence での確認】
-- 「熊本市統計アナリスト」を開き、以下の質問を試してください:
--   - 「市内企業の女性管理職の状況を教えて」（文書検索）
--   - 「有効求人倍率の推移と市内企業の取組は?」（統計 + 文書の組み合わせ）
-- ============================================================
