# 熊本市オープンデータ × Snowflake Intelligence ハンズオン

## ハンズオンの概要

熊本市が公開しているオープンデータ統計（人口・交通・防災・文化・経済など）を
Snowflake に取り込み、**Snowflake Intelligence** から自然言語で問い合わせできる環境と、
統計データを可視化する **Streamlit ダッシュボード**を構築します。

**最終的にできること:**
- 「熊本市の月次推計人口の推移を教えて」（統計データ）
- 「市電の乗車人数と空港の乗降客数を月次で比較して」（統計データ横断）
- 「熊本市内企業の女性管理職の状況を教えて」（PDF 全文検索）
- 「育児休業の取得状況はどうなっていますか」（PDF 全文検索）
- 統計データを 6 カテゴリのグラフで可視化するダッシュボード

---

## ファイル構成

```
handson/
├── README.md                    ← このファイル
├── STEP0_connect_github.sql     GitHub リポジトリ連携（任意・事前準備）
├── STEP1_setup.sql              インフラ設定（DB・Network Rule・EAI）
├── STEP2_ingest_data.sql        データ取込 SP 作成・実行（92テーブル）
├── STEP3_semantic_view.sql      Semantic View 作成
├── STEP4_cortex_agent.sql       Cortex Agent 作成
├── STEP5_demo_queries.sql       動作確認クエリ
├── STEP6_cortex_search.sql      PDF + Cortex Search 追加（発展編）
└── STEP7_streamlit_dashboard.sql Streamlit ダッシュボード作成（発展編）
```

---

## 全体アーキテクチャ

```
┌──────────────────────────────────────────────────────────────┐
│  data.bodik.jp（CKAN API）                                   │
│  熊本市オープンデータ: 84 データセット / 92 CSV ファイル      │
└────────────────────┬─────────────────────────────────────────┘
                     │ HTTPS（External Network Access）
                     ▼
┌──────────────────────────────────────────────────────────────┐
│  Snowflake  KUMAMOTO_OPENDATA.PUBLIC                        │
│                                                              │
│  [STEP2] INGEST_KUMAMOTO_OPENDATA()  Snowpark Python SP    │
│    └→ 92 テーブル + DATASET_CATALOG                          │
│                                                              │
│  [STEP3] KUMAMOTO_CITY_STATISTICS  Semantic View            │
│    └→ 14 テーブル / 46 dim / 24 fact / 6 metric / 16 VQR    │
│                                                              │
│  [STEP4] KUMAMOTO_CITY_STATS_AGENT  Cortex Agent           │
│    ├→ Tool 1: cortex_analyst（Semantic View 経由）            │
│    └→ Tool 2: cortex_search（STEP6 追加後）                  │
│                                                              │
│  [STEP6] KUMAMOTO_DOCS_STAGE / PARSED / CHUNKS              │
│    └→ AI_PARSE_DOCUMENT → チャンク分割                       │
│       → KUMAMOTO_DOCS_SEARCH（Cortex Search Service）         │
│                                                              │
│  [STEP7] KUMAMOTO_DASHBOARD  Streamlit in Snowflake         │
│    └→ 92 テーブルを 6 カテゴリ・タブで可視化                 │
└──────────────────────────────────────────────────────────────┘
                     │
          ┌──────────┴──────────┐
          ▼                     ▼
┌──────────────────┐  ┌─────────────────────────┐
│ Snowflake        │  │ Streamlit ダッシュボード │
│ Intelligence     │  │ 人口/交通/防災/文化/経済 │
│ 「熊本市統計     │  │ /環境 の6タブグラフ      │
│  アナリスト」    │  └─────────────────────────┘
│ 自然言語問い合わせ│
└──────────────────┘
```

---

## 実行手順

### 事前準備

Snowsight にログインし、左メニューの **「Worksheets」** を開きます。
各 STEP のファイルを新しいワークシートに貼り付けて、**上から順に**実行してください。

---

### STEP 1: インフラ設定（`STEP1_setup.sql`）

**実行ロール:** ACCOUNTADMIN | **所要時間:** 約 1 分

| 作成するオブジェクト | 説明 |
|---|---|
| `KUMAMOTO_OPENDATA` データベース | データ格納先 |
| `BODIK_NETWORK_RULE` Network Rule | data.bodik.jp への通信を許可 |
| `BODIK_EXTERNAL_ACCESS` EAI | SP から外部 HTTP 通信を許可 |

> **ポイント:** Snowflake のストアドプロシージャは通常、外部ネットワークにアクセスできません。
> External Network Access を設定することで、CKAN API への直接アクセスが可能になります。

---

### STEP 2: データ取込（`STEP2_ingest_data.sql`）

