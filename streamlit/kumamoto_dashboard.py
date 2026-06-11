"""
熊本市オープンデータ ダッシュボード
Streamlit in Snowflake アプリ

【概要】
External Network Access で取り込んだ 92 テーブルの統計データを
6 カテゴリ・タブ形式で可視化するダッシュボード。

【動作環境】
Streamlit in Snowflake（SiS）で実行する。
ローカル実行は非対応（get_active_session() を使用するため）。

【カテゴリ一覧】
  Tab 1: 人口動態  - 推計人口・出生死亡・転入転出
  Tab 2: 交通      - 市電乗車人数・空港乗降客数
  Tab 3: 防災・安全 - 火災件数・交通事故件数
  Tab 4: 文化施設  - 博物館・動植物園の入館者数
  Tab 5: 経済・労働 - 家計支出・有効求人倍率
  Tab 6: 環境      - ごみ収集量・上水道使用量
"""

import altair as alt
import pandas as pd
import streamlit as st
from snowflake.snowpark.context import get_active_session

# ─── ページ設定 ────────────────────────────────────────────────────────────────
st.set_page_config(
    page_title="熊本市オープンデータ ダッシュボード",
    page_icon="🏙️",
    layout="wide",
)

# ─── Snowflake セッション取得 ──────────────────────────────────────────────────
# SiS では get_active_session() でセッションを取得する
session = get_active_session()


# ─── ユーティリティ関数 ────────────────────────────────────────────────────────
@st.cache_data(ttl=3600)
def run_query(sql: str) -> pd.DataFrame:
    """SQL を実行して DataFrame を返す（1時間キャッシュ）"""
    return session.sql(sql).to_pandas()


def line_chart(df, x, y, color=None, title="", y_label="", x_label=""):
    """Altair の折れ線グラフを生成する"""
    encoding = {
        "x": alt.X(x, title=x_label or x),
        "y": alt.Y(y, title=y_label or y),
        "tooltip": [x, y],
    }
    if color:
        encoding["color"] = alt.Color(color, legend=alt.Legend(title=color))
        encoding["tooltip"].append(color)

    chart = (
        alt.Chart(df)
        .mark_line(point=True)
        .encode(**encoding)
        .properties(title=title, height=300)
        .interactive()
    )
    return chart


def bar_chart(df, x, y, color=None, title="", y_label="", x_label="", horizontal=False):
    """Altair の棒グラフを生成する"""
    if horizontal:
        encoding = {
            "x": alt.X(y, title=y_label or y),
            "y": alt.Y(x, title=x_label or x, sort="-x"),
            "tooltip": [x, y],
        }
    else:
        encoding = {
            "x": alt.X(x, title=x_label or x),
            "y": alt.Y(y, title=y_label or y),
            "tooltip": [x, y],
        }
    if color:
        encoding["color"] = alt.Color(color, legend=alt.Legend(title=color))
        encoding["tooltip"].append(color)

    chart = (
        alt.Chart(df)
        .mark_bar()
        .encode(**encoding)
        .properties(title=title, height=300)
        .interactive()
    )
    return chart


def area_chart(df, x, y, color=None, title="", y_label=""):
    """Altair の面グラフを生成する"""
    encoding = {
        "x": alt.X(x),
        "y": alt.Y(y, title=y_label or y, stack=None),
        "opacity": alt.value(0.6),
        "tooltip": [x, y],
    }
    if color:
        encoding["color"] = alt.Color(color, legend=alt.Legend(title=color))
        encoding["tooltip"].append(color)

    chart = (
        alt.Chart(df)
        .mark_area()
        .encode(**encoding)
        .properties(title=title, height=300)
        .interactive()
    )
    return chart


# ─── タイトル ─────────────────────────────────────────────────────────────────
st.title("🏙️ 熊本市オープンデータ ダッシュボード")
st.caption("データソース: 熊本市オープンデータカタログ（BODIK ODCS）| 対象期間: 2011〜2021年")
st.divider()

