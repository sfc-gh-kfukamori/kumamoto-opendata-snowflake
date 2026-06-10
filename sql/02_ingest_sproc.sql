-- =============================================================================
-- 02_ingest_sproc.sql
--
-- 概要: データ取込ストアドプロシージャのデプロイ
--   熊本市オープンデータカタログ (BODIK ODCS) から CSV データを取得し
--   Snowflake テーブルとして格納するストアドプロシージャを作成する。
--
-- 実行前提: 01_setup.sql が実行済みであること
-- 実行ロール: ACCOUNTADMIN または SYSADMIN
-- =============================================================================

-- Python コードの本体は sproc/ingest_kumamoto.py を参照。
-- このファイルは Snowflake にデプロイするための CREATE PROCEDURE DDL。

CREATE OR REPLACE PROCEDURE KUMAMOTO_OPENDATA.PUBLIC.INGEST_KUMAMOTO_OPENDATA()
    RETURNS VARCHAR
    LANGUAGE PYTHON
    RUNTIME_VERSION = '3.11'
    -- requests: CKAN API への HTTP 通信
    -- snowflake-snowpark-python: Snowpark DataFrame 操作
    PACKAGES = ('snowflake-snowpark-python', 'requests')
    HANDLER = 'ingest_kumamoto_opendata'
    -- External Access Integration を指定することで
    -- data.bodik.jp への外部通信が許可される
    EXTERNAL_ACCESS_INTEGRATIONS = (BODIK_EXTERNAL_ACCESS)
AS
$$
import requests
import csv
import io
import json
import re
from snowflake.snowpark import Session
from snowflake.snowpark.types import StructType, StructField, StringType