**実行ロール:** ACCOUNTADMIN | **所要時間:** SP 作成: 数秒 / データ取込: **約 5 分**

1. Snowpark Python ストアドプロシージャ `INGEST_KUMAMOTO_OPENDATA` を作成
2. `CALL KUMAMOTO_OPENDATA.PUBLIC.INGEST_KUMAMOTO_OPENDATA()` を実行
3. 92 テーブル + `DATASET_CATALOG` が作成されることを確認

**期待される結果:**

| INGEST_STATUS | データセット数 | 総レコード数 |
|---|---|---|
| OK | 92 | 約 200,000+ |

> **ポイント:** CKAN API から CSV をダウンロードし、CP932（Shift-JIS）を自動検出して
> UTF-8 に変換してから格納します。テーブル名は `T11051_TRAM_RIDERSHIP_REVENUE_MONTHLY`
> のように「コード + 英語説明」形式です。

---

### STEP 3: Semantic View 作成（`STEP3_semantic_view.sql`）

**実行ロール:** ACCOUNTADMIN | **所要時間:** 約 10 秒

`CREATE OR REPLACE SEMANTIC VIEW` DDL で `KUMAMOTO_CITY_STATISTICS` を作成します。

**定義内容:**

| 要素 | 数 | 役割 |
|---|---|---|
| TABLES（対象テーブル） | 14 | 人口・交通・防災・文化・経済・環境 |
| DIMENSIONS（次元） | 46 | 年次・月次・性別・種別など |
| FACTS（ファクト） | 24 | 推計人口・乗車人数・火災件数など |
| METRICS（メトリクス） | 6 | フィルタ込み集計（ZOO_VISITORS_TOTAL など） |
| VQR（検証済みクエリ） | 16 | 単一テーブル + クロステーブル SQL サンプル |
| AI_SQL_GENERATION | 1 | データ特性・フィルタ値の説明 |

> **ポイント 1:** `FACTS` と `DIMENSIONS` はセクション順序が重要です（FACTS → DIMENSIONS）。
> **ポイント 2:** `METRICS` は集計関数込みの定義（例: `SUM("件数"::INT)`）で、
> フィルタが不要なテーブルのみ定義できます。
> **ポイント 3:** `VQR` によく使う質問と正解 SQL を登録すると回答精度が上がります。

---

### STEP 4: Cortex Agent 作成（`STEP4_cortex_agent.sql`）

**実行ロール:** ACCOUNTADMIN | **所要時間:** 約 10 秒

`CREATE OR REPLACE AGENT` で `KUMAMOTO_CITY_STATS_AGENT` を作成します。

**設定内容:**

| 項目 | 内容 |
|---|---|
| 表示名 | 熊本市統計アナリスト |
| ツール | `cortex_analyst_text_to_sql`（Semantic View と紐付け） |
| サンプル質問（Cortex Analyst） | 6 件（Metrics・Dimension・Relationship を活用） |
| サンプル質問（Cortex Search） | 4 件（STEP6 完了後に活用） |

> **ポイント:** Snowflake Intelligence の一覧に表示されるのは Cortex Agent のみです。
> Semantic View だけでは一覧に表示されません。

---

### STEP 5: 動作確認（`STEP5_demo_queries.sql`）

SQL で取り込んだデータを直接確認するクエリ集です。

**Snowflake Intelligence での確認手順:**
1. Snowsight 左メニュー下部「**Intelligence**」をクリック
2. 「**熊本市統計アナリスト**」が表示されることを確認
3. 以下のサンプル質問を入力して動作を確認

| 種別 | サンプル質問 |
|---|---|
| Cortex Analyst | 月次の推計総人口はどのように推移していますか |
| Cortex Analyst | 熊本市電の年度別乗車人数合計と乗車料収入の推移を教えて |
| Cortex Analyst | 博物館と動植物園の月次入館者数を比較して |
| Cortex Analyst | 火災件数と損害額の年次推移を見せて |
| Cortex Analyst | 有効求人倍率の最近の推移を教えて |
| Cortex Analyst | 市電の定期利用者と定期外利用者の割合はどう変化しているか |

---

### STEP 6: PDF + Cortex Search 追加 ─ 発展編（`STEP6_cortex_search.sql`）

**実行ロール:** ACCOUNTADMIN | **所要時間:** 約 2〜3 分

PDF ドキュメントを取り込み、Cortex Search で全文意味検索できるようにします。
完了後、Agent に Cortex Search ツールが追加されます。

#### 対象 PDF

| ファイル名 | 内容 |
|---|---|
| `Kumamoto_kyoudousankaku.pdf` | 熊本市 男女共同参画企業意識・実態調査（令和5年度）約 3MB |