# ─── サイドバー: 年度フィルタ ──────────────────────────────────────────────────
with st.sidebar:
    st.header("🔧 フィルタ設定")
    year_range = st.slider(
        "表示年度の範囲",
        min_value=2011,
        max_value=2021,
        value=(2015, 2021),
        step=1,
    )
    start_year, end_year = str(year_range[0]), str(year_range[1])
    st.info(f"表示範囲: {start_year} 〜 {end_year} 年")
    st.divider()
    st.markdown("""
    **📊 カテゴリ一覧**
    - 👥 人口動態
    - 🚃 交通
    - 🔥 防災・安全
    - 🎭 文化施設
    - 💰 経済・労働
    - ♻️ 環境
    """)

# ─── メインコンテンツ: タブ ────────────────────────────────────────────────────
tab1, tab2, tab3, tab4, tab5, tab6 = st.tabs(
    ["👥 人口動態", "🚃 交通", "🔥 防災・安全", "🎭 文化施設", "💰 経済・労働", "♻️ 環境"]
)

# ==============================================================================
# Tab 1: 人口動態
# ==============================================================================
with tab1:
    st.subheader("👥 人口動態")

    col1, col2 = st.columns(2)

    # ── 月次推計人口（性別別）────────────────────────────────────────────────
    with col1:
        with st.spinner("推計人口を読み込み中..."):
            df_pop = run_query(f"""
                SELECT "年次" AS year, "月次" AS month,
                       "性別" AS gender, "人数【人】"::INT AS population
                FROM KUMAMOTO_OPENDATA.PUBLIC.T02031_POPULATION_MONTHLY
                WHERE "年次" BETWEEN '{start_year}' AND '{end_year}'
                ORDER BY year, month
            """)
            # 総数のみで年次集計
            df_pop_total = (
                df_pop[df_pop["GENDER"] == "総数"]
                .groupby("YEAR")["POPULATION"]
                .mean()
                .reset_index()
            )
            df_pop_total.columns = ["年次", "月平均推計人口"]
            st.altair_chart(
                line_chart(df_pop_total, "年次", "月平均推計人口",
                           title="月平均推計人口の推移", y_label="人"),
                use_container_width=True,
            )

    # ── 男女別推計人口 ──────────────────────────────────────────────────────
    with col2:
        with st.spinner("男女別人口を読み込み中..."):
            df_gender = (
                df_pop[df_pop["GENDER"].isin(["男", "女"])]
                .groupby(["YEAR", "GENDER"])["POPULATION"]
                .mean()
                .reset_index()
            )
            df_gender.columns = ["年次", "性別", "月平均人口"]
            st.altair_chart(
                line_chart(df_gender, "年次", "月平均人口", color="性別",
                           title="男女別月平均推計人口", y_label="人"),
                use_container_width=True,
            )

    st.divider()
    col3, col4 = st.columns(2)

    # ── 月次出生・死亡数 ────────────────────────────────────────────────────
    with col3:
        with st.spinner("出生・死亡を読み込み中..."):
            df_bd = run_query(f"""
                SELECT "年次" AS year, "種別" AS event_type,
                       SUM("人数【人】"::INT) AS count
                FROM KUMAMOTO_OPENDATA.PUBLIC.T02040_BIRTHS_DEATHS_MONTHLY
                WHERE "性別" = '総数'
                  AND "年次" BETWEEN '{start_year}' AND '{end_year}'
                  AND "種別" IN ('出生', '死亡')
                GROUP BY year, event_type
                ORDER BY year
            """)
            df_bd.columns = ["年次", "種別", "人数"]
            st.altair_chart(
                line_chart(df_bd, "年次", "人数", color="種別",
                           title="年次出生・死亡数", y_label="人"),
                use_container_width=True,
            )

    # ── 月次転入・転出数 ────────────────────────────────────────────────────
    with col4:
        with st.spinner("転入・転出を読み込み中..."):
            df_mig = run_query(f"""
                SELECT "年次" AS year, "種別" AS type,
                       SUM("人数【人】又は件数【件】"::INT) AS count
                FROM KUMAMOTO_OPENDATA.PUBLIC.T02050_MIGRATION_MARRIAGE_MONTHLY
                WHERE "性別" = '総数'
                  AND "年次" BETWEEN '{start_year}' AND '{end_year}'
                  AND "種別" IN ('転入', '転出')
                GROUP BY year, type
                ORDER BY year
            """)
            df_mig.columns = ["年次", "種別", "人数"]
            st.altair_chart(
                line_chart(df_mig, "年次", "人数", color="種別",
                           title="年次転入・転出数", y_label="人"),
                use_container_width=True,
            )

