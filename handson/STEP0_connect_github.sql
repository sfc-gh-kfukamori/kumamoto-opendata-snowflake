-- ============================================================
-- Snowflake Intelligence Hands-on Lab
-- STEP 0: GitHub リポジトリの Snowflake 連携
-- ============================================================
--
-- 【このステップでやること】
--   GitHub リポジトリを Snowflake に接続し、
--   Snowsight の Worksheets・Notebooks から
--   リポジトリのファイルを直接実行できるようにします。
--
-- 【Snowflake Git Repository 連携とは?】
--   Snowflake はリモート Git リポジトリ（GitHub等）を
--   クローンして Snowflake 内部ステージとして保持できます。
--   これにより以下が可能になります:
--     - EXECUTE IMMEDIATE FROM で SQL ファイルをリポジトリから直接実行
--     - Snowflake Notebooks から Python コードを直接インポート
--     - コードの変更を FETCH コマンドで同期
--
-- 【前提条件】
--   - GitHub のアカウントをお持ちであること
--   - (推奨) GitHub の Personal Access Token (PAT) を作成済みであること
--     作成方法: https://docs.github.com/ja/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens
--     必要なスコープ: repo（プライベートリポジトリの場合）/ public_repo（パブリックの場合）
--
-- 【実行ロール】ACCOUNTADMIN
-- 【接続先リポジトリ】
--   https://github.com/sfc-gh-kfukamori/kumamoto-opendata-snowflake
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE KUMAMOTO_OPENDATA;
USE SCHEMA PUBLIC;


-- ============================================================
-- STEP 0-1: GitHub 認証情報の Secret 作成
-- ============================================================
-- GitHub の Personal Access Token (PAT) を Snowflake の Secret として
-- 安全に保存します。
--
-- 【PAT の作成手順】
--   1. GitHub にログイン
--   2. Settings → Developer settings → Personal access tokens → Tokens (classic)
--   3. Generate new token をクリック
--   4. 有効期限を設定し、スコープで「repo」にチェック
--   5. 生成されたトークン（ghp_xxxx...）をコピー
--
-- ⚠️ PAT は一度しか表示されないのでコピーしておいてください
--
-- 【パブリックリポジトリの場合】
--   PAT なしでも接続できますが、API レートリミット対策のため
--   PAT を使用することを推奨します。

CREATE OR REPLACE SECRET KUMAMOTO_OPENDATA.PUBLIC.GITHUB_PAT_SECRET
    TYPE     = password
    USERNAME = '<あなたのGitHubユーザー名>'       -- 例: sfc-gh-kfukamori
    PASSWORD = '<あなたのPersonal Access Token>'  -- 例: ghp_xxxxxxxxxxxxxxxxxxxx
    COMMENT  = 'GitHub Personal Access Token for kumamoto-opendata-snowflake repo';

-- Secret の作成確認
SHOW SECRETS IN SCHEMA KUMAMOTO_OPENDATA.PUBLIC;


-- ============================================================
-- STEP 0-2: API Integration の作成
-- ============================================================
-- Snowflake が GitHub API にアクセスするための統合オブジェクトを作成します。
--
-- API_ALLOWED_PREFIXES: アクセスを許可する GitHub URL のプレフィックス
-- ALLOWED_AUTHENTICATION_SECRETS: 使用できる Secret を指定

CREATE OR REPLACE API INTEGRATION GITHUB_API_INTEGRATION
    API_PROVIDER                = git_https_api
    API_ALLOWED_PREFIXES        = ('https://github.com/sfc-gh-kfukamori/')
    ALLOWED_AUTHENTICATION_SECRETS = (KUMAMOTO_OPENDATA.PUBLIC.GITHUB_PAT_SECRET)
    ENABLED                     = TRUE
    COMMENT                     = 'GitHub API Integration for sfc-gh-kfukamori organization';

-- API Integration の作成確認
SHOW INTEGRATIONS LIKE 'GITHUB_API_INTEGRATION';


