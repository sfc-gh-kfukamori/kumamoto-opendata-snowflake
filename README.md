# 熊本市オープンデータ × Snowflake Intelligence Demo

熊本市のオープンデータカタログサイト（BODIK ODCS）から CKAN API 経由でデータを取得し、
Snowflake に格納。さらに Snowflake Cortex AI により全テーブル・カラムに日本語の
Description を自動付与するエンドツーエンドのデモです。

---

## デモの流れ

```
┌──────────────────────────────────────────────────────────────────┐
│  熊本市オープンデータカタログ (odcs.bodik.jp/431001)              │
│  ↓ CKAN API (data.bodik.jp)                                      │
│    84 データセット / 92 CSV ファイル                              │
└──────────────────────┬───────────────────────────────────────────┘
                       │ External Network Access (HTTPS)
                       ▼
┌──────────────────────────────────────────────────────────────────┐
│  Snowflake                                                        │
│                                                                   │
│  Step 1: INGEST_KUMAMOTO_OPENDATA()                               │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ Snowpark Python Stored Procedure                           │  │
│  │  1. CKAN API で全データセット一覧を取得                     │  │
│  │  2. CSV ダウンロード（CP932 → UTF-8 自動変換）              │  │
│  │  3. テーブル作成 & データ投入（92 テーブル）                │  │
│  │  4. DATASET_CATALOG にメタ情報を記録                        │  │
│  └────────────────────────────────────────────────────────────┘  │
│               ↓                                                   │
│  KUMAMOTO_OPENDATA.PUBLIC                                         │
│    T02031_POPULATION_MONTHLY          (月次推計人口)              │
│    T11051_TRAM_RIDERSHIP_REVENUE_MONTHLY (市電月次データ)         │
│    FREE_WIFI_SPOTS                    (フリーWi-Fiスポット)       │
│    ... 計 92 テーブル + DATASET_CATALOG                           │
│               ↓                                                   │
│  Step 2: GENERATE_DB_DESCRIPTIONS()                               │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ Snowpark Python Stored Procedure                           │  │
│  │  1. AI_GENERATE_TABLE_DESC でテーブル・カラムの説明を生成   │  │
│  │     （LLM がメタデータ・サンプルデータを解析）              │  │
│  │  2. CORTEX.TRANSLATE で英語説明 → 日本語に翻訳             │  │
│  │  3. ALTER TABLE SET COMMENT でコメントを設定               │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

---

## リポジトリ構成

```
kumamoto-opendata-snowflake/
├── README.md                        # このファイル
├── sql/
│   ├── 01_setup.sql                 # インフラ設定（DB / Network Rule / EAI）
│   ├── 02_ingest_sproc.sql          # データ取込 SP デプロイ
│   ├── 03_ai_desc_sproc.sql         # AI 説明生成 SP デプロイ
│   └── 04_run_demo.sql              # デモ実行スクリプト
└── sproc/
    ├── ingest_kumamoto.py           # 取込 SP ソース（コメント付き参照用）
    └── generate_db_descriptions.py  # AI 説明生成 SP ソース（コメント付き参照用）
```

> `sql/` 配下の SQL ファイルを番号順に実行するだけでデモが完成します。  
> `sproc/` 配下は SQL に埋め込まれた Python コードの参照・編集用です。

---

## セットアップ手順

### 前提条件

| 項目 | 要件 |
|---|---|
| Snowflake ロール | `ACCOUNTADMIN`（Network Rule / EAI 作成に必要） |
| Snowflake 機能 | Snowpark Python、Cortex AI（`AI_GENERATE_TABLE_DESC`）が利用可能なリージョン |
| Cortex ロール | `SNOWFLAKE.CORTEX_USER` データベースロール |

### 実行手順

```sql
-- 1. インフラ設定（DB・Network Rule・External Access Integration）
--    ロール: ACCOUNTADMIN
-- ファイル: sql/01_setup.sql

-- 2. データ取込 SP のデプロイ
-- ファイル: sql/02_ingest_sproc.sql

-- 3. AI 説明生成 SP のデプロイ
-- ファイル: sql/03_ai_desc_sproc.sql