> ⚠️ **PDF のファイルサイズに注意**
> `AI_PARSE_DOCUMENT` はサイズに比例して処理時間がかかります。
> ハンズオンには **5MB 以下** のファイルを推奨します。

#### 2 段階のパイプライン

```
STAGE 1: AI_PARSE_DOCUMENT
  PDF → テキスト全文抽出
  → KUMAMOTO_DOCS_PARSED（1ファイル = 1レコード）

STAGE 2: SPLIT_TEXT_RECURSIVE_CHARACTER
  全文 → チャンク分割（500文字 / オーバーラップ50文字）
  → KUMAMOTO_DOCS_CHUNKS（約150チャンク）
  → CREATE CORTEX SEARCH SERVICE KUMAMOTO_DOCS_SEARCH
  → Agent に cortex_search ツールとして追加
```

#### 注意事項

| 項目 | 内容 |
|---|---|
| ステージの暗号化 | `ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')` が必須（デフォルトのクライアントサイド暗号化では AI_PARSE_DOCUMENT が動作しない） |
| ファイル指定 | `TO_FILE('@stage', 'filename')` を使用（`BUILD_SCOPED_FILE_URL` は使用不可） |

#### STEP 6 完了後の Agent 構成

| ツール | 役割 | サンプル質問 |
|---|---|---|
| `cortex_analyst` | 統計データを SQL で分析 | 有効求人倍率の推移など |
| `cortex_search` | PDF ドキュメントを意味検索 | 女性管理職の状況、育児休業の取得状況など |

---

### STEP 7: Streamlit ダッシュボード作成 ─ 発展編（`STEP7_streamlit_dashboard.sql`）

**実行ロール:** ACCOUNTADMIN | **所要時間:** 約 5 分

92 テーブルのデータを 6 カテゴリ・タブ形式で可視化する
Streamlit in Snowflake ダッシュボードを作成します。

#### ダッシュボードの構成

| タブ | 可視化内容 | チャート数 |
|---|---|---|
| 👥 人口動態 | 月次推計人口・男女別・出生死亡・転入転出 | 4 |
| 🚃 交通 | 市電乗車人数・定期外別・空港乗降客数・収入 | 4 |
| 🔥 防災・安全 | 火災件数・種別内訳・交通事故・損害額 | 5 |
| 🎭 文化施設 | 博物館・動植物園・現代美術館入館者数比較 | 3 |
| 💰 経済・労働 | 有効求人倍率・就職率・家計支出費目別 | 4 |
| ♻️ 環境 | ごみ収集量・種別内訳・上水道用途別 | 4 |

- **サイドバー:** 年度スライダー（2011〜2021）で全タブのチャートを一括フィルタリング

#### 作成方法

**方法 A（推奨）:** Snowsight 左メニュー「Streamlit」→「+ Streamlit App」
→ `streamlit/kumamoto_dashboard.py` のコードを貼り付けて実行

**方法 B:** `STEP7_streamlit_dashboard.sql` の SQL 手順に従ってステージ経由で作成

---

## トラブルシューティング

| 症状 | 対処 |
|---|---|
| STEP2 でエラー | STEP1 が実行済みか確認。ACCOUNTADMIN ロールを使用 |
| STEP2 の取込が一部 ERROR | 一時的なネットワーク問題の可能性。再度 CALL すると OK が増える |
| STEP3 の構文エラー | セクション順序を確認（FACTS → DIMENSIONS の順が必須） |
| Intelligence に Agent が表示されない | STEP4 を実行済みか確認。ブラウザをリロード |
| STEP6 で `Client Side Encryption` エラー | ステージを `ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')` で再作成 |
| STEP6 で `AI_PARSE_DOCUMENT` がタイムアウト | PDF が大きすぎる（5MB 以下を推奨） |
| STEP7 でアプリが表示されない | STEP7 の SQL を実行済みか確認。Snowsight の「Streamlit」メニューを確認 |
| 自然言語の回答が間違っている | STEP5 の SQL で正しいフィルタ値を確認 |

---

## 参考情報

- データソース: [熊本市オープンデータカタログ](https://odcs.bodik.jp/431001/)
- CKAN API: `https://data.bodik.jp/api/3/action/`
- [Snowflake Intelligence ドキュメント](https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork)
- [Streamlit in Snowflake ドキュメント](https://docs.snowflake.com/en/developer-guide/streamlit/about-streamlit)
- [CREATE SEMANTIC VIEW](https://docs.snowflake.com/en/sql-reference/sql/create-semantic-view)
- [AI_PARSE_DOCUMENT](https://docs.snowflake.com/en/user-guide/snowflake-cortex/parse-document)