# ==============================================================================
# Tab 2: 交通
# ==============================================================================
with tab2:
    st.subheader("🚃 交通")

    col1, col2 = st.columns(2)

    # ── 市電月次乗車人数 ───────────────────────────────────────────────────
    with col1:
        with st.spinner("市電データを読み込み中..."):
            df_tram = run_query(f"""
                SELECT "年度" AS year,
                       SUM("乗車人数【人】"::INT) / 12 AS avg_monthly_ridership,
                       SUM("乗車料収入【円】"::INT) / 12 AS avg_monthly_revenue
                FROM KUMAMOTO_OPENDATA.PUBLIC.T11051_TRAM_RIDERSHIP_REVENUE_MONTHLY
                WHERE "総数/定期/定期外" = '総数'
                  AND "年度" BETWEEN '{start_year}' AND '{end_year}'
                GROUP BY year
                ORDER BY year
            """)
            df_tram.columns = ["年度", "月平均乗車人数", "月平均収入"]
            st.altair_chart(
                bar_chart(df_tram, "年度", "月平均乗車人数",
                          title="市電 年度別月平均乗車人数", y_label="人"),
                use_container_width=True,
            )

    # ── 市電 定期・定期外割合 ───────────────────────────────────────────────
    with col2:
        with st.spinner("市電内訳を読み込み中..."):
            df_tram_type = run_query(f"""
                SELECT "年度" AS year,
                       "総数/定期/定期外" AS ticket_type,
                       SUM("乗車人数【人】"::INT) AS ridership
                FROM KUMAMOTO_OPENDATA.PUBLIC.T11051_TRAM_RIDERSHIP_REVENUE_MONTHLY
                WHERE "総数/定期/定期外" IN ('定期', '定期外')
                  AND "年度" BETWEEN '{start_year}' AND '{end_year}'
                GROUP BY year, ticket_type
                ORDER BY year
            """)
            df_tram_type.columns = ["年度", "乗車区分", "乗車人数"]
            st.altair_chart(
                area_chart(df_tram_type, "年度", "乗車人数", color="乗車区分",
                           title="市電 定期・定期外乗車人数", y_label="人"),
                use_container_width=True,
            )

    st.divider()
    col3, col4 = st.columns(2)

    # ── 空港月次乗降客数 ───────────────────────────────────────────────────
    with col3:
        with st.spinner("空港データを読み込み中..."):
            df_air = run_query(f"""
                SELECT "年度" AS year,
                       SUM("人数【人】"::INT) AS total_passengers
                FROM KUMAMOTO_OPENDATA.PUBLIC.T11031_AIRPORT_PASSENGERS_MONTHLY
                WHERE "年度" BETWEEN '{start_year}' AND '{end_year}'
                GROUP BY year
                ORDER BY year
            """)
            df_air.columns = ["年度", "年間乗降客数"]
            st.altair_chart(
                bar_chart(df_air, "年度", "年間乗降客数",
                          title="熊本空港 年間乗降客数", y_label="人"),
                use_container_width=True,
            )

    # ── 市電 乗車料収入推移 ─────────────────────────────────────────────────
    with col4:
        st.altair_chart(
            line_chart(df_tram, "年度", "月平均収入",
                       title="市電 年度別月平均乗車料収入", y_label="円"),
            use_container_width=True,
        )

