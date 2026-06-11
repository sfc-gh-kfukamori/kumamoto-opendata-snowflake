# GitHub リポジトリ × Snowflake ワークスペース連携ガイド

GitHub リポジトリのコードを Snowflake のワークスペース（Worksheets / Notebooks）から
直接実行・参照する方法をまとめたガイドです。

---

## 概要

Snowflake の **Git Repository 連携**機能を使うと、GitHub のリポジトリを
Snowflake 内部ステージとして保持でき、以下が可能になります：

| 機能 | 説明 |
|---|---|
| SQL ファイルの直接実行 | `EXECUTE IMMEDIATE FROM @git_repo/...` でコピペ不要 |
| Notebooks からのコード参照 | Python コードを GitHub から直接インポート |
| コード更新の同期 | `ALTER GIT REPOSITORY ... FETCH` でいつでも最新化 |

---

## アーキテクチャ

```
GitHub
  github.com/sfc-gh-kfukamori/kumamoto-opendata-snowflake
         │
         │  HTTPS (API Integration)
         ▼
Snowflake
  @KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DEMO_REPO  ← Git Repository ステージ
         │
         ├── /branches/master/handson/STEP1_setup.sql
         ├── /branches/master/handson/STEP2_ingest_data.sql
         ├── /branches/master/handson/STEP3_semantic_view.sql
         ├── /branches/master/handson/STEP4_cortex_agent.sql
         ├── /branches/master/handson/STEP5_demo_queries.sql
         ├── /branches/master/sproc/ingest_kumamoto.py
         └── /branches/master/sproc/generate_db_descriptions.py
         │
         ├── Worksheets → EXECUTE IMMEDIATE FROM @git_repo/...
         └── Notebooks  → import from stage
```

---

## セットアップ手順

`handson/STEP0_connect_github.sql` を Snowsight で実行してください。

### 必要なオブジェクト

| オブジェクト | 種類 | 役割 |
|---|---|---|
| `GITHUB_PAT_SECRET` | Secret | GitHub 認証情報（PAT）を安全に保存 |
| `GITHUB_API_INTEGRATION` | API Integration | Snowflake → GitHub API の通信を許可 |
| `KUMAMOTO_DEMO_REPO` | Git Repository | GitHub リポジトリのクローン（ステージ） |

### GitHub Personal Access Token の作成

1. GitHub にログイン
2. **Settings** → **Developer settings** → **Personal access tokens** → **Tokens (classic)**
3. **Generate new token** をクリック
4. 以下を設定：
   - Note: `Snowflake Git Integration`
   - Expiration: 任意（90 days 推奨）
   - Scope: `repo`（プライベートリポジトリ）または `public_repo`（パブリック）
5. 生成されたトークン（`ghp_xxxxx...`）をコピー

> ⚠️ PAT は一度しか表示されません。必ずコピーしておいてください。

---

## 使い方 1: Worksheets から SQL ファイルを実行

Git Repository に接続後、`EXECUTE IMMEDIATE FROM` コマンドで
リポジトリ内の SQL ファイルを直接実行できます。

```sql
-- ハンズオン STEP1（インフラ設定）を実行
EXECUTE IMMEDIATE FROM
    @KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DEMO_REPO/branches/master/handson/STEP1_setup.sql;

-- ハンズオン STEP2（データ取込）を実行
EXECUTE IMMEDIATE FROM
    @KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DEMO_REPO/branches/master/handson/STEP2_ingest_data.sql;

-- ハンズオン STEP3（Semantic View 作成）を実行
EXECUTE IMMEDIATE FROM
    @KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DEMO_REPO/branches/master/handson/STEP3_semantic_view.sql;

-- ハンズオン STEP4（Cortex Agent 作成）を実行
EXECUTE IMMEDIATE FROM
    @KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DEMO_REPO/branches/master/handson/STEP4_cortex_agent.sql;

-- ハンズオン STEP5（デモクエリ）を実行
EXECUTE IMMEDIATE FROM
    @KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DEMO_REPO/branches/master/handson/STEP5_demo_queries.sql;
```

### コードの更新同期

GitHub でコードが更新されたら、以下のコマンドで Snowflake 側を最新化します：

```sql
ALTER GIT REPOSITORY KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DEMO_REPO FETCH;
```

---

## 使い方 2: Snowflake Notebooks から Python コードを参照

Snowflake Notebooks（Python セル）から、リポジトリ内の Python ファイルを
直接インポートして使用できます。

### Notebook セルでの使い方

```python
# ステージからファイルの内容を取得して実行
import sys
from snowflake.snowpark.context import get_active_session

session = get_active_session()

# Git リポジトリから Python ファイルを取得
files = session.file.get(
    '@KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DEMO_REPO/branches/master/sproc/',
    '/tmp/sproc/'
)

# sproc を一時的にパスに追加してインポート
sys.path.insert(0, '/tmp/sproc')
import ingest_kumamoto
import generate_db_descriptions
```