-- 4. デモ実行
-- ファイル: sql/04_run_demo.sql
```

---

## ストアドプロシージャ リファレンス

### `INGEST_KUMAMOTO_OPENDATA()`

熊本市のオープンデータを CKAN API から取得して Snowflake テーブルに格納する。

```sql
CALL KUMAMOTO_OPENDATA.PUBLIC.INGEST_KUMAMOTO_OPENDATA();
```

| 項目 | 内容 |
|---|---|
| 取込件数 | 92 CSV ファイル（84 データセット） |
| 実行時間の目安 | 約 5 分（XSmall WH） |
| 戻り値 | `{"ok": 92, "error": 0, "skip": 0, ...}` の JSON |

#### 取込テーブルの命名規則

| カテゴリ | テーブル名の例 |
|---|---|
| 人口統計 | `T02031_POPULATION_MONTHLY` |
| 交通 | `T11051_TRAM_RIDERSHIP_REVENUE_MONTHLY` |
| 保健医療 | `T13033_CITY_HOSPITAL_PATIENTS` |
| 教育文化 | `T18172_MUSEUM_VISITORS_MONTHLY` |
| 特殊 | `FREE_WIFI_SPOTS`, `BICYCLE_PARKING` |

---

### `GENERATE_DB_DESCRIPTIONS(P_DATABASE_NAME, P_OVERWRITE_EXISTING, P_USE_TABLE_DATA)`

指定 DB の全テーブル・ビューとカラムに AI 生成の日本語 Description を付与する。

```sql
-- 未設定のもののみ生成（推奨）
CALL KUMAMOTO_OPENDATA.PUBLIC.GENERATE_DB_DESCRIPTIONS(
    'KUMAMOTO_OPENDATA', FALSE, FALSE
);

-- 全件上書き再生成（実データで精度向上）
CALL KUMAMOTO_OPENDATA.PUBLIC.GENERATE_DB_DESCRIPTIONS(
    'KUMAMOTO_OPENDATA', TRUE, TRUE
);
```

| パラメータ | 型 | 説明 |
|---|---|---|
| `P_DATABASE_NAME` | STRING | 対象データベース名 |
| `P_OVERWRITE_EXISTING` | BOOLEAN | `TRUE`: 既存を上書き / `FALSE`: 未設定のみ生成 |
| `P_USE_TABLE_DATA` | BOOLEAN | `TRUE`: 実データをサンプリング（精度↑・コスト↑）|

---

## 技術的ポイント

### 1. External Network Access

通常、Snowflake 内部から外部 API を直接呼び出すことはできません。
**External Network Access** を設定することで、Python ストアドプロシージャが
`requests` ライブラリを使って外部 HTTP エンドポイントを呼び出せるようになります。

```sql
-- 接続先ホストを許可するルールを定義
CREATE OR REPLACE NETWORK RULE BODIK_NETWORK_RULE
    TYPE = HOST_PORT  MODE = EGRESS
    VALUE_LIST = ('data.bodik.jp');

-- SP に紐付ける統合オブジェクトを作成
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION BODIK_EXTERNAL_ACCESS
    ALLOWED_NETWORK_RULES = (BODIK_NETWORK_RULE)
    ENABLED = TRUE;
```

```python
# SP の宣言時に指定するだけで requests が使えるようになる
CREATE PROCEDURE ...
    EXTERNAL_ACCESS_INTEGRATIONS = (BODIK_EXTERNAL_ACCESS)
AS $$
import requests
resp = requests.get("https://data.bodik.jp/api/3/action/package_search", ...)
```

### 2. CKAN API の構造

BODIK ODCS は **CKAN**（オープンソースのオープンデータポータル）をベースにしています。
熊本市のデータは `data.bodik.jp` の CKAN API で公開されています。

```
# 組織のデータセット一覧を取得
GET https://data.bodik.jp/api/3/action/package_search
    ?fq=organization:431001&rows=100

# レスポンス構造
{
  "result": {
    "results": [
      {
        "name": "431001_t11050",
        "title": "T11050_熊本市電月次利用状況",
        "resources": [
          {
            "format": "CSV",
            "url": "https://data.bodik.jp/.../download/t11051_.csv"
          }
        ]
      }
    ]
  }
}
```

> `odcs.bodik.jp/431001`（カタログサイト）と `data.bodik.jp`（CKAN API）は
> 別ホストです。データ取得には `data.bodik.jp` を使います。

### 3. CP932 エンコーディングの自動検出

熊本市の CSV ファイルは **Shift-JIS（CP932）** エンコーディングで提供されています。
`requests.content`（バイト列）を受け取り、CP932 → UTF-8-sig → UTF-8 の順で
デコードを試みます。

```python
for enc in ("cp932", "utf-8-sig", "utf-8"):
    try:
        content = r.content.decode(enc)
        break
    except (UnicodeDecodeError, LookupError):
        continue