# ==============================================================================
# Tab 3: 防災・安全
# ==============================================================================
with tab3:
    st.subheader("🔥 防災・安全")

    col1, col2 = st.columns(2)

    # ── 火災件数の年次推移 ─────────────────────────────────────────────────
    with col1:
        with st.spinner("火災データを読み込み中..."):
            df_fire = run_query(f"""
                SELECT "年次" AS year, "種別" AS fire_type,
                       SUM("件数"::INT) AS count,
                       SUM("損害額【円】"::INT) AS damage
                FROM KUMAMOTO_OPENDATA.PUBLIC.T15191_FIRE_INCIDENTS_DAMAGE
                WHERE "年次" BETWEEN '{start_year}' AND '{end_year}'
                GROUP BY year, fire_type
                ORDER BY year, fire_type
            """)
            df_fire.columns = ["年次", "種別", "件数", "損害額"]
            # 全種別合計
            df_fire_total = df_fire.groupby("年次")[["件数", "損害額"]].sum().reset_index()
            st.altair_chart(
                bar_chart(df_fire_total, "年次", "件数",
                          title="年次火災件数（全種別合計）", y_label="件"),
                use_container_width=True,
            )

    # ── 火災 種別内訳 ──────────────────────────────────────────────────────
    with col2:
        df_fire_type = df_fire[df_fire["種別"].isin(["建物", "車両", "林野", "その他"])]
        st.altair_chart(
            bar_chart(df_fire_type, "年次", "件数", color="種別",
                      title="火災件数 種別内訳", y_label="件"),
            use_container_width=True,
        )

    st.divider()
    col3, col4 = st.columns(2)

    # ── 交通事故件数 ───────────────────────────────────────────────────────
    with col3:
        with st.spinner("交通事故データを読み込み中..."):
            df_acc = run_query(f"""
                SELECT "年次" AS year,
                       "件数/死者/傷者" AS stat_type,
                       SUM("件数【件】・人数【人】"::INT) AS count
                FROM KUMAMOTO_OPENDATA.PUBLIC.T15120_TRAFFIC_ACCIDENTS_BY_STATION
                WHERE "年次" BETWEEN '{start_year}' AND '{end_year}'
                  AND "件数/死者/傷者" IN ('件数', '死者', '傷者')
                GROUP BY year, stat_type
                ORDER BY year, stat_type
            """)
            df_acc.columns = ["年次", "区分", "件数・人数"]
            df_acc_incidents = df_acc[df_acc["区分"] == "件数"]
            st.altair_chart(
                line_chart(df_acc_incidents, "年次", "件数・人数",
                           title="年次交通事故件数", y_label="件"),
                use_container_width=True,
            )

    # ── 交通事故 死傷者数 ──────────────────────────────────────────────────
    with col4:
        df_cas = df_acc[df_acc["区分"].isin(["死者", "傷者"])]
        st.altair_chart(
            line_chart(df_cas, "年次", "件数・人数", color="区分",
                       title="交通事故 死傷者数の推移", y_label="人"),
            use_container_width=True,
        )

    # ── 火災損害額 ────────────────────────────────────────────────────────
    st.altair_chart(
        line_chart(df_fire_total, "年次", "損害額",
                   title="年次火災損害額", y_label="円"),
        use_container_width=True,
    )

# ==============================================================================
# Tab 4: 文化施設
# ==============================================================================
with tab4:
    st.subheader("🎭 文化施設")

    col1, col2 = st.columns(2)

    # ── 博物館 月次入館者数 ─────────────────────────────────────────────────
    with col1:
        with st.spinner("博物館データを読み込み中..."):
            df_museum = run_query(f"""
                SELECT "年度" AS year,
                       SUM("人数【人】"::INT) AS visitors
                FROM KUMAMOTO_OPENDATA.PUBLIC.T18172_MUSEUM_VISITORS_MONTHLY
                WHERE "年度" BETWEEN '{start_year}' AND '{end_year}'
                GROUP BY year
                ORDER BY year
            """)
            df_museum.columns = ["年度", "年間入館者数"]
            st.altair_chart(
                bar_chart(df_museum, "年度", "年間入館者数",
                          title="熊本博物館 年間入館者数", y_label="人"),
                use_container_width=True,
            )

    # ── 動植物園 月次入園者数 ──────────────────────────────────────────────
    with col2:
        with st.spinner("動植物園データを読み込み中..."):
            df_zoo = run_query(f"""
                SELECT "年度" AS year,
                       SUM("入園者総数【人】"::INT) AS visitors
                FROM KUMAMOTO_OPENDATA.PUBLIC.T18201_ZOO_MONTHLY_OVERVIEW
                WHERE "年度" BETWEEN '{start_year}' AND '{end_year}'
                GROUP BY year
                ORDER BY year
            """)
            df_zoo.columns = ["年度", "年間入園者数"]
            st.altair_chart(
                bar_chart(df_zoo, "年度", "年間入園者数",
                          title="熊本市動植物園 年間入園者数", y_label="人"),
                use_container_width=True,
            )

    # ── 博物館 vs 動植物園 比較 ────────────────────────────────────────────
    st.divider()
    with st.spinner("比較データを読み込み中..."):
        df_compare = pd.merge(
            df_museum.rename(columns={"年間入館者数": "博物館"}),
            df_zoo.rename(columns={"年間入園者数": "動植物園"}),
            on="年度",
        )
        df_compare_long = df_compare.melt(
            id_vars="年度", var_name="施設", value_name="年間入館者数"
        )
        st.altair_chart(
            line_chart(df_compare_long, "年度", "年間入館者数", color="施設",
                       title="博物館 vs 動植物園 年間入館者数比較", y_label="人"),
            use_container_width=True,
        )

    # ── 現代美術館 入館者数 ────────────────────────────────────────────────
    col3, col4 = st.columns(2)
    with col3:
        with st.spinner("現代美術館データを読み込み中..."):
            df_art = run_query(f"""
                SELECT "年度" AS year,
                       SUM("入館者総数【人】"::INT) AS visitors
                FROM KUMAMOTO_OPENDATA.PUBLIC.T18191_CONTEMPORARY_ART_MUSEUM_MONTHLY
                WHERE "年度" BETWEEN '{start_year}' AND '{end_year}'
                GROUP BY year
                ORDER BY year
            """)
            df_art.columns = ["年度", "年間入館者数"]
            st.altair_chart(
                line_chart(df_art, "年度", "年間入館者数",
                           title="熊本市現代美術館 年間入館者数", y_label="人"),
                use_container_width=True,
            )

