# =============================================================================
# ingest_kumamoto.py
#
# 概要:
#   熊本市オープンデータカタログ (BODIK ODCS) の CKAN API から
#   CSV 形式のデータセットを取得し、Snowflake テーブルとして格納する
#   Snowpark Python ストアドプロシージャ。
#
# アーキテクチャ上のポイント:
#   - External Network Access を使い、Snowflake 内部から直接 CKAN API を呼び出す
#   - データはすべて VARCHAR 型で格納し、スキーマレスに取り込む
#   - テーブル名は CSV ファイルのコード部分 (T11051 等) に英語説明を付与した
#     形式 (例: T11051_TRAM_RIDERSHIP_REVENUE_MONTHLY) とする
#   - 日本語カラム名は Snowflake の quoted identifier としてそのまま保持する
#   - CP932 (Shift-JIS) エンコーディングを自動検出して UTF-8 に変換する
#
# デプロイ:
#   sql/02_ingest_sproc.sql を実行することでストアドプロシージャとして
#   Snowflake にデプロイされる。このファイルは参照・編集用のソースコード。
#
# 呼び出し例:
#   CALL KUMAMOTO_OPENDATA.PUBLIC.INGEST_KUMAMOTO_OPENDATA();
# =============================================================================

import requests
import csv
import io
import json
import re
from snowflake.snowpark import Session
from snowflake.snowpark.types import StructType, StructField, StringType