```

### 4. 日本語カラム名の保持

CSV の列名（`年度`, `乗車人数【人】` 等）は Snowflake の
**quoted identifier** としてそのまま保持します。

```python
# テーブル定義時にダブルクォートで囲む
cols_ddl = ", ".join([f'"{h}" VARCHAR' for h in headers])
# → "年度" VARCHAR, "月次" VARCHAR, "乗車人数【人】" VARCHAR

# クエリ時も同様にクォートが必要
SELECT "乗車人数【人】" FROM T11051_TRAM_RIDERSHIP_REVENUE_MONTHLY;
```

### 5. Snowpark Python でのデータ投入

`session.write_pandas()` は内部でステージを使うため権限問題が発生しやすいです。
代わりに `session.create_dataframe() + .write.save_as_table()` を使うことで
ステージレスにデータを投入できます。

```python
schema_def = StructType([StructField(h, StringType()) for h in headers])
snow_df    = session.create_dataframe(data_rows, schema=schema_def)
snow_df.write.mode("append").save_as_table([db, schema, table_name])
```

### 6. AI_GENERATE_TABLE_DESC + CORTEX.TRANSLATE

`AI_GENERATE_TABLE_DESC` は英語で説明を生成するため、
`CORTEX.TRANSLATE` で日本語に翻訳してから COMMENT として設定します。

```python
# 英語で説明を生成
result = session.sql(
    f"CALL AI_GENERATE_TABLE_DESC('{full_name}', "
    f"{{'describe_columns': true, 'use_table_data': true}})"
).collect()
output = json.loads(result[0][0])

# 日本語に翻訳
desc_en = output["TABLE"][0]["description"]
desc_ja = session.sql(
    f"SELECT SNOWFLAKE.CORTEX.TRANSLATE('{desc_en}', 'en', 'ja') AS t"
).collect()[0]["T"]

# コメントとして設定
session.sql(f"ALTER TABLE {table} SET COMMENT = '{desc_ja}'").collect()
```

> **AIの生成ミスへの対策**: AI が実在しないカラム名を返す場合があります。
> `INFORMATION_SCHEMA.COLUMNS` の実際のカラム名と照合し、存在しない場合はスキップします。

### 7. joblib.Parallel による並列処理

テーブル単位の Description 生成を並列化してスループットを向上させます。

```python
from joblib import Parallel, delayed
import multiprocessing

n_jobs  = min(multiprocessing.cpu_count(), len(tables), 8)
results = Parallel(n_jobs=n_jobs, backend="threading")(
    delayed(process_object)(session, db, schema, tbl, ...)
    for tbl in tables
)
```

> `threading` バックエンドを使用します。SQL 呼び出しは I/O バウンドな処理
> のため、Python の GIL があっても並列化の効果が得られます。

---

## データセット一覧

| カテゴリ | テーブル数 | 例 |
|---|---|---|
| 人口統計 (T02) | 10 | 月次推計人口、外国人住民、国勢調査 |
| 交通 (T11) | 10 | 市電・空港・JR・タクシー・駐車場 |
| 労働・福祉 (T12) | 12 | 雇用保険・求人・保育所・高齢者福祉 |
| 保健・医療 (T13) | 13 | 病院・診療所・ごみ処理・下水道 |
| 道路・インフラ (T14) | 8 | 橋りょう・都市計画道路 |
| 教育・文化 (T18) | 17 | 学校・図書館・博物館・動植物園 |
| 家計・物価 (T09) | 7 | 家計調査・小売物価 |
| その他 | 15 | 土地・商業・水道・安全・特殊ファイル |
| **合計** | **92** | |

---

## 注意事項

- `AI_GENERATE_TABLE_DESC` は Preview 機能（2025年8月時点）
- Cortex COMPLETE / TRANSLATE の利用には追加コストが発生します
- Network Rule / External Access Integration の作成には `ACCOUNTADMIN` 権限が必要です
- Cortex 機能が利用可能なリージョンかどうか事前にご確認ください