# =============================================================================
# テーブル名マッピング辞書
# CSV ファイルコード (T11051 等) → Snowflake テーブル名
# =============================================================================
TABLE_NAME_MAP = {
    # ── 土地・都市計画 (T01) ─────────────────────────────────────────────────
    "T01040": "T01040_LAND_USE_AREA",
    "T01050": "T01050_URBANIZATION_AREA",
    # ── 人口統計 (T02) ───────────────────────────────────────────────────────
    "T02011": "T02011_CITY_POPULATION_HIST",
    "T02012": "T02012_CITY_HOUSEHOLDS_HIST",
    "T02020": "T02020_FOREIGN_RESIDENTS",
    "T02031": "T02031_POPULATION_MONTHLY",
    "T02032": "T02032_POPULATION_HOUSEHOLDS_MONTHLY",
    "T02040": "T02040_BIRTHS_DEATHS_MONTHLY",
    "T02050": "T02050_MIGRATION_MARRIAGE_MONTHLY",
    "T02060": "T02060_MIGRATION_IN_OUT_MONTHLY",
    "T02081": "T02081_CENSUS_POPULATION",
    "T02082": "T02082_CENSUS_URBAN_DISTRICT",
    # ── 商業 (T06) ───────────────────────────────────────────────────────────
    "T06011": "T06011_LARGE_RETAIL_STORES_MONTHLY",
    "T06012": "T06012_LARGE_RETAIL_SALES_MONTHLY",
    "T06020": "T06020_ALCOHOL_SALES",
    # ── 水道 (T08) ───────────────────────────────────────────────────────────
    "T08071": "T08071_WATER_SUPPLY_ANALYSIS",
    "T08072": "T08072_WATER_SUPPLY_EFFICIENCY",
    "T08080": "T08080_WATER_SUPPLY_BY_PURPOSE",
    # ── 家計・物価 (T09) ─────────────────────────────────────────────────────
    "T09011": "T09011_HOUSEHOLD_MONTHLY_EXPENDITURE",
    "T09021": "T09021_WORKER_HOUSEHOLD_INCOME",
    "T09022": "T09022_WORKER_HOUSEHOLD_EXPENSE",
    "T09023": "T09023_WORKER_HOUSEHOLD_TOTAL_EXPENSE",
    "T09024": "T09024_WORKER_HOUSEHOLD_INFO_MONTHLY",
    "T09040": "T09040_RETAIL_PRICES_KEY_ITEMS",
    "T09050": "T09050_CONSUMER_PRICE_INDEX_REGIONAL",
    # ── 交通 (T11) ───────────────────────────────────────────────────────────
    "T11010": "T11010_JR_STATION_ANNUAL_RIDERSHIP",
    "T11031": "T11031_AIRPORT_PASSENGERS_MONTHLY",
    "T11032": "T11032_AIRPORT_CARGO_MAIL_MONTHLY",
    "T11051": "T11051_TRAM_RIDERSHIP_REVENUE_MONTHLY",
    "T11052": "T11052_TRAM_OPERATION_STATS_MONTHLY",
    "T11060": "T11060_CITY_PARKING_MONTHLY",
    "T11070": "T11070_VEHICLE_REGISTRATIONS_BY_TYPE",
    "T11081": "T11081_TAXI_REGISTERED_VEHICLES",
    "T11082": "T11082_TAXI_OPERATORS",
    "T11090": "T11090_LIGHT_VEHICLE_REGISTRATIONS",
    # ── 労働・社会福祉 (T12) ─────────────────────────────────────────────────
    "T12041": "T12041_EMPLOYMENT_INSURANCE_MONTHLY",
    "T12042": "T12042_EMPLOYMENT_INSURANCE_BENEFITS",
    "T12051": "T12051_JOB_SEEKERS_MONTHLY",
    "T12052": "T12052_SENIOR_JOB_SEEKERS_MONTHLY",
    "T12055": "T12055_JOB_VACANCY_RATE_MONTHLY",
    "T12060": "T12060_JOB_OPENINGS_BY_INDUSTRY",
    "T12081": "T12081_SOCIAL_WELFARE_FACILITIES",
    "T12082": "T12082_WELFARE_COMMISSIONERS",
    "T12171": "T12171_ELDERLY_WELFARE_OVERVIEW",
    "T12172": "T12172_ELDERLY_WELFARE_CENTER_USERS",
    "T12191": "T12191_NURSERY_SCHOOLS_OVERVIEW",
    "T12192": "T12192_NURSERY_SCHOOL_ENROLLMENT_BY_AGE",
    # ── 保健・医療 (T13) ─────────────────────────────────────────────────────
    "T13011": "T13011_HOSPITALS_BY_DISTRICT_TYPE",
    "T13012": "T13012_HOSPITAL_BEDS_BY_TYPE",
    "T13013": "T13013_CLINICS_BY_DISTRICT",
    "T13014": "T13014_CLINIC_BEDS_BY_DISTRICT",
    "T13015": "T13015_DENTAL_CLINICS_BY_DISTRICT",
    "T13031": "T13031_CITY_HOSPITAL_STAFF",
    "T13032": "T13032_CITY_HOSPITAL_BEDS",
    "T13033": "T13033_CITY_HOSPITAL_PATIENTS",
    "T13080": "T13080_HEALTH_PROMOTION_STATS",
    "T13100": "T13100_DEATHS_BY_SEX_CAUSE",
    "T13180": "T13180_WASTE_PROCESSING_MONTHLY",
    "T13191": "T13191_SEWAGE_POPULATION_BY_FACILITY",
    "T13192": "T13192_SEWAGE_TREATMENT_VOLUME",
    # ── 道路・インフラ (T14) ─────────────────────────────────────────────────
    "T14011": "T14011_ROAD_OVERVIEW_1",
    "T14012": "T14012_ROAD_OVERVIEW_2",
    "T14020": "T14020_NATIONAL_PREFECTURAL_BRIDGES",
    "T14031": "T14031_URBAN_ROAD_OVERVIEW_1",
    "T14032": "T14032_URBAN_ROAD_ROUTE_COUNT",
    "T14041": "T14041_CITY_ROAD_BRIDGES_OVERVIEW",
    "T14042": "T14042_CITY_ROAD_BRIDGES_BY_AGE",
    "T14043": "T14043_CITY_ROAD_BRIDGES_BY_CONDITION",
    # ── 安全・防災 (T15) ─────────────────────────────────────────────────────
    "T15120": "T15120_TRAFFIC_ACCIDENTS_BY_STATION",
    "T15191": "T15191_FIRE_INCIDENTS_DAMAGE",
    "T15192": "T15192_FIRE_BURNT_BUILDINGS",
    "T15193": "T15193_FIRE_CASUALTIES",
    "T15200": "T15200_FIRE_BY_BUILDING_CAUSE",
    # ── 教育・文化 (T18) ─────────────────────────────────────────────────────
    "T18041": "T18041_JUNIOR_HIGH_SCHOOLS_CLASSES",
    "T18042": "T18042_JUNIOR_HIGH_STAFF_STUDENTS",
    "T18051": "T18051_ELEMENTARY_SCHOOLS_CLASSES",
    "T18052": "T18052_ELEMENTARY_STAFF_STUDENTS",
    "T18140": "T18140_CITY_LIBRARY_COLLECTION",
    "T18150": "T18150_PREF_LIBRARY_COLLECTION",
    "T18160": "T18160_MUSEUM_COLLECTION",
    "T18171": "T18171_MUSEUM_OPEN_DAYS_MONTHLY",
    "T18172": "T18172_MUSEUM_VISITORS_MONTHLY",
    "T18173": "T18173_PLANETARIUM_VISITORS_MONTHLY",
    "T18174": "T18174_MUSEUM_ADMISSION_MONTHLY",
    "T18180": "T18180_CONTEMPORARY_ART_COLLECTION",
    "T18191": "T18191_CONTEMPORARY_ART_MUSEUM_MONTHLY",
    "T18192": "T18192_CONTEMPORARY_ART_EXHIBITION",
    "T18201": "T18201_ZOO_MONTHLY_OVERVIEW",
    "T18202": "T18202_ZOO_VISITORS_BY_TYPE",
    "T18230": "T18230_CIVIC_HALL_MONTHLY_USAGE",
    # ── コード体系なし（特殊ファイル）────────────────────────────────────────
    "くまもとフリーWi-Fi":           "FREE_WIFI_SPOTS",
    "熊本市駐輪場一覧（令和６年３月）": "BICYCLE_PARKING",
}


