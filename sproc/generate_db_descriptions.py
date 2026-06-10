# =============================================================================
# generate_db_descriptions.py
#
# 概要:
#   Snowflake の AI_GENERATE_TABLE_DESC を使って、指定した DB 内の
#   全テーブル・ビューおよびその全カラムの Description を自動生成し、
#   COMMENT として設定するストアドプロシージャ。
#
#   生成された Description は英語のため、SNOWFLAKE.CORTEX.TRANSLATE を
#   用いて日本語に翻訳してから設定する。
#
# アーキテクチャ上のポイント:
#   - AI_GENERATE_TABLE_DESC: Snowflake Cortex が LLM を使ってテーブル・
#     カラムの説明を自動生成する組み込み SP (Preview 機能)
#   - CORTEX.TRANSLATE: 生成された英語説明を日本語に翻訳
#   - joblib.Parallel: テーブルを並列処理してスループットを向上
#   - カラム存在チェック: AI が実在しないカラム名を返す場合に対応
#
# デプロイ先:
#   sql/03_ai_desc_sproc.sql を実行することでデプロイされる。
#
# 呼び出し例:
#   -- 未設定のオブジェクトのみ生成（メタデータのみ使用）
#   CALL KUMAMOTO_OPENDATA.PUBLIC.GENERATE_DB_DESCRIPTIONS(
#       'KUMAMOTO_OPENDATA', FALSE, FALSE
#   );
#
#   -- 全件上書き再生成（実データをサンプリングして精度向上）
#   CALL KUMAMOTO_OPENDATA.PUBLIC.GENERATE_DB_DESCRIPTIONS(
#       'KUMAMOTO_OPENDATA', TRUE, TRUE
#   );
#
# パラメータ:
#   P_DATABASE_NAME      STRING  : 対象データベース名
#   P_OVERWRITE_EXISTING BOOLEAN : TRUE=既存 Description を上書き
#                                  FALSE=未設定のもののみ生成
#   P_USE_TABLE_DATA     BOOLEAN : TRUE=実データをサンプリングして精度向上
#                                  FALSE=メタデータのみで生成（コスト低）
#
# 必要な権限:
#   - 対象テーブル・ビューへの SELECT 権限
#   - SNOWFLAKE.CORTEX_USER データベースロール
#
# 注意事項:
#   - AI_GENERATE_TABLE_DESC は Preview 機能（2025年8月時点）
#   - Cortex COMPLETE / TRANSLATE の利用分だけ追加コストが発生する
#   - 5,000 カラムを超えるテーブルはカラム Description 生成不可
#   - カラム数の多い DB では実行時間が長くなる場合がある
# =============================================================================

import json
from joblib import Parallel, delayed
import multiprocessing