# ==============================================================================
# Tab 5: 経済・労働
# ==============================================================================
with tab5:
    st.subheader("💰 経済・労働")

    col1, col2 = st.columns(2)

    # ── 有効求人倍率 ───────────────────────────────────────────────────────
    with col1:
        with st.spinner("有効求人倍率を読み込み中..."):
            df_job = run_query(f"""
                SELECT "年度" AS year, "年月" AS month, "比率"::FLOAT AS rate
                FROM KUMAMOTO_OPENDATA.PUBLIC.T12055_JOB_VACANCY_RATE_MONTHLY
                WHERE "種別" = '有効求人倍率'
                  AND "年度" BETWEEN '{start_year}' AND '{end_year}'
                ORDER BY year, month
            """)
            df_job.columns = ["年度", "年月", "有効求人倍率"]
            st.altair_chart(
                line_chart(df_job, "年月", "有効求人倍率",
                           title="有効求人倍率の推移", y_label="倍"),
                use_container_width=True,
            )

    # ── 就職率・充足率 ─────────────────────────────────────────────────────
    with col2:
        with st.spinner("就職率を読み込み中..."):
            df_emp = run_query(f"""
                SELECT "年度" AS year, "年月" AS month,
                       "種別" AS rate_type, "比率"::FLOAT AS rate
                FROM KUMAMOTO_OPENDATA.PUBLIC.T12055_JOB_VACANCY_RATE_MONTHLY
                WHERE "種別" IN ('就職率', '充足率')
                  AND "年度" BETWEEN '{start_year}' AND '{end_year}'
                ORDER BY year, month
            """)
            df_emp.columns = ["年度", "年月", "種別", "比率(%)"]
            st.altair_chart(
                line_chart(df_emp, "年月", "比率(%)", color="種別",
                           title="就職率・充足率の推移", y_label="%"),
                use_container_width=True,
            )

    st.divider()
    col3, col4 = st.columns(2)

    # ── 世帯月次家計支出（大項目別） ──────────────────────────────────────
    with col3:
        with st.spinner("家計支出を読み込み中..."):
            df_exp = run_query(f"""
                SELECT "年次" AS year, "大項目" AS category,
                       SUM("支出【円】"::INT) AS total_expense
                FROM KUMAMOTO_OPENDATA.PUBLIC.T09011_HOUSEHOLD_MONTHLY_EXPENDITURE
                WHERE "年次" BETWEEN '{start_year}' AND '{end_year}'
                GROUP BY year, category
                ORDER BY year, total_expense DESC
            """)
            df_exp.columns = ["年次", "費目", "支出額"]
            # 最新年の費目別支出
            latest_year = df_exp["年次"].max()
            df_exp_latest = df_exp[df_exp["年次"] == latest_year].nlargest(8, "支出額")
            st.altair_chart(
                bar_chart(df_exp_latest, "費目", "支出額",
                          title=f"費目別家計支出（{latest_year}年）",
                          y_label="円", horizontal=True),
                use_container_width=True,
            )

    # ── 家計支出 年次推移 ──────────────────────────────────────────────────
    with col4:
        df_exp_year = df_exp.groupby("年次")["支出額"].sum().reset_index()
        df_exp_year.columns = ["年次", "年間支出総額"]
        st.altair_chart(
            line_chart(df_exp_year, "年次", "年間支出総額",
                       title="年間家計支出総額の推移", y_label="円"),
            use_container_width=True,
        )