-- ============================================================
-- STEP 0-3: Git Repository オブジェクトの作成
-- ============================================================
-- Snowflake 内に GitHub リポジトリのクローンを作成します。
-- このオブジェクトは内部ステージ（@KUMAMOTO_DEMO_REPO）として扱われます。

CREATE OR REPLACE GIT REPOSITORY KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DEMO_REPO
    ORIGIN          = 'https://github.com/sfc-gh-kfukamori/kumamoto-opendata-snowflake.git'
    API_INTEGRATION = GITHUB_API_INTEGRATION
    GIT_CREDENTIALS = KUMAMOTO_OPENDATA.PUBLIC.GITHUB_PAT_SECRET
    COMMENT         = '熊本市オープンデータ × Snowflake Intelligence デモリポジトリ';

-- Git Repository の作成確認
SHOW GIT REPOSITORIES IN SCHEMA KUMAMOTO_OPENDATA.PUBLIC;


-- ============================================================
-- STEP 0-4: 最新コードの取得（フェッチ）
-- ============================================================
-- リモートの GitHub から最新のコードを Snowflake に同期します。
-- リポジトリのコードが更新されたときは、このコマンドを再実行してください。

ALTER GIT REPOSITORY KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DEMO_REPO FETCH;

-- フェッチ後、ブランチ一覧を確認
SHOW GIT BRANCHES IN KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DEMO_REPO;


-- ============================================================
-- STEP 0-5: リポジトリ内のファイル一覧確認
-- ============================================================
-- ステージとして参照して、利用可能なファイルを確認します。

-- handson ディレクトリのファイル一覧
LS @KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DEMO_REPO/branches/master/handson/;

-- sproc ディレクトリのファイル一覧（Python コード）
LS @KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DEMO_REPO/branches/master/sproc/;


-- ============================================================
-- STEP 0-6: リポジトリからの SQL ファイル実行（使い方の確認）
-- ============================================================
-- EXECUTE IMMEDIATE FROM コマンドで、リポジトリ内の SQL ファイルを
-- Snowsight から直接実行できます。
--
-- 構文:
--   EXECUTE IMMEDIATE FROM @<git_repo>/branches/<branch>/<path/to/file.sql>
--
-- 【注意】
--   - STEP1〜STEP5 のハンズオンファイルを実行する場合は
--     ファイル内の USE ROLE / WAREHOUSE 等のコンテキスト設定が
--     自動的に適用されます。
--   - 各 STEP は順番に実行してください（依存関係があります）

-- ハンズオン STEP1（インフラ設定）を実行する場合:
-- EXECUTE IMMEDIATE FROM @KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DEMO_REPO/branches/master/handson/STEP1_setup.sql;

-- ハンズオン STEP2（データ取込）を実行する場合:
-- EXECUTE IMMEDIATE FROM @KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DEMO_REPO/branches/master/handson/STEP2_ingest_data.sql;

-- ハンズオン STEP3（Semantic View 作成）を実行する場合:
-- EXECUTE IMMEDIATE FROM @KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DEMO_REPO/branches/master/handson/STEP3_semantic_view.sql;

-- ハンズオン STEP4（Cortex Agent 作成）を実行する場合:
-- EXECUTE IMMEDIATE FROM @KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DEMO_REPO/branches/master/handson/STEP4_cortex_agent.sql;

-- ハンズオン STEP5（デモクエリ）を実行する場合:
-- EXECUTE IMMEDIATE FROM @KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DEMO_REPO/branches/master/handson/STEP5_demo_queries.sql;


-- ============================================================
-- STEP 0 完了
-- ============================================================
-- ✅ GitHub リポジトリが Snowflake に接続されました
-- ✅ @KUMAMOTO_DEMO_REPO ステージからファイルを参照・実行できます
--
-- 次のステップ:
--   A. ハンズオンを実行する場合: STEP1〜STEP5 を順番に実行
--   B. Notebooks で使用する場合: GITHUB_WORKSPACE_GUIDE.md を参照
-- ============================================================