# =============================================================================
# テーブル名マッピング辞書
#
# CKAN リソースの CSV ファイルコード (T11051 等) を、人間が読みやすい
# 英語テーブル名に対応付ける。
# キー   : CSV ファイル名の先頭コード部分 (大文字)
# バリュー: Snowflake テーブル名 ({コード}_{英語説明} 形式)
# =============================================================================
TABLE_NAME_MAP = {
    # ── 土地・都市計画 (T01) ─────────────────────────────────────────────────
    "T01040": "T01040_LAND_USE_AREA",           # 地目別面積
    "T01050": "T01050_URBANIZATION_AREA",       # 市街化区域面積

    # ── 人口統計 (T02) ───────────────────────────────────────────────────────
    "T02011": "T02011_CITY_POPULATION_HIST",           # 推計人口（歴史値）
    "T02012": "T02012_CITY_HOUSEHOLDS_HIST",           # 世帯数（歴史値）
    "T02020": "T02020_FOREIGN_RESIDENTS",              # 国籍別外国人住民
    "T02031": "T02031_POPULATION_MONTHLY",             # 月次推計人口
    "T02032": "T02032_POPULATION_HOUSEHOLDS_MONTHLY",  # 月次推計人口・世帯数
    "T02040": "T02040_BIRTHS_DEATHS_MONTHLY",          # 月次自然動態
    "T02050": "T02050_MIGRATION_MARRIAGE_MONTHLY",     # 月次社会動態・婚姻離婚
    "T02060": "T02060_MIGRATION_IN_OUT_MONTHLY",       # 月次転入転出
    "T02081": "T02081_CENSUS_POPULATION",              # 国勢調査人口
    "T02082": "T02082_CENSUS_URBAN_DISTRICT",          # 人口集中地区

    # ── 商業 (T06) ───────────────────────────────────────────────────────────
    "T06011": "T06011_LARGE_RETAIL_STORES_MONTHLY",   # 大型小売店舗月次概況
    "T06012": "T06012_LARGE_RETAIL_SALES_MONTHLY",    # 大型小売店舗月次販売額
    "T06020": "T06020_ALCOHOL_SALES",                 # 酒類販売量

    # ── 水道 (T08) ───────────────────────────────────────────────────────────
    "T08071": "T08071_WATER_SUPPLY_ANALYSIS",    # 配水量分析（有効・無効水量）
    "T08072": "T08072_WATER_SUPPLY_EFFICIENCY",  # 配水量分析（有収率等）
    "T08080": "T08080_WATER_SUPPLY_BY_PURPOSE",  # 用途別件数・有収水量

    # ── 家計・物価 (T09) ─────────────────────────────────────────────────────
    "T09011": "T09011_HOUSEHOLD_MONTHLY_EXPENDITURE",    # 家計月次支出
    "T09021": "T09021_WORKER_HOUSEHOLD_INCOME",          # 勤労世帯月次収入
    "T09022": "T09022_WORKER_HOUSEHOLD_EXPENSE",         # 勤労世帯月次支出
    "T09023": "T09023_WORKER_HOUSEHOLD_TOTAL_EXPENSE",   # 勤労世帯月次支出合計
    "T09024": "T09024_WORKER_HOUSEHOLD_INFO_MONTHLY",    # 勤労世帯情報月次
    "T09040": "T09040_RETAIL_PRICES_KEY_ITEMS",          # 主要品目小売価格
    "T09050": "T09050_CONSUMER_PRICE_INDEX_REGIONAL",    # 消費者物価地域差指数

    # ── 交通 (T11) ───────────────────────────────────────────────────────────
    "T11010": "T11010_JR_STATION_ANNUAL_RIDERSHIP",      # JR駅別年間乗車人員
    "T11031": "T11031_AIRPORT_PASSENGERS_MONTHLY",       # 空港月次乗降客数
    "T11032": "T11032_AIRPORT_CARGO_MAIL_MONTHLY",       # 空港月次貨物・郵便
    "T11051": "T11051_TRAM_RIDERSHIP_REVENUE_MONTHLY",   # 市電月次乗車・収入
    "T11052": "T11052_TRAM_OPERATION_STATS_MONTHLY",     # 市電月次輸送概況
    "T11060": "T11060_CITY_PARKING_MONTHLY",             # 市営駐車場月次利用
    "T11070": "T11070_VEHICLE_REGISTRATIONS_BY_TYPE",    # 車種別自動車登録台数
    "T11081": "T11081_TAXI_REGISTERED_VEHICLES",         # タクシー届出台数
    "T11082": "T11082_TAXI_OPERATORS",                   # タクシー経営者数
    "T11090": "T11090_LIGHT_VEHICLE_REGISTRATIONS",      # 軽自動車登録台数

    # ── 労働・社会福祉 (T12) ─────────────────────────────────────────────────
    "T12041": "T12041_EMPLOYMENT_INSURANCE_MONTHLY",     # 雇用保険月次適用状況
    "T12042": "T12042_EMPLOYMENT_INSURANCE_BENEFITS",    # 雇用保険月次給付状況
    "T12051": "T12051_JOB_SEEKERS_MONTHLY",              # 求人・求職月次概況
    "T12052": "T12052_SENIOR_JOB_SEEKERS_MONTHLY",       # 月次中高年求職者
    "T12055": "T12055_JOB_VACANCY_RATE_MONTHLY",         # 有効求人倍率月次
    "T12060": "T12060_JOB_OPENINGS_BY_INDUSTRY",         # 産業別求人状況
    "T12081": "T12081_SOCIAL_WELFARE_FACILITIES",        # 社会福祉事業施設数
    "T12082": "T12082_WELFARE_COMMISSIONERS",            # 民生委員数
    "T12171": "T12171_ELDERLY_WELFARE_OVERVIEW",         # 高齢者福祉概況
    "T12172": "T12172_ELDERLY_WELFARE_CENTER_USERS",     # 老人福祉センター利用者
    "T12191": "T12191_NURSERY_SCHOOLS_OVERVIEW",         # 保育所概況
    "T12192": "T12192_NURSERY_SCHOOL_ENROLLMENT_BY_AGE", # 年齢別保育所入所者数

    # ── 保健・医療 (T13) ─────────────────────────────────────────────────────
    "T13011": "T13011_HOSPITALS_BY_DISTRICT_TYPE",       # 行政区別病院施設数
    "T13012": "T13012_HOSPITAL_BEDS_BY_TYPE",            # 行政区別病院病床数
    "T13013": "T13013_CLINICS_BY_DISTRICT",              # 行政区別一般診療所
    "T13014": "T13014_CLINIC_BEDS_BY_DISTRICT",          # 行政区別診療所病床数
    "T13015": "T13015_DENTAL_CLINICS_BY_DISTRICT",       # 行政区別歯科診療所
    "T13031": "T13031_CITY_HOSPITAL_STAFF",              # 市立病院職種別従事者
    "T13032": "T13032_CITY_HOSPITAL_BEDS",               # 市立病院病床数
    "T13033": "T13033_CITY_HOSPITAL_PATIENTS",           # 市立病院患者数
    "T13080": "T13080_HEALTH_PROMOTION_STATS",           # 健康増進事業概況
    "T13100": "T13100_DEATHS_BY_SEX_CAUSE",              # 性別死因別死亡数
    "T13180": "T13180_WASTE_PROCESSING_MONTHLY",         # 月次ごみ処理概況
    "T13191": "T13191_SEWAGE_POPULATION_BY_FACILITY",    # 処理施設別人口
    "T13192": "T13192_SEWAGE_TREATMENT_VOLUME",          # 処理場別し尿処理量

    # ── 道路・インフラ (T14) ─────────────────────────────────────────────────
    "T14011": "T14011_ROAD_OVERVIEW_1",                  # 道路概況1
    "T14012": "T14012_ROAD_OVERVIEW_2",                  # 道路概況2
    "T14020": "T14020_NATIONAL_PREFECTURAL_BRIDGES",     # 国県道橋りょう状況
    "T14031": "T14031_URBAN_ROAD_OVERVIEW_1",            # 都市計画道路概況1
    "T14032": "T14032_URBAN_ROAD_ROUTE_COUNT",           # 都市計画道路路線数
    "T14041": "T14041_CITY_ROAD_BRIDGES_OVERVIEW",       # 市道橋りょう概況
    "T14042": "T14042_CITY_ROAD_BRIDGES_BY_AGE",         # 市道橋齢別橋数
    "T14043": "T14043_CITY_ROAD_BRIDGES_BY_CONDITION",   # 市道現況別橋数

    # ── 安全・防災 (T15) ─────────────────────────────────────────────────────
    "T15120": "T15120_TRAFFIC_ACCIDENTS_BY_STATION",     # 警察署管轄別交通事故
    "T15191": "T15191_FIRE_INCIDENTS_DAMAGE",            # 火災件数・損害額
    "T15192": "T15192_FIRE_BURNT_BUILDINGS",             # 火災焼損むね数
    "T15193": "T15193_FIRE_CASUALTIES",                  # 火災罹災・死傷者
    "T15200": "T15200_FIRE_BY_BUILDING_CAUSE",           # 建物用途別火災件数

    # ── 教育・文化 (T18) ─────────────────────────────────────────────────────
    "T18041": "T18041_JUNIOR_HIGH_SCHOOLS_CLASSES",      # 中学校数・学級数
    "T18042": "T18042_JUNIOR_HIGH_STAFF_STUDENTS",       # 中学校職員・生徒数
    "T18051": "T18051_ELEMENTARY_SCHOOLS_CLASSES",       # 小学校数・学級数
    "T18052": "T18052_ELEMENTARY_STAFF_STUDENTS",        # 小学校職員・生徒数
    "T18140": "T18140_CITY_LIBRARY_COLLECTION",          # 市立図書館蔵書冊数
    "T18150": "T18150_PREF_LIBRARY_COLLECTION",          # 県立図書館蔵書・閲覧
    "T18160": "T18160_MUSEUM_COLLECTION",                # 博物館所蔵資料数
    "T18171": "T18171_MUSEUM_OPEN_DAYS_MONTHLY",         # 博物館開館日数月次
    "T18172": "T18172_MUSEUM_VISITORS_MONTHLY",          # 博物館入館者数月次
    "T18173": "T18173_PLANETARIUM_VISITORS_MONTHLY",     # プラネタリウム観覧者
    "T18174": "T18174_MUSEUM_ADMISSION_MONTHLY",         # 博物館観覧料月次
    "T18180": "T18180_CONTEMPORARY_ART_COLLECTION",      # 現代美術館所蔵資料
    "T18191": "T18191_CONTEMPORARY_ART_MUSEUM_MONTHLY",  # 現代美術館月次概況
    "T18192": "T18192_CONTEMPORARY_ART_EXHIBITION",      # 現代美術館企画展
    "T18201": "T18201_ZOO_MONTHLY_OVERVIEW",             # 動植物園月次概況
    "T18202": "T18202_ZOO_VISITORS_BY_TYPE",             # 動植物園種別入園者
    "T18230": "T18230_CIVIC_HALL_MONTHLY_USAGE",         # 市民会館月次利用

    # ── コード体系なし（特殊ファイル）────────────────────────────────────────
    "くまもとフリーWi-Fi":           "FREE_WIFI_SPOTS",    # フリーWi-Fiスポット
    "熊本市駐輪場一覧（令和６年３月）": "BICYCLE_PARKING",   # 駐輪場一覧
}


