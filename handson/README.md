# 熊本市オープンデータ × Snowflake Intelligence ハンズオン

## ハンズオンの概要

熊本市が公開しているオープンデータ統計（人口・交通・防災・文化・経済など）を
Snowflake に取り込み、**Snowflake Intelligence** から自然言語で問い合わせできる
環境を約 20〜30 分で構築します。

**最終的にできること:**
- 「熊本市の月次推計人口の推移を教えて」
- 「市電の乗車人数と空港の乗降客数を月次で比較して」
- 「火災件数と交通事故件数を年次で比較して」

---

## ファイル構成

```
handson/
├── README.md                ← このファイル
├── STEP1_setup.sql          インフラ設定（DB・Network Rule・EAI）
├── STEP2_ingest_data.sql    データ取込 SP 作成・実行
├── STEP3_semantic_view.sql  Semantic View 作成（YAML 埋め込み済み）
├── STEP4_cortex_agent.sql   Cortex Agent 作成
└── STEP5_demo_queries.sql   動作確認クエリ
```

---

## 実行手順

### 事前準備

Snowsight にログインし、左メニューの **「Worksheets」** を開きます。  
各 STEP のファイルを新しいワークシートに貼り付けて実行してください。

---

### STEP 1: インフラ設定 (`STEP1_setup.sql`)

**実行ロール:** ACCOUNTADMIN  
**所要時間:** 約 1 分

| 作成するオブジェクト | 説明 |
|---|---|
| `KUMAMOTO_OPENDATA` データベース | データ格納先 |
| `BODIK_NETWORK_RULE` Network Rule | data.bodik.jp への通信を許可 |
| `BODIK_EXTERNAL_ACCESS` EAI | SP からの外部 HTTP 通信を許可 |

> **ポイント:** Snowflake のストアドプロシージャは通常、外部ネットワークにアクセスできません。  
> External Network Access を設定することで、CKAN API への直接アクセスが可能になります。

---

### STEP 2: データ取込 (`STEP2_ingest_data.sql`)

**実行ロール:** ACCOUNTADMIN  
**所要時間:** ストアドプロシージャ作成: 数秒 / データ取込実行: **約 5 分**

1. ストアドプロシージャ `INGEST_KUMAMOTO_OPENDATA` を作成
2. `CALL KUMAMOTO_OPENDATA.PUBLIC.INGEST_KUMAMOTO_OPENDATA()` を実行
3. 92 テーブルが作成されることを確認

**期待される結果:**
```
INGEST_STATUS | データセット数 | 総レコード数
OK            | 92            | 〜200,000+
```

> **ポイント:** Snowpark Python ストアドプロシージャが CKAN API に直接アクセスし、  
> CP932 (Shift-JIS) 形式の CSV を自動検出・変換してテーブルに格納します。

---

### STEP 3: Semantic View 作成 (`STEP3_semantic_view.sql`)

**実行ロール:** ACCOUNTADMIN  
**所要時間:** 約 10 秒

`SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML` を呼び出し、  
YAML 定義から Semantic View `KUMAMOTO_CITY_STATISTICS` を作成します。

**定義内容:**

| 要素 | 数 | 例 |
|---|---|---|
| 対象テーブル | 14 | T02031_POPULATION_MONTHLY など |
| ディメンション | 46 | 年次、月次、性別、種別 など |
| メジャー/ファクト | 24 | 推計人口、乗車人数、火災件数 など |
| メトリクス | 6 | ZOO_VISITORS_TOTAL など |
| VQR（検証済みクエリ） | 16 | 単一テーブル＋クロステーブル |

> **ポイント:** Semantic View は Cortex Analyst が「このカラムは何か」「どのテーブルを  
> 結合すればよいか」を理解するためのメタデータです。VQR（Verified Query Results）は  
> よく使う質問とその正しい SQL のペアで、回答精度を高めます。

---

### STEP 4: Cortex Agent 作成 (`STEP4_cortex_agent.sql`)

**実行ロール:** ACCOUNTADMIN  
**所要時間:** 約 10 秒

`CREATE AGENT` で Cortex Agent `KUMAMOTO_CITY_STATS_AGENT` を作成します。

**設定内容:**
- 表示名: **熊本市統計アナリスト**
- ツール: `cortex_analyst_text_to_sql`（Semantic View と紐付け）
- サンプル質問: 10 件登録

> **ポイント:** Cortex Agent を作成することで Snowflake Intelligence の一覧に  
> 「熊本市統計アナリスト」が表示されるようになります。  
> Semantic View だけではこの一覧に表示されません。

---

### STEP 5: 動作確認 (`STEP5_demo_queries.sql`)

SQL でデータ・クエリを直接確認できます。  
また、**Snowflake Intelligence** での動作確認手順も記載しています。

**Snowflake Intelligence での確認:**
1. Snowsight 左メニュー下部「**Intelligence**」をクリック
2. 「**熊本市統計アナリスト**」が表示されることを確認
3. サンプル質問をクリックするか、自由に質問を入力

---

## アーキテクチャ図

```
┌──────────────────────────────────────────────────────────────┐
│  data.bodik.jp (CKAN API)                                    │
│  熊本市オープンデータ: 84 データセット / 92 CSV ファイル      │
└────────────────────┬─────────────────────────────────────────┘
                     │ HTTPS (External Network Access)
                     ▼
┌──────────────────────────────────────────────────────────────┐
│  Snowflake KUMAMOTO_OPENDATA.PUBLIC                         │
│                                                              │
│  STEP2: INGEST_KUMAMOTO_OPENDATA() ── Snowpark Python SP   │
│    └→ 92 テーブル（T02031_POPULATION_MONTHLY など）          │
│         + DATASET_CATALOG（取込メタ情報）                    │
│                                                              │
│  STEP3: KUMAMOTO_CITY_STATISTICS ── Semantic View           │
│    └→ 14 テーブルの意味・関係・VQR を定義                    │
│                                                              │
│  STEP4: KUMAMOTO_CITY_STATS_AGENT ── Cortex Agent          │
│    └→ Semantic View を Tool として使用                        │
└──────────────────────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────────────────┐
│  Snowflake Intelligence                                      │
│  「熊本市統計アナリスト」                                    │
│  → 自然言語で熊本市統計データを横断分析                      │
└──────────────────────────────────────────────────────────────┘
```

---

## トラブルシューティング

| 症状 | 対処 |
|---|---|
| STEP2 でエラーが出る | STEP1 が実行済みか確認。ACCOUNTADMIN ロールを使用 |
| STEP2 の取込が一部 ERROR | 一時的なネットワーク問題の可能性。再度 CALL すると OK が増えることがある |
| STEP3 で YAML パースエラー | ファイルを変更していないか確認 |
| Intelligence に Agent が表示されない | STEP4 を実行済みか確認。画面をリロード |
| 自然言語の回答が間違っている | STEP5 の SQL クエリで正しいフィルタ値を確認 |

---

## 参考情報

- データソース: [熊本市オープンデータカタログ](https://odcs.bodik.jp/431001/)
- CKAN API: `https://data.bodik.jp/api/3/action/`
- Snowflake Intelligence ドキュメント: https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork
