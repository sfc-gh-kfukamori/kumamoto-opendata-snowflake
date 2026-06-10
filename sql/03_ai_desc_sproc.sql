-- =============================================================================
-- 03_ai_desc_sproc.sql
--
-- 概要: AI 説明生成ストアドプロシージャのデプロイ
--   指定 DB の全テーブル・ビューとカラムに AI 生成の日本語 Description
--   (COMMENT) を設定するストアドプロシージャを作成する。
--
-- 実行前提: 01_setup.sql, 02_ingest_sproc.sql が実行済みであること
-- 実行ロール: ACCOUNTADMIN または SYSADMIN
--
-- 必要な権限:
--   - 対象テーブル・ビューへの SELECT 権限
--   - SNOWFLAKE.CORTEX_USER データベースロール
-- =============================================================================

CREATE OR REPLACE PROCEDURE KUMAMOTO_OPENDATA.PUBLIC.GENERATE_DB_DESCRIPTIONS(
    P_DATABASE_NAME      STRING,
    P_OVERWRITE_EXISTING BOOLEAN,
    P_USE_TABLE_DATA     BOOLEAN
)
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
-- joblib: テーブルの並列処理に使用
PACKAGES = ('snowflake-snowpark-python', 'joblib')
HANDLER = 'main'
COMMENT = '指定DBの全テーブル・ビューおよびカラムにAI生成の日本語Descriptionを設定する。P_DATABASE_NAME=対象DB, P_OVERWRITE_EXISTING=既存を上書き, P_USE_TABLE_DATA=実データをサンプリング'
AS
$$
import json
from joblib import Parallel, delayed
import multiprocessing


def translate_to_ja(session, text):
    """英語テキストを CORTEX.TRANSLATE で日本語に翻訳する。"""
    if not text or not text.strip():
        return text
    escaped = text.replace("'", "\\'")
    result  = session.sql(
        f"SELECT SNOWFLAKE.CORTEX.TRANSLATE('{escaped}', 'en', 'ja') AS t"
    ).collect()
    translated = result[0]["T"]
    return translated if translated else text


def process_object(session, db, schema, obj_name, obj_type,
                   tbl_comment, col_comment_map, overwrite, use_data):
    """
    1 テーブル/ビューの Description を生成・翻訳・設定する。

    技術的ポイント:
      - col_comment_map のキーは大文字で格納（大文字小文字非依存の照合のため）
      - AI が実在しないカラム名を返す場合があるため、設定前に存在確認を実施
      - カラム名が大文字以外（日本語等）の場合はダブルクォートで囲む
      - カラム単位のエラーは記録して処理を継続（ビューの制限等を考慮）
    """
    full_name    = f"{db}.{schema}.{obj_name}"
    alter_obj_kw = "VIEW" if obj_type == "VIEW" else "TABLE"
    tbl_updated  = 0
    col_updated  = 0
    col_errors   = []

    try:
        # AI_GENERATE_TABLE_DESC でテーブルとカラムの説明を一括生成
        result = session.sql(
            f"CALL AI_GENERATE_TABLE_DESC('{full_name}', "
            f"{{'describe_columns': true, 'use_table_data': {str(use_data).lower()}}})"
        ).collect()
        output = json.loads(result[0][0])

        # テーブル/ビューレベルの Description を設定
        set_tbl = overwrite or not (tbl_comment or "").strip()
        if set_tbl and "TABLE" in output and output["TABLE"]:
            desc_en         = output["TABLE"][0]["description"]
            desc_ja         = translate_to_ja(session, desc_en)
            desc_ja_escaped = desc_ja.replace("'", "\\'")
            session.sql(
                f"ALTER {alter_obj_kw} {full_name} "
                f"SET COMMENT = '{desc_ja_escaped}'"
            ).collect()
            tbl_updated = 1

        # カラムレベルの Description を設定
        for col in output.get("COLUMNS", []):
            col_name = col["name"]

            # 存在確認: AI が実在しないカラム名を返すことがある
            if col_name.upper() not in col_comment_map:
                col_errors.append(
                    f"  Column '{col_name}': not found (AI hallucination)"
                )
                continue

            existing = col_comment_map.get(col_name.upper(), "")
            if not overwrite and (existing or "").strip():
                continue

            col_desc_ja  = translate_to_ja(session, col["description"])
            col_desc_esc = col_desc_ja.replace("'", "\\'")
            quoted_col   = f'"{col_name}"' if not col_name.isupper() else col_name

            try:
                session.sql(
                    f"ALTER {alter_obj_kw} {full_name} "
                    f"MODIFY COLUMN {quoted_col} COMMENT '{col_desc_esc}'"
                ).collect()
                col_updated += 1
            except Exception as col_e:
                col_errors.append(f"  Column '{col_name}': {col_e}")

        ret = {"status": "ok", "object": full_name,
               "tbl_updated": tbl_updated, "cols_updated": col_updated}
        if col_errors:
            ret["col_errors"] = col_errors
        return ret

    except Exception as e:
        return {"status": "error", "object": full_name, "error": str(e)}


def main(session, p_database_name, p_overwrite_existing, p_use_table_data):
    """
    エントリポイント。全テーブル・ビューを並列処理して結果サマリを返す。

    技術的ポイント (並列処理):
      - joblib.Parallel + threading バックエンド
      - SQL 呼び出しは I/O バウンドなため threading が有効
      - INFORMATION_SCHEMA の情報を事前一括取得してスレッド内クエリを最小化
    """
    db = p_database_name.upper()

    # 対象 DB の全テーブル・ビューを取得
    objects_df = session.sql(f"""
        SELECT table_schema, table_name, table_type, comment
        FROM {db}.information_schema.tables
        WHERE table_type IN ('BASE TABLE', 'VIEW')
          AND table_schema NOT IN ('INFORMATION_SCHEMA')
        ORDER BY table_schema, table_name
    """).collect()

    if not objects_df:
        return f"No tables or views found in database: {db}"

    # 全カラムの既存コメントを事前一括取得（スレッド内の重複クエリ防止）
    cols_df = session.sql(f"""
        SELECT table_schema, table_name, column_name, comment
        FROM {db}.information_schema.columns
        WHERE table_schema NOT IN ('INFORMATION_SCHEMA')
    """).collect()

    # col_map: (スキーマ, テーブル) -> {カラム名大文字: 既存コメント}
    col_map = {}
    for col in cols_df:
        key = (col["TABLE_SCHEMA"], col["TABLE_NAME"])
        col_map.setdefault(key, {})[col["COLUMN_NAME"].upper()] = col["COMMENT"] or ""

    # 処理対象を絞り込む（P_OVERWRITE_EXISTING=FALSE 時）
    def needs_work(obj):
        if p_overwrite_existing:
            return True
        if not (obj["COMMENT"] or "").strip():
            return True
        tbl_key = (obj["TABLE_SCHEMA"], obj["TABLE_NAME"])
        return any(not v.strip() for v in col_map.get(tbl_key, {}).values())

    to_process    = [obj for obj in objects_df if needs_work(obj)]
    skipped_count = len(objects_df) - len(to_process)

    if not to_process:
        return (
            f"All {len(objects_df)} objects already have descriptions. "
            "Set P_OVERWRITE_EXISTING=TRUE to regenerate."
        )

    # 並列処理（最大 8 スレッド）
    n_jobs  = min(multiprocessing.cpu_count(), len(to_process), 8)
    results = Parallel(n_jobs=n_jobs, backend="threading")(
        delayed(process_object)(
            session, db,
            obj["TABLE_SCHEMA"], obj["TABLE_NAME"], obj["TABLE_TYPE"],
            obj["COMMENT"] or "",
            col_map.get((obj["TABLE_SCHEMA"], obj["TABLE_NAME"]), {}),
            p_overwrite_existing, p_use_table_data,
        )
        for obj in to_process
    )

    # 結果サマリ生成
    ok_results   = [r for r in results if r["status"] == "ok"]
    err_results  = [r for r in results if r["status"] == "error"]
    tbl_updated  = sum(r["tbl_updated"]  for r in ok_results)
    col_updated  = sum(r["cols_updated"] for r in ok_results)
    col_err_msgs = [msg for r in ok_results for msg in r.get("col_errors", [])]

    summary = (
        f"=== GENERATE_DB_DESCRIPTIONS completed ===\n"
        f"Database     : {db}\n"
        f"Total objects: {len(objects_df)}  "
        f"(processed: {len(to_process)}, skipped: {skipped_count})\n"
        f"Object descriptions updated : {tbl_updated}\n"
        f"Column descriptions updated : {col_updated}\n"
    )
    if err_results:
        summary += f"\n[Object-level errors ({len(err_results)})]\n"
        summary += "\n".join(f"  {e['object']}: {e['error']}" for e in err_results)
    if col_err_msgs:
        summary += f"\n[Column-level warnings ({len(col_err_msgs)})]\n"
        summary += "\n".join(col_err_msgs)

    return summary
$$;