# ==============================================================================
# Tab 6: 環境
# ==============================================================================
with tab6:
    st.subheader("♻️ 環境")

    col1, col2 = st.columns(2)

    # ── 月次ごみ収集量 ─────────────────────────────────────────────────────
    with col1:
        with st.spinner("ごみ収集データを読み込み中..."):
            df_waste = run_query(f"""
                SELECT "年度" AS year,
                       SUM("数量【t】"::FLOAT) AS total_tons
                FROM KUMAMOTO_OPENDATA.PUBLIC.T13180_WASTE_PROCESSING_MONTHLY
                WHERE "収集および搬入量/処理量" = '収集および搬入量'
                  AND "年度" BETWEEN '{start_year}' AND '{end_year}'
                GROUP BY year
                ORDER BY year
            """)
            df_waste.columns = ["年度", "年間ごみ収集量(t)"]
            st.altair_chart(
                line_chart(df_waste, "年度", "年間ごみ収集量(t)",
                           title="年間ごみ収集量の推移", y_label="トン"),
                use_container_width=True,
            )

    # ── 上水道 用途別使用量 ────────────────────────────────────────────────
    with col2:
        with st.spinner("上水道データを読み込み中..."):
            df_water = run_query(f"""
                SELECT "年度" AS year, "用途" AS purpose,
                       SUM("水量【m3】"::INT) AS volume
                FROM KUMAMOTO_OPENDATA.PUBLIC.T08080_WATER_SUPPLY_BY_PURPOSE
                WHERE "年度" BETWEEN '{start_year}' AND '{end_year}'
                GROUP BY year, purpose
                ORDER BY year, volume DESC
            """)
            df_water.columns = ["年度", "用途", "水量(m3)"]
            st.altair_chart(
                area_chart(df_water, "年度", "水量(m3)", color="用途",
                           title="上水道 用途別水量の推移", y_label="m3"),
                use_container_width=True,
            )

    st.divider()
    col3, col4 = st.columns(2)

    # ── ごみ処理量（処理方法別） ───────────────────────────────────────────
    with col3:
        with st.spinner("ごみ処理量を読み込み中..."):
            df_waste_type = run_query(f"""
                SELECT "年度" AS year, "種別" AS waste_type,
                       SUM("数量【t】"::FLOAT) AS total_tons
                FROM KUMAMOTO_OPENDATA.PUBLIC.T13180_WASTE_PROCESSING_MONTHLY
                WHERE "収集および搬入量/処理量" = '収集および搬入量'
                  AND "年度" BETWEEN '{start_year}' AND '{end_year}'
                GROUP BY year, waste_type
                ORDER BY year, total_tons DESC
            """)
            df_waste_type.columns = ["年度", "種別", "収集量(t)"]
            # 上位5種別
            top5 = (
                df_waste_type.groupby("種別")["収集量(t)"]
                .sum()
                .nlargest(5)
                .index.tolist()
            )
            df_waste_top = df_waste_type[df_waste_type["種別"].isin(top5)]
            st.altair_chart(
                bar_chart(df_waste_top, "年度", "収集量(t)", color="種別",
                          title="ごみ種別収集量（上位5種別）", y_label="トン"),
                use_container_width=True,
            )

    # ── 上水道 総使用量 ────────────────────────────────────────────────────
    with col4:
        df_water_total = df_water.groupby("年度")["水量(m3)"].sum().reset_index()
        df_water_total.columns = ["年度", "総水量(m3)"]
        st.altair_chart(
            line_chart(df_water_total, "年度", "総水量(m3)",
                       title="上水道 年間総有収水量", y_label="m3"),
            use_container_width=True,
        )

# ─── フッター ──────────────────────────────────────────────────────────────────
st.divider()
st.caption(
    "データ: 熊本市オープンデータカタログ（BODIK ODCS）| "
    "Snowflake External Network Access で取り込んだ 92 テーブルを可視化"
)