def translate_to_ja(session, text):
    """
    英語テキストを日本語に翻訳する。

    SNOWFLAKE.CORTEX.TRANSLATE を使用。翻訳結果が空の場合は元のテキストを返す。

    技術的ポイント:
      シングルクォートをエスケープして SQL インジェクションを防ぐ。
    """
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
    1つのテーブルまたはビューに対して以下を行う。
      1. AI_GENERATE_TABLE_DESC でテーブルおよびカラムの Description を生成
      2. CORTEX.TRANSLATE で日本語に翻訳
      3. P_OVERWRITE_EXISTING の設定に従い ALTER TABLE/VIEW で COMMENT を設定

    技術的ポイント (カラムコメント設定):
      - col_comment_map のキーは大文字 (COLUMN_NAME.upper()) で格納されている
      - AI が実在しないカラム名を返すことがあるため、設定前に存在確認を行う
        （例: AI が "町字" を返したが実際のカラムは "町字ID" だった）
      - カラム名が大文字以外を含む場合（日本語等）はダブルクォートで囲む

    Parameters
    ----------
    session        : Snowpark セッション
    db             : データベース名（大文字）
    schema         : スキーマ名
    obj_name       : テーブル/ビュー名
    obj_type       : 'BASE TABLE' or 'VIEW'
    tbl_comment    : 既存のテーブルレベルコメント（空文字列の場合は未設定）
    col_comment_map: {カラム名大文字: 既存コメント} の辞書
    overwrite      : True=既存コメントを上書き / False=未設定のみ更新
    use_data       : AI_GENERATE_TABLE_DESC の use_table_data オプション

    Returns
    -------
    dict: 処理結果。status='ok' または 'error'
    """
    full_name    = f"{db}.{schema}.{obj_name}"
    alter_obj_kw = "VIEW" if obj_type == "VIEW" else "TABLE"
    tbl_updated  = 0
    col_updated  = 0
    col_errors   = []

    try:
        # ── Step 1: AI_GENERATE_TABLE_DESC で Description を生成 ──────────
        result = session.sql(
            f"CALL AI_GENERATE_TABLE_DESC('{full_name}', "
            f"{{'describe_columns': true, 'use_table_data': {str(use_data).lower()}}})"
        ).collect()
        output = json.loads(result[0][0])

        # ── Step 2: テーブル/ビューレベルの Description を設定 ───────────
        # overwrite=True または既存コメントが空の場合のみ設定する
        set_tbl = overwrite or not (tbl_comment or "").strip()
        if set_tbl and "TABLE" in output and output["TABLE"]:
            desc_en        = output["TABLE"][0]["description"]
            desc_ja        = translate_to_ja(session, desc_en)
            desc_ja_escaped = desc_ja.replace("'", "\\'")
            session.sql(
                f"ALTER {alter_obj_kw} {full_name} "
                f"SET COMMENT = '{desc_ja_escaped}'"
            ).collect()
            tbl_updated = 1

        # ── Step 3: カラムレベルの Description を設定 ────────────────────
        for col in output.get("COLUMNS", []):
            col_name = col["name"]

            # 存在確認: AI が実在しないカラム名を返す場合がある
            # col_comment_map のキーは大文字で格納されているため upper() で比較
            if col_name.upper() not in col_comment_map:
                col_errors.append(
                    f"  Column '{col_name}': not found in table (AI hallucination)"
                )
                continue

            existing = col_comment_map.get(col_name.upper(), "")
            set_col  = overwrite or not (existing or "").strip()
            if not set_col:
                continue

            col_desc_en  = col["description"]
            col_desc_ja  = translate_to_ja(session, col_desc_en)
            col_desc_esc = col_desc_ja.replace("'", "\\'")

            # 大文字のみのカラム名はクォート不要（例: ID）
            # それ以外（日本語、アンダースコア混じり等）はダブルクォートで囲む
            quoted_col = f'"{col_name}"' if not col_name.isupper() else col_name

            try:
                session.sql(
                    f"ALTER {alter_obj_kw} {full_name} "
                    f"MODIFY COLUMN {quoted_col} COMMENT '{col_desc_esc}'"
                ).collect()
                col_updated += 1
            except Exception as col_e:
                # カラム単位のエラーは記録して処理を継続する
                # （ビューのカラムコメント制限、権限不足 等）
                col_errors.append(f"  Column '{col_name}': {col_e}")

        ret = {
            "status": "ok",
            "object": full_name,
            "tbl_updated": tbl_updated,
            "cols_updated": col_updated,
        }
        if col_errors:
            ret["col_errors"] = col_errors
        return ret

    except Exception as e:
        # テーブル単位のエラーは記録して他のテーブルの処理を継続する
        return {"status": "error", "object": full_name, "error": str(e)}


def main(session, p_database_name, p_overwrite_existing, p_use_table_data):
    """
    ストアドプロシージャのエントリポイント。
    指定 DB 内の全テーブル・ビューを並列処理し、結果サマリを返す。

    技術的ポイント (並列処理):
      joblib.Parallel + threading バックエンドを使用。
      - threading: GIL があるが、SQL 呼び出しは I/O バウンドなため有効
      - n_jobs: CPU コア数と対象オブジェクト数の小さい方（最大 8）
      - 各スレッドは同一の session オブジェクトを共有する
        （Snowpark の session は read 操作において thread-safe）
    """
    db = p_database_name.upper()

    # ── 1. 対象 DB の全テーブル・ビューを取得 ────────────────────────────
    objects_df = session.sql(f"""
        SELECT table_schema, table_name, table_type, comment
        FROM {db}.information_schema.tables
        WHERE table_type IN ('BASE TABLE', 'VIEW')
          AND table_schema NOT IN ('INFORMATION_SCHEMA')
        ORDER BY table_schema, table_name
    """).collect()

    if not objects_df:
        return f"No tables or views found in database: {db}"

    # ── 2. 全カラムの既存コメントを一括取得 ─────────────────────────────
    # スレッド内での重複クエリを避けるため、事前に全件取得しておく
    cols_df = session.sql(f"""
        SELECT table_schema, table_name, column_name, comment
        FROM {db}.information_schema.columns
        WHERE table_schema NOT IN ('INFORMATION_SCHEMA')
    """).collect()

    # col_map: (スキーマ名, テーブル名) -> {カラム名大文字: 既存コメント}
    # カラム名を大文字化して格納するのは、AI が返すカラム名との照合を
    # 大文字小文字に依存しない形で行うため
    col_map = {}
    for col in cols_df:
        key = (col["TABLE_SCHEMA"], col["TABLE_NAME"])
        col_map.setdefault(key, {})[col["COLUMN_NAME"].upper()] = col["COMMENT"] or ""

    # ── 3. 処理が必要なオブジェクトを絞り込む ────────────────────────────
    def needs_work(obj):
        """
        以下のいずれかに該当する場合に処理対象とする。
          - P_OVERWRITE_EXISTING=TRUE（常に処理）
          - テーブルのコメントが未設定
          - 1つでもコメントが未設定のカラムが存在する
        """
        if p_overwrite_existing:
            return True
        if not (obj["COMMENT"] or "").strip():
            return True  # テーブルレベルのコメントが未設定
        tbl_key = (obj["TABLE_SCHEMA"], obj["TABLE_NAME"])
        return any(not v.strip() for v in col_map.get(tbl_key, {}).values())

    to_process    = [obj for obj in objects_df if needs_work(obj)]
    skipped_count = len(objects_df) - len(to_process)

    if not to_process:
        return (
            f"All {len(objects_df)} objects already have descriptions. "
            "Set P_OVERWRITE_EXISTING=TRUE to regenerate."
        )

    # ── 4. テーブル単位で並列処理 ────────────────────────────────────────
    n_jobs  = min(multiprocessing.cpu_count(), len(to_process), 8)
    results = Parallel(n_jobs=n_jobs, backend="threading")(
        delayed(process_object)(
            session,
            db,
            obj["TABLE_SCHEMA"],
            obj["TABLE_NAME"],
            obj["TABLE_TYPE"],
            obj["COMMENT"] or "",
            col_map.get((obj["TABLE_SCHEMA"], obj["TABLE_NAME"]), {}),
            p_overwrite_existing,
            p_use_table_data,
        )
        for obj in to_process
    )

    # ── 5. 実行結果のサマリを生成して返す ────────────────────────────────
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