def ingest_kumamoto_opendata(session: Session) -> str:
    """
    CKAN API からデータを取得して Snowflake テーブルに格納するメイン関数。

    処理フロー:
      1. CKAN API (package_search) で熊本市の全データセットを取得
      2. CSV フォーマットのリソースのみ対象に絞り込む
      3. 各 CSV ファイルをダウンロードし CP932 → UTF-8 変換
      4. pandas DataFrame を経由して Snowflake テーブルを作成・データ投入
      5. DATASET_CATALOG テーブルにメタ情報を記録
    """
    # CKAN API のベース URL と対象組織 ID (熊本市)
    CKAN_API   = "https://data.bodik.jp/api/3/action"
    ORG_ID     = "431001"
    TARGET_DB  = "KUMAMOTO_OPENDATA"
    TARGET_SCH = "PUBLIC"

    # ── Step 1: CKAN API でデータセット一覧を取得 ─────────────────────────
    resp = requests.get(
        f"{CKAN_API}/package_search",
        params={"fq": f"organization:{ORG_ID}", "rows": 100},
        timeout=30
    )
    resp.raise_for_status()
    packages = resp.json()["result"]["results"]

    results = []

    # ── Step 2-4: 各 CSV リソースを処理 ──────────────────────────────────
    for pkg in packages:
        for res in pkg.get("resources", []):
            # CSV 形式のリソースのみ処理（XLSX・ZIP は対象外）
            if res.get("format", "").upper() != "CSV":
                continue
            url = res.get("url", "").strip()
            if not url:  # URL が未設定のリソースはスキップ
                continue

            res_name   = res.get("name", "")
            table_name = _extract_table_name(res_name, pkg["name"])

            try:
                # Step 2: CSV ダウンロード
                r = requests.get(url, timeout=60, allow_redirects=True)
                r.raise_for_status()

                # Step 3: エンコーディング自動判定
                # 熊本市の CSV は主に CP932 (Shift-JIS)。UTF-8 BOM 付きも考慮。
                content = None
                for enc in ("cp932", "utf-8-sig", "utf-8"):
                    try:
                        content = r.content.decode(enc)
                        break
                    except (UnicodeDecodeError, LookupError):
                        continue
                if content is None:
                    raise ValueError("エンコーディング判定失敗")

                # CSV パース
                reader   = csv.reader(io.StringIO(content))
                all_rows = list(reader)

                if len(all_rows) < 2:  # ヘッダーのみでデータなし
                    results.append({
                        "table": table_name, "status": "SKIP",
                        "rows": 0, "message": "データ行なし"
                    })
                    continue

                # ヘッダー行と空行を除いたデータ行を取得
                headers   = [h.strip() for h in all_rows[0]]
                data_rows = [row for row in all_rows[1:] if any(v.strip() for v in row)]

                # 列数不一致の行を補正（短い行は空文字で埋める）
                n = len(headers)
                normalized = []
                for row in data_rows:
                    normalized.append(
                        row[:n] if len(row) >= n else row + [""] * (n - len(row))
                    )

                # Step 4: Snowflake テーブルを作成してデータを投入
                _create_and_load(session, TARGET_DB, TARGET_SCH, table_name,
                                 headers, normalized)

                results.append({
                    "table": table_name, "status": "OK",
                    "rows": len(normalized), "message": res_name
                })

            except Exception as e:
                results.append({
                    "table": table_name, "status": "ERROR",
                    "rows": 0, "message": str(e)[:500]
                })

    # ── Step 5: データセットカタログテーブルを更新 ────────────────────────
    try:
        _upsert_catalog(session, TARGET_DB, TARGET_SCH, packages, results)
    except Exception as e:
        results.append({
            "table": "DATASET_CATALOG", "status": "ERROR",
            "rows": 0, "message": str(e)[:500]
        })

    ok_count   = sum(1 for r in results if r["status"] == "OK")
    err_count  = sum(1 for r in results if r["status"] == "ERROR")
    skip_count = sum(1 for r in results if r["status"] == "SKIP")

    return json.dumps(
        {"ok": ok_count, "error": err_count, "skip": skip_count,
         "total": len(results), "detail": results},
        ensure_ascii=False, indent=2
    )