def ingest_kumamoto_opendata(session: Session) -> str:
    CKAN_API   = "https://data.bodik.jp/api/3/action"
    ORG_ID     = "431001"
    TARGET_DB  = "KUMAMOTO_OPENDATA"
    TARGET_SCH = "PUBLIC"

    # CKAN API でデータセット一覧を取得
    resp = requests.get(
        f"{CKAN_API}/package_search",
        params={"fq": f"organization:{ORG_ID}", "rows": 100},
        timeout=30
    )
    resp.raise_for_status()
    packages = resp.json()["result"]["results"]

    results = []

    for pkg in packages:
        for res in pkg.get("resources", []):
            if res.get("format", "").upper() != "CSV":
                continue
            url = res.get("url", "").strip()
            if not url:
                continue

            res_name   = res.get("name", "")
            table_name = _extract_table_name(res_name, pkg["name"])

            try:
                # CSV ダウンロード
                r = requests.get(url, timeout=60, allow_redirects=True)
                r.raise_for_status()

                # エンコーディング自動判定（CP932 → UTF-8-sig → UTF-8 の順で試行）
                content = None
                for enc in ("cp932", "utf-8-sig", "utf-8"):
                    try:
                        content = r.content.decode(enc)
                        break
                    except (UnicodeDecodeError, LookupError):
                        continue
                if content is None:
                    raise ValueError("エンコーディング判定失敗")

                reader   = csv.reader(io.StringIO(content))
                all_rows = list(reader)

                if len(all_rows) < 2:
                    results.append({
                        "table": table_name, "status": "SKIP",
                        "rows": 0, "message": "データ行なし"
                    })
                    continue

                headers   = [h.strip() for h in all_rows[0]]
                data_rows = [row for row in all_rows[1:] if any(v.strip() for v in row)]

                n = len(headers)
                normalized = []
                for row in data_rows:
                    normalized.append(
                        row[:n] if len(row) >= n else row + [""] * (n - len(row))
                    )

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


def _create_and_load(session, db, schema, table_name, headers, normalized):
    full_table = f"{db}.{schema}.{table_name}"
    cols_ddl   = ", ".join([f'"{h}" VARCHAR' for h in headers])
    session.sql(f"CREATE OR REPLACE TABLE {full_table} ({cols_ddl})").collect()
    if not normalized:
        return
    schema_def = StructType([StructField(h, StringType()) for h in headers])
    for i in range(0, len(normalized), 500):
        chunk   = normalized[i:i + 500]
        snow_df = session.create_dataframe(chunk, schema=schema_def)
        snow_df.write.mode("append").save_as_table([db, schema, table_name])


def _extract_table_name(res_name, pkg_name):
    base = re.sub(r'\.csv$', '', res_name, flags=re.IGNORECASE).strip()
    m = re.match(r'^([A-Z0-9]+)_', base, re.IGNORECASE)
    if m:
        code = m.group(1).upper()
        return TABLE_NAME_MAP.get(code, code)
    if base in TABLE_NAME_MAP:
        return TABLE_NAME_MAP[base]
    name = re.sub(r'[^A-Z0-9_]', '_', pkg_name.upper())[:30].rstrip('_')
    return f'T_{name}' if name and name[0].isdigit() else name


def _upsert_catalog(session, db, schema, packages, results):
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
                pkg.get("name", ""), pkg.get("title", ""),
                res.get("id", ""), res_name, res.get("url", ""),
                table_name, rr.get("status", "NOT_RUN"),
                str(rr.get("rows", 0)), rr.get("message", "")[:500]
            ])
    if not catalog_rows:
        return
    cat_headers = [
        "PACKAGE_NAME", "PACKAGE_TITLE", "RESOURCE_ID", "RESOURCE_NAME",
        "RESOURCE_URL", "TABLE_NAME", "INGEST_STATUS", "ROW_COUNT", "INGEST_MESSAGE"
    ]
    cat_schema = StructType([StructField(h, StringType()) for h in cat_headers])
    session.create_dataframe(catalog_rows, schema=cat_schema).write \
           .mode("overwrite").save_as_table([db, schema, "DATASET_CATALOG"])
$$;