### Notebook での Git Repository 参照（UI から）

1. Snowsight で **Notebooks** を開く
2. 新規 Notebook を作成
3. Notebook の **Files** タブを開く
4. **Add from stage** → `@KUMAMOTO_DEMO_REPO/branches/master/sproc/` を選択
5. `ingest_kumamoto.py` や `generate_db_descriptions.py` を追加
6. Python セルで `import ingest_kumamoto` として使用

---

## 使い方 3: Snowflake CLI からの実行

Snowflake CLI（`snow` コマンド）がインストールされている場合、
コマンドラインからリポジトリのファイルを一括実行できます。

```bash
# リポジトリの最新化
snow git fetch KUMAMOTO_DEMO_REPO \
    --database KUMAMOTO_OPENDATA \
    --schema PUBLIC

# handson ディレクトリの SQL ファイルを全て実行
snow git execute \
    @KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DEMO_REPO/branches/master/handson/ \
    --database KUMAMOTO_OPENDATA \
    --schema PUBLIC

# 特定のファイルだけ実行
snow git execute \
    @KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DEMO_REPO/branches/master/handson/STEP1_setup.sql
```

> Snowflake CLI のインストール方法: https://docs.snowflake.com/en/developer-guide/snowflake-cli/installation/installation

---

## Snowsight での Git Repository 確認方法

1. Snowsight にログイン
2. 左メニュー **「Data」** → **「Databases」** をクリック
3. `KUMAMOTO_OPENDATA` → `PUBLIC` → **「Git Repositories」** を選択
4. `KUMAMOTO_DEMO_REPO` をクリックすると、ブランチ・ファイル一覧が表示される

または SQL で確認：
```sql
-- ブランチ一覧
SHOW GIT BRANCHES IN KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DEMO_REPO;

-- ファイル一覧（handson/）
LS @KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DEMO_REPO/branches/master/handson/;

-- ファイルの内容を確認
SELECT $1 FROM @KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DEMO_REPO/branches/master/handson/STEP1_setup.sql
    (FILE_FORMAT => (TYPE = CSV FIELD_DELIMITER = NONE RECORD_DELIMITER = '\n'));
```

---

## トラブルシューティング

| 症状 | 対処 |
|---|---|
| `Invalid credentials` エラー | PAT の有効期限・スコープを確認。PAT を再生成してSecretを更新 |
| `FETCH` に失敗する | API Integration の `API_ALLOWED_PREFIXES` が正しいか確認 |
| ファイルが見つからない | `ALTER GIT REPOSITORY ... FETCH` を実行してから再試行 |
| `EXECUTE IMMEDIATE FROM` でエラー | SQL ファイル内の USE ROLE / WAREHOUSE 設定を確認 |
| PAT なしで接続したい（パブリックリポジトリ） | `GIT_CREDENTIALS` を省略し、`ALLOWED_AUTHENTICATION_SECRETS = ()` に変更 |

### パブリックリポジトリへの認証なし接続（代替手順）

リポジトリがパブリックの場合、PAT なしでも接続できます：

```sql
-- 認証なしの API Integration
CREATE OR REPLACE API INTEGRATION GITHUB_API_INTEGRATION_PUBLIC
    API_PROVIDER         = git_https_api
    API_ALLOWED_PREFIXES = ('https://github.com/sfc-gh-kfukamori/')
    ENABLED              = TRUE;

-- 認証なしの Git Repository
CREATE OR REPLACE GIT REPOSITORY KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_DEMO_REPO
    ORIGIN          = 'https://github.com/sfc-gh-kfukamori/kumamoto-opendata-snowflake.git'
    API_INTEGRATION = GITHUB_API_INTEGRATION_PUBLIC;
    -- GIT_CREDENTIALS は省略
```

---

## リポジトリ構成

```
kumamoto-opendata-snowflake/
│
├── handson/                    ← ハンズオン用 SQL ファイル（Worksheets で実行）
│   ├── README.md               手順書
│   ├── STEP0_connect_github.sql GitHub 連携設定（このガイドの内容）
│   ├── STEP1_setup.sql         インフラ設定
│   ├── STEP2_ingest_data.sql   データ取込
│   ├── STEP3_semantic_view.sql Semantic View 作成
│   ├── STEP4_cortex_agent.sql  Cortex Agent 作成
│   └── STEP5_demo_queries.sql  デモクエリ
│
├── sproc/                      ← Python ストアドプロシージャ（Notebooks で参照）
│   ├── ingest_kumamoto.py      データ取込 SP（参照・編集用）
│   └── generate_db_descriptions.py AI説明生成 SP（参照・編集用）
│
├── semantic_view/              ← Semantic View 定義
│   └── kumamoto_city_statistics_semantic_model.yaml
│
└── sql/                        ← 管理・参照用 SQL
    ├── 01_setup.sql ～ 06_create_cortex_agent.sql
```