def _create_and_load(session, db: str, schema: str, table_name: str,
                     headers: list, normalized: list):
    """
    テーブルを作成してデータをロードする。

    技術的ポイント:
      - CREATE OR REPLACE TABLE で冪等性を確保（何度実行しても同じ結果）
      - 全カラムを VARCHAR 型で定義し、スキーマレスに取り込む
      - 日本語カラム名は double-quote でそのまま保持
        (例: "年度" VARCHAR, "月次" VARCHAR)
      - session.create_dataframe() + save_as_table() でデータを投入
        大量データは 500 行単位でチャンク処理してメモリを節約
    """
    full_table = f"{db}.{schema}.{table_name}"
    cols_ddl   = ", ".join([f'"{h}" VARCHAR' for h in headers])

    # テーブル作成（存在すれば上書き）
    session.sql(f"CREATE OR REPLACE TABLE {full_table} ({cols_ddl})").collect()

    if not normalized:
        return

    # データ投入: 500 行ずつ Snowpark DataFrame → save_as_table
    schema_def = StructType([StructField(h, StringType()) for h in headers])
    for i in range(0, len(normalized), 500):
        chunk   = normalized[i:i + 500]
        snow_df = session.create_dataframe(chunk, schema=schema_def)
        snow_df.write.mode("append").save_as_table([db, schema, table_name])


def _extract_table_name(res_name: str, pkg_name: str) -> str:
    """
    CSV ファイル名から Snowflake テーブル名を生成する。

    命名規則:
      1. ファイル名の先頭コード部分 (T11051 等) を TABLE_NAME_MAP でルックアップ
      2. マッチした場合: マップの値を使用 (例: T11051_TRAM_RIDERSHIP_REVENUE_MONTHLY)
      3. コードなし: パッケージ名を ASCII 化してフォールバック
      4. 数字始まりの場合: T_ プレフィックスを付与 (Snowpark の制約回避)
    """
    base = re.sub(r'\.csv$', '', res_name, flags=re.IGNORECASE).strip()

    # T コードを抽出してマッピング検索
    m = re.match(r'^([A-Z0-9]+)_', base, re.IGNORECASE)
    if m:
        code = m.group(1).upper()
        return TABLE_NAME_MAP.get(code, code)

    # コードなし: ファイル名そのものでマッピング検索（特殊ファイル対応）
    if base in TABLE_NAME_MAP:
        return TABLE_NAME_MAP[base]

    # フォールバック: パッケージ名を ASCII 化
    name = re.sub(r'[^A-Z0-9_]', '_', pkg_name.upper())[:30].rstrip('_')
    return f'T_{name}' if name and name[0].isdigit() else name


def _upsert_catalog(session, db: str, schema: str,
                    packages: list, results: list):
    """
    DATASET_CATALOG テーブルを作成・更新する。

    カタログには以下の情報を格納:
      - パッケージ名・タイトル
      - リソース ID・名前・URL
      - 対応するテーブル名
      - 取込ステータス・行数・メッセージ
    """
    result_map   = {r["table"]: r for r in results}
    catalog_rows = []

    for pkg in packages:
        for res in pkg.get("resources", []):
            if res.get("format", "").upper() != "CSV":
                continue
            res_name   = res.get("name", "")
            table_name = _extract_table_name(res_name, pkg["name"])
            rr         = result_map.get(table_name, {})
            catalog_rows.append([
                pkg.get("name", ""),
                pkg.get("title", ""),
                res.get("id", ""),
                res_name,
                res.get("url", ""),
                table_name,
                rr.get("status", "NOT_RUN"),
                str(rr.get("rows", 0)),
                rr.get("message", "")[:500]
            ])

    if not catalog_rows:
        return

    cat_headers = [
        "PACKAGE_NAME", "PACKAGE_TITLE", "RESOURCE_ID", "RESOURCE_NAME",
        "RESOURCE_URL", "TABLE_NAME", "INGEST_STATUS", "ROW_COUNT", "INGEST_MESSAGE"
    ]
    cat_schema = StructType([StructField(h, StringType()) for h in cat_headers])
    cat_df     = session.create_dataframe(catalog_rows, schema=cat_schema)
    cat_df.write.mode("overwrite").save_as_table([db, schema, "DATASET_CATALOG"])
