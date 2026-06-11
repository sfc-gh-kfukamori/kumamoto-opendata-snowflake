-- ============================================================
-- Snowflake Intelligence Hands-on Lab
-- STEP 3: Semantic View の作成
-- ============================================================
--
-- 【このステップでやること】
--   Cortex Analyst（Snowflake Intelligence の AI コア）が
--   テーブルの意味を理解するための Semantic View を作成します。
--
-- 【Semantic View とは?】
--   テーブル・カラムの説明・別名(synonym)・メトリクス・
--   テーブル間のリレーションシップ・検証済みクエリ(VQR)などを
--   定義したメタデータオブジェクトです。
--   Cortex Analyst はこれを参照して自然言語 → SQL 変換を行います。
--
-- 【このハンズオンで定義する内容】
--   - 対象テーブル : 14 テーブル（人口・交通・防災・文化・環境・経済）
--   - ファクト    : 24 個（推計人口・乗車人数・件数など）
--   - ディメンション: 46 個（年次・月次・性別・種別など）
--   - メトリクス  :  6 個（動植物園・火災・水道の集計値）
--   - VQR（検証済みクエリ）: 16 本（単一テーブル＋クロステーブル）
--   - カスタムインストラクション: データ特性・フィルタ値の説明
--
-- 【セクションの記述順序（重要）】
--   TABLES → RELATIONSHIPS → FACTS → DIMENSIONS → METRICS
--   → COMMENT → AI_SQL_GENERATION → AI_VERIFIED_QUERIES
--
-- 【前提条件】  STEP2_ingest_data.sql が実行済みで 92 テーブルが存在すること
-- 【実行ロール】ACCOUNTADMIN
-- 【実行時間の目安】数秒
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE KUMAMOTO_OPENDATA;
USE SCHEMA PUBLIC;
USE WAREHOUSE COMPUTE_WH;


-- ============================================================
-- STEP 3-1: Semantic View の作成
-- ============================================================

CREATE OR REPLACE SEMANTIC VIEW KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_CITY_STATISTICS

    -- ─── TABLES ─────────────────────────────────────────────
    -- 対象の物理テーブルを論理名で定義する
    -- 書式: 論理名 AS DB.SCHEMA.物理テーブル名
    --   PRIMARY KEY: 1行を一意に識別する列（リレーション推論に使用）
    --   COMMENT    : Cortex Analyst がテーブルの内容を理解するための説明
    TABLES (
        T02031_POPULATION_MONTHLY AS KUMAMOTO_OPENDATA.PUBLIC.T02031_POPULATION_MONTHLY
            COMMENT = '熊本市の月次推計人口。性別（総数・男・女）×年次×月次で記録。 人口合計を取得する場合は 性別=''総数'' でフィルターする。',
        T02040_BIRTHS_DEATHS_MONTHLY AS KUMAMOTO_OPENDATA.PUBLIC.T02040_BIRTHS_DEATHS_MONTHLY
            COMMENT = '熊本市の月次出生・死亡統計。種別（出生・死亡）×性別×年次×月次で記録。 出生数は 種別=''出生'' AND 性別=''総数''、死亡数は 種別=''死亡'' AND 性別=''総数'' でフィルター。',
        T02050_MIGRATION_MARRIAGE_MONTHLY AS KUMAMOTO_OPENDATA.PUBLIC.T02050_MIGRATION_MARRIAGE_MONTHLY
            COMMENT = '熊本市の月次社会動態（転入・転出）と婚姻・離婚件数。 種別（転入・転出・婚姻・離婚）×性別×年次×月次で記録。',
        T11051_TRAM_RIDERSHIP_REVENUE_MONTHLY AS KUMAMOTO_OPENDATA.PUBLIC.T11051_TRAM_RIDERSHIP_REVENUE_MONTHLY
            COMMENT = '熊本市電の月次乗車人数と乗車料収入。総数・定期・定期外の3区分で記録。 合計値は 総数/定期/定期外=''総数'' でフィルターして取得。',
        T11052_TRAM_OPERATION_STATS_MONTHLY AS KUMAMOTO_OPENDATA.PUBLIC.T11052_TRAM_OPERATION_STATS_MONTHLY
            COMMENT = '熊本市電の月次運行統計。営業路線延長・在籍車両数・使用車両数・運転キロ数。',
        T11031_AIRPORT_PASSENGERS_MONTHLY AS KUMAMOTO_OPENDATA.PUBLIC.T11031_AIRPORT_PASSENGERS_MONTHLY
            COMMENT = '熊本空港の月次乗降客数。乗客（搭乗）と降客（到着）の区分で記録。 合計を求める場合は両方を SUM するか乗客/降客 列でフィルターする。',
        T18172_MUSEUM_VISITORS_MONTHLY AS KUMAMOTO_OPENDATA.PUBLIC.T18172_MUSEUM_VISITORS_MONTHLY
            PRIMARY KEY (NIANDU, YUECI, FENLEI, DAREN_XIAOZHONGXUESHENG)
            COMMENT = '熊本博物館の月次入館者数。分類（総数など）×大人/小中学生の区分で記録。',
        T18201_ZOO_MONTHLY_OVERVIEW AS KUMAMOTO_OPENDATA.PUBLIC.T18201_ZOO_MONTHLY_OVERVIEW
            PRIMARY KEY (NIANDU, YUECI)
            COMMENT = '熊本市動植物園の月次概況。開園日数・入園者総数・1日平均入園者数。 年度×月次で1レコード（主キー）。',
        T15191_FIRE_INCIDENTS_DAMAGE AS KUMAMOTO_OPENDATA.PUBLIC.T15191_FIRE_INCIDENTS_DAMAGE
            COMMENT = '熊本市消防局管内の月次火災件数と損害。種別（建物・林野・車両・船舶・航空機・その他・計）で記録。 合計は 種別=''計'' でフィルター。',
        T15120_TRAFFIC_ACCIDENTS_BY_STATION AS KUMAMOTO_OPENDATA.PUBLIC.T15120_TRAFFIC_ACCIDENTS_BY_STATION
            COMMENT = '警察署管轄別・月次の交通事故件数・死者数・傷者数。 件数/死者/傷者 列の値（件数・死者数・傷者数）でフィルターして集計。',
        T13180_WASTE_PROCESSING_MONTHLY AS KUMAMOTO_OPENDATA.PUBLIC.T13180_WASTE_PROCESSING_MONTHLY
            COMMENT = '熊本市の月次ごみ処理概況。収集量・搬入量・処理量の区分、ごみの種別（燃やすごみ・粗大ごみ等）で記録。 収集量は 収集および搬入量/処理量=''収集'' でフィルター。',
        T08080_WATER_SUPPLY_BY_PURPOSE AS KUMAMOTO_OPENDATA.PUBLIC.T08080_WATER_SUPPLY_BY_PURPOSE
            COMMENT = '熊本市の年度別・用途別の上水道使用状況。家事用・営業用・工場用等の区分で件数と水量を記録。',
        T09011_HOUSEHOLD_MONTHLY_EXPENDITURE AS KUMAMOTO_OPENDATA.PUBLIC.T09011_HOUSEHOLD_MONTHLY_EXPENDITURE
            COMMENT = '熊本市の家計調査報告による月次家計支出。大項目・中項目の費目分類で記録。',
        T12055_JOB_VACANCY_RATE_MONTHLY AS KUMAMOTO_OPENDATA.PUBLIC.T12055_JOB_VACANCY_RATE_MONTHLY
            COMMENT = '熊本公共職業安定所調査による月次有効求人倍率・就職率・充足率。 種別（有効求人倍率（季節調整値）・有効求人倍率（パートタイムを除く）等）で記録。'
    )

    -- ─── RELATIONSHIPS ──────────────────────────────────────
    -- テーブル間の結合条件を定義する
    -- 書式: リレーション名 AS 左テーブル(列) REFERENCES 右テーブル(列)
    RELATIONSHIPS (
        museum_to_zoo_monthly AS
            T18172_MUSEUM_VISITORS_MONTHLY (NIANDU, YUECI) REFERENCES T18201_ZOO_MONTHLY_OVERVIEW (NIANDU, YUECI)
    )

    -- ─── FACTS ──────────────────────────────────────────────
    -- 数値型の列を「ファクト（集計可能な生の数値）」として定義する
    -- DIMENSIONS との違い: SUM/AVG 等の集計対象となる数値列
    -- 書式: テーブル名.ファクト名 AS 物理列名_または_キャスト式
    -- ※ セクション順序: FACTS は DIMENSIONS より前に記述する
    FACTS (
        T02031_POPULATION_MONTHLY.JINKO AS "人数【人】"::INT
            WITH SYNONYMS = ('人口', '推計人口', '住民数')
            COMMENT = '推計人口（人）。性別=''総数'' でフィルターして合計するのが基本。',
        T02040_BIRTHS_DEATHS_MONTHLY.SHIZEN_DOTAI AS "人数【人】"::INT
            WITH SYNONYMS = ('自然動態', '出生死亡数')
            COMMENT = '出生または死亡の人数（人）',
        T02050_MIGRATION_MARRIAGE_MONTHLY.SHAKAI_DOTAI AS "人数【人】又は件数【件】"::INT
            WITH SYNONYMS = ('転入転出数', '件数', '婚姻離婚件数')
            COMMENT = '転入・転出の人数または婚姻・離婚の件数',
        T11051_TRAM_RIDERSHIP_REVENUE_MONTHLY.JOSHARENSHU AS "乗車人数【人】"::INT
            WITH SYNONYMS = ('乗車人数', '乗客数', '市電利用者')
            COMMENT = '市電の乗車人数（人）',
        T11051_TRAM_RIDERSHIP_REVENUE_MONTHLY.JOSHARYOSHOURU AS "乗車料収入【円】"::INT
            WITH SYNONYMS = ('乗車料収入', '収入', '運賃収入')
            COMMENT = '乗車料収入（円）',
        T11052_TRAM_OPERATION_STATS_MONTHLY.EIGYO_ROSEN_KM AS "営業路線【km】"::FLOAT
            WITH SYNONYMS = ('営業路線', '路線延長')
            COMMENT = '営業路線の延長（km）',
        T11052_TRAM_OPERATION_STATS_MONTHLY.ZAIJI_SHARYO AS "在籍車両数【両】"::INT
            WITH SYNONYMS = ('在籍車両数', '保有車両')
            COMMENT = '在籍車両数（両）',
        T11052_TRAM_OPERATION_STATS_MONTHLY.UNTEN_KIRO AS "運転キロ数【千km】"::FLOAT
            WITH SYNONYMS = ('運転キロ数', '走行距離')
            COMMENT = '運転キロ数（千km）',
        T11031_AIRPORT_PASSENGERS_MONTHLY.KUKO_RYOKAKUSU AS "人数【人】"::INT
            WITH SYNONYMS = ('乗降客数', '旅客数', '空港利用者')
            COMMENT = '空港の乗降客数（人）',
        T18172_MUSEUM_VISITORS_MONTHLY.HAKUBUTSUKAN_NYUKAN AS "人数【人】"::INT
            WITH SYNONYMS = ('博物館入館者数', '博物館来館者', '博物館利用者')
            COMMENT = '博物館の入館者数（人）',
        T18201_ZOO_MONTHLY_OVERVIEW.KAIEN_NISSHU AS "開園日数【日】"::INT
            WITH SYNONYMS = ('開園日数')
            COMMENT = '動植物園の開園日数（日）',
        T18201_ZOO_MONTHLY_OVERVIEW.ZOO_NYUEN_SHA AS "入園者総数【人】"::INT
            WITH SYNONYMS = ('動植物園入園者数', '動植物園来園者', 'zoo入園者')
            COMMENT = '動植物園の入園者総数（人）',
        T18201_ZOO_MONTHLY_OVERVIEW.ZOO_ICHINICHI_HEIKIN AS "1日平均入園者【人/日】"::FLOAT
            WITH SYNONYMS = ('1日平均入園者', '日平均来園者')
            COMMENT = '1日平均入園者数（人/日）',
        T15191_FIRE_INCIDENTS_DAMAGE.KASAI_KENSHU AS "件数"::INT
            WITH SYNONYMS = ('火災件数', '火災発生件数', '火事件数')
            COMMENT = '火災件数（件）',
        T15191_FIRE_INCIDENTS_DAMAGE.KASAI_SONHAIGAKU AS "損害額【円】"::INT
            WITH SYNONYMS = ('損害額', '火災損害', '被害額')
            COMMENT = '火災による損害額（円）',
        T15120_TRAFFIC_ACCIDENTS_BY_STATION.KOTSU_JIKO AS "件数【件】・人数【人】"::INT
            WITH SYNONYMS = ('交通事故件数', '事故件数', '死傷者数')
            COMMENT = '交通事故の件数または死傷者数',
        T13180_WASTE_PROCESSING_MONTHLY.GOMI_SURYO AS "数量【t】"::FLOAT
            WITH SYNONYMS = ('ごみ量', '廃棄物量', 'ごみ収集量', 'ごみ処理量')
            COMMENT = 'ごみの量（t）',
        T08080_WATER_SUPPLY_BY_PURPOSE.SUIDO_KENSHU AS "延戸(件)数【件】"::INT
            WITH SYNONYMS = ('件数', '戸数', '世帯数')
            COMMENT = '水道使用の件数（戸）',
        T08080_WATER_SUPPLY_BY_PURPOSE.SUIDO_SURYO AS "水量【m3】"::INT
            WITH SYNONYMS = ('水量', '使用水量', '給水量')
            COMMENT = '使用水量（m3）',
        T09011_HOUSEHOLD_MONTHLY_EXPENDITURE.KAKEI_SHICHU AS "支出【円】"::INT
            WITH SYNONYMS = ('支出', '家計支出', '消費支出')
            COMMENT = '家計支出額（円）',
        T12055_JOB_VACANCY_RATE_MONTHLY.KYUJIN_BAIRITSU AS "比率"::FLOAT
            WITH SYNONYMS = ('有効求人倍率', '求人倍率', '就職率', '充足率')
            COMMENT = '有効求人倍率または就職率・充足率の比率'
    )

    -- ─── DIMENSIONS ─────────────────────────────────────────
    -- カテゴリ型の列を「次元」として定義する
    -- 書式: テーブル名.次元名 AS 物理列名_または_式
    --   WITH SYNONYMS = ('別名1', ...): 自然言語での別名（複数可）
    --   COMMENT                      : この次元の意味の説明
    DIMENSIONS (
        T02031_POPULATION_MONTHLY.NIANCI AS "年次"
            WITH SYNONYMS = ('年', '年次', '西暦', '年度')
            COMMENT = '統計の年次（例）2023',
        T02031_POPULATION_MONTHLY.YUECI AS "月次"
            WITH SYNONYMS = ('月', '月次', '月別')
            COMMENT = '統計の月次（例）2023-04',
        T02031_POPULATION_MONTHLY.XINGBIE AS "性別"
            WITH SYNONYMS = ('性別', '男女')
            COMMENT = '性別区分。値 総数・男・女',
        T02040_BIRTHS_DEATHS_MONTHLY.NIANCI AS "年次"
            WITH SYNONYMS = ('年', '年次')
            COMMENT = '統計の年次',
        T02040_BIRTHS_DEATHS_MONTHLY.YUECI AS "月次"
            WITH SYNONYMS = ('月', '月次')
            COMMENT = '統計の月次',
        T02040_BIRTHS_DEATHS_MONTHLY.ZHONGBIE AS "種別"
            WITH SYNONYMS = ('種別', '区分')
            COMMENT = '統計の種別。値 出生・死亡',
        T02040_BIRTHS_DEATHS_MONTHLY.XINGBIE AS "性別"
            WITH SYNONYMS = ('性別')
            COMMENT = '性別区分。値 総数・男・女',
        T02050_MIGRATION_MARRIAGE_MONTHLY.NIANCI AS "年次"
            WITH SYNONYMS = ('年', '年次')
            COMMENT = '統計の年次',
        T02050_MIGRATION_MARRIAGE_MONTHLY.YUECI AS "月次"
            WITH SYNONYMS = ('月', '月次')
            COMMENT = '統計の月次',
        T02050_MIGRATION_MARRIAGE_MONTHLY.ZHONGBIE AS "種別"
            WITH SYNONYMS = ('種別', '区分')
            COMMENT = '種別。値 転入・転出・婚姻・離婚',
        T02050_MIGRATION_MARRIAGE_MONTHLY.XINGBIE AS "性別"
            WITH SYNONYMS = ('性別')
            COMMENT = '性別区分',
        T11051_TRAM_RIDERSHIP_REVENUE_MONTHLY.NIANDU AS "年度"
            WITH SYNONYMS = ('年度', '年', '会計年度')
            COMMENT = '統計の年度（例）2023',
        T11051_TRAM_RIDERSHIP_REVENUE_MONTHLY.YUECI AS "月次"
            WITH SYNONYMS = ('月', '月次')
            COMMENT = '統計の月次',
        T11051_TRAM_RIDERSHIP_REVENUE_MONTHLY.ZONGSHU_DINGQI_DINGQIWAI AS "総数/定期/定期外"
            WITH SYNONYMS = ('定期区分', '乗車種別', '総数定期定期外')
            COMMENT = '乗車種別。値 総数・定期・定期外',
        T11052_TRAM_OPERATION_STATS_MONTHLY.NIANDU AS "年度"
            WITH SYNONYMS = ('年度')
            COMMENT = '運行データの年度',
        T11052_TRAM_OPERATION_STATS_MONTHLY.YUECI AS "月次"
            WITH SYNONYMS = ('月', '月次')
            COMMENT = '統計の月次',
        T11031_AIRPORT_PASSENGERS_MONTHLY.NIANDU AS "年度"
            WITH SYNONYMS = ('年度', '年')
            COMMENT = '統計の年度',
        T11031_AIRPORT_PASSENGERS_MONTHLY.YUECI AS "月次"
            WITH SYNONYMS = ('月', '月次')
            COMMENT = '統計の月次',
        T11031_AIRPORT_PASSENGERS_MONTHLY.CHENGKE_JIANGKE AS "乗客/降客"
            WITH SYNONYMS = ('乗降区分', '乗客降客')
            COMMENT = '乗客（搭乗）または降客（到着）の区分',
        T18172_MUSEUM_VISITORS_MONTHLY.NIANDU AS "年度"
            WITH SYNONYMS = ('年度', '年')
            COMMENT = '統計の年度',
        T18172_MUSEUM_VISITORS_MONTHLY.YUECI AS "月次"
            WITH SYNONYMS = ('月', '月次')
            COMMENT = '統計の月次',
        T18172_MUSEUM_VISITORS_MONTHLY.FENLEI AS "分類"
            WITH SYNONYMS = ('分類', '展示区分')
            COMMENT = '博物館の区分・展示分類',
        T18172_MUSEUM_VISITORS_MONTHLY.DAREN_XIAOZHONGXUESHENG AS "大人/小中学生"
            WITH SYNONYMS = ('入館者区分', '大人小中学生')
            COMMENT = '入館者の区分。値 大人・小中学生',
        T18201_ZOO_MONTHLY_OVERVIEW.NIANDU AS "年度"
            WITH SYNONYMS = ('年度', '年')
            COMMENT = '統計の年度',
        T18201_ZOO_MONTHLY_OVERVIEW.YUECI AS "月次"
            WITH SYNONYMS = ('月', '月次')
            COMMENT = '統計の月次',
        T15191_FIRE_INCIDENTS_DAMAGE.NIANCI AS "年次"
            WITH SYNONYMS = ('年次', '年')
            COMMENT = '統計の年次',
        T15191_FIRE_INCIDENTS_DAMAGE.YUECI AS "月次"
            WITH SYNONYMS = ('月', '月次')
            COMMENT = '統計の月次',
        T15191_FIRE_INCIDENTS_DAMAGE.ZHONGBIE AS "種別"
            WITH SYNONYMS = ('種別', '火災種別')
            COMMENT = '火災の種別。値 建物・林野・車両・その他・計',
        T15120_TRAFFIC_ACCIDENTS_BY_STATION.NIANCI AS "年次"
            WITH SYNONYMS = ('年次', '年')
            COMMENT = '統計の年次',
        T15120_TRAFFIC_ACCIDENTS_BY_STATION.YUECI AS "月次"
            WITH SYNONYMS = ('月', '月次')
            COMMENT = '統計の月次',
        T15120_TRAFFIC_ACCIDENTS_BY_STATION.GUANXIA AS "管轄"
            WITH SYNONYMS = ('管轄', '警察署', '管轄警察署')
            COMMENT = '警察署の管轄区域名',
        T15120_TRAFFIC_ACCIDENTS_BY_STATION.JIANSHU_SIZHE_SHANGZHE AS "件数/死者/傷者"
            WITH SYNONYMS = ('統計区分', '件数死者傷者区分')
            COMMENT = '統計の種別。値 件数・死者数・傷者数',
        T13180_WASTE_PROCESSING_MONTHLY.NIANDU AS "年度"
            WITH SYNONYMS = ('年度', '年')
            COMMENT = '統計の年度',
        T13180_WASTE_PROCESSING_MONTHLY.YUECI AS "月次"
            WITH SYNONYMS = ('月', '月次')
            COMMENT = '統計の月次',
        T13180_WASTE_PROCESSING_MONTHLY.SHOUJI_CHULI AS "収集および搬入量/処理量"
            WITH SYNONYMS = ('処理区分', '収集搬入処理区分')
            COMMENT = '収集および搬入量または処理量の区分',
        T13180_WASTE_PROCESSING_MONTHLY.ZHONGBIE AS "種別"
            WITH SYNONYMS = ('種別', 'ごみ種別')
            COMMENT = 'ごみの種別（燃やすごみ・粗大ごみ等）',
        T08080_WATER_SUPPLY_BY_PURPOSE.NIANDU AS "年度"
            WITH SYNONYMS = ('年度', '年')
            COMMENT = '統計の年度',
        T08080_WATER_SUPPLY_BY_PURPOSE.YONGTU AS "用途"
            WITH SYNONYMS = ('用途', '水道用途', '使用用途')
            COMMENT = '水道の使用用途（家事用・営業用・工場用等）',
        T09011_HOUSEHOLD_MONTHLY_EXPENDITURE.NIANCI AS "年次"
            WITH SYNONYMS = ('年次', '年')
            COMMENT = '統計の年次',
        T09011_HOUSEHOLD_MONTHLY_EXPENDITURE.YUECI AS "月次"
            WITH SYNONYMS = ('月', '月次')
            COMMENT = '統計の月次',
        T09011_HOUSEHOLD_MONTHLY_EXPENDITURE.DAXIANGMU AS "大項目"
            WITH SYNONYMS = ('大項目', '支出大分類', '費目大項目')
            COMMENT = '家計支出の大分類（食料・住居・光熱水道等）',
        T09011_HOUSEHOLD_MONTHLY_EXPENDITURE.ZHONGXIANGMU AS "中項目"
            WITH SYNONYMS = ('中項目', '支出中分類', '費目中項目')
            COMMENT = '家計支出の中分類',
        T12055_JOB_VACANCY_RATE_MONTHLY.NIANDU AS "年度"
            WITH SYNONYMS = ('年度', '年')
            COMMENT = '統計の年度',
        T12055_JOB_VACANCY_RATE_MONTHLY.NIANYUE AS "年月"
            WITH SYNONYMS = ('年月', '月')
            COMMENT = '統計の年月（例）2023-04',
        T12055_JOB_VACANCY_RATE_MONTHLY.ZHONGBIE AS "種別"
            WITH SYNONYMS = ('種別', '指標区分')
            COMMENT = '統計指標の種別（有効求人倍率・就職率・充足率等）'
    )

    -- ─── METRICS ────────────────────────────────────────────
    -- 集計式を「メトリクス（計算済み指標）」として定義する
    -- FACTS との違い: SUM(...) 等の集計関数を含む計算式そのもの
    -- 書式: テーブル名.メトリクス名 AS 集計式
    METRICS (
        T11052_TRAM_OPERATION_STATS_MONTHLY.TRAM_TOTAL_DISTANCE_1000KM AS SUM("運転キロ数【千km】"::FLOAT)
            WITH SYNONYMS = ('市電運転キロ', '走行距離')
            COMMENT = '市電月次運転キロ数合計（千km）',
        T18201_ZOO_MONTHLY_OVERVIEW.ZOO_VISITORS_TOTAL AS SUM("入園者総数【人】"::INT)
            WITH SYNONYMS = ('動植物園入園者', '動物園来場者', '動植物園利用者')
            COMMENT = '動植物園の月次入園者総数',
        T18201_ZOO_MONTHLY_OVERVIEW.ZOO_OPEN_DAYS AS SUM("開園日数【日】"::INT)
            WITH SYNONYMS = ('開園日数')
            COMMENT = '動植物園の月次開園日数',
        T15191_FIRE_INCIDENTS_DAMAGE.FIRE_INCIDENTS_TOTAL AS SUM("件数"::INT)
            WITH SYNONYMS = ('火災件数', '火事件数', '火災発生件数')
            COMMENT = '火災件数合計（全種別）',
        T15191_FIRE_INCIDENTS_DAMAGE.FIRE_DAMAGE_YEN AS SUM("損害額【円】"::INT)
            WITH SYNONYMS = ('火災損害額', '火災被害額', '損害額')
            COMMENT = '火災損害額合計（円）',
        T08080_WATER_SUPPLY_BY_PURPOSE.TOTAL_WATER_VOLUME_M3 AS SUM("水量【m3】"::INT)
            WITH SYNONYMS = ('水量', '給水量', '水道使用量', '有収水量')
            COMMENT = '上水道有収水量合計（m3）'
    )
    COMMENT = '熊本市の各種統計データを自然言語で問い合わせるためのセマンティックビュー。 人口動態・交通（市電・空港）・防災（火災・交通事故）・文化施設（博物館・動植物園）・ 環境（ごみ処理・水道）・経済（家計支出・求人）など、多岐にわたる月次統計データを 横断的に分析できる。データソース: 熊本市オープンデータカタログ（BODIK ODCS）。'

    -- ─── AI_SQL_GENERATION ──────────────────────────────────
    -- Cortex Analyst へのシステムインストラクション
    -- データ特性・フィルタ条件・結合の注意事項を記述する
    AI_SQL_GENERATION '【データの特性と注意事項】 1. すべての数値列は VARCHAR 型で格納されているため、集計時には ::INT または ::FLOAT でキャストする。 2. 年次列（年次・年度）は文字列であるため、並び替えは ORDER BY ... DESC で年が新しい順になる。 3. 人口データ（T02031_POPULATION_MONTHLY）の合計人口は 性別=''総数'' でフィルターして取得する。 4. 市電データ（T11051_TRAM_RIDERSHIP_REVENUE_MONTHLY）の合計は 総数/定期/定期外=''総数'' でフィルター。    定期・定期外の内訳を見る場合はそのままSUMしない（二重カウントになる）。 5. 火災データ（T15191_FIRE_INCIDENTS_DAMAGE）の合計件数は 種別=''計'' でフィルター。 6. 交通事故データ（T15120_TRAFFIC_ACCIDENTS_BY_STATION）は 件数/死者/傷者 列で件数・死者数・傷者数を区別。 7. 空港データ（T11031_AIRPORT_PASSENGERS_MONTHLY）は 乗客/降客 列で搭乗・到着を区別。    全旅客数は両方をSUMするか乗客のみでフィルターする。 8. 複数テーブルを跨ぐ質問（例 人口と市電利用者の相関）は、    年次/年度・月次で LEFT JOIN して集計する。時系列の結合キーは    T02031の「年次」と T11051の「年度」が対応する場合が多い。 9. ごみ処理データ（T13180_WASTE_PROCESSING_MONTHLY）の収集量は    収集および搬入量/処理量=''収集'' でフィルター。 10. 家計支出データ（T09011_HOUSEHOLD_MONTHLY_EXPENDITURE）は大項目別に     SUM することで費目ごとの支出額を把握できる。'

    -- ─── AI_VERIFIED_QUERIES ────────────────────────────────
    -- 正解 SQL のサンプル（VQR: Verified Query Results）
    -- 質問と正しい SQL のペアを登録することで回答精度が向上する
    AI_VERIFIED_QUERIES (
        "月次推計人口の推移" AS (
            QUESTION '熊本市の月次推計人口の直近の推移を教えて'
            ONBOARDING_QUESTION false
            SQL 'SELECT "年次", "月次", "人数【人】"::INT AS 推計人口
FROM KUMAMOTO_OPENDATA.PUBLIC.T02031_POPULATION_MONTHLY
WHERE "性別" = ''総数''
ORDER BY "年次" DESC, "月次" DESC
LIMIT 24'
        ),
        "市電年度別乗車人数と収入" AS (
            QUESTION '熊本市電の年度別乗車人数と乗車料収入はどのくらいか'
            ONBOARDING_QUESTION false
            SQL 'SELECT
    "年度",
    SUM("乗車人数【人】"::INT) AS 年間乗車人数,
    SUM("乗車料収入【円】"::INT) AS 年間乗車料収入
FROM KUMAMOTO_OPENDATA.PUBLIC.T11051_TRAM_RIDERSHIP_REVENUE_MONTHLY
WHERE "総数/定期/定期外" = ''総数''
GROUP BY "年度"
ORDER BY "年度" DESC'
        ),
        "市電月次乗車人数推移" AS (
            QUESTION '熊本市電の直近の月次乗車人数の推移を教えて'
            ONBOARDING_QUESTION false
            SQL 'SELECT "年度", "月次", "乗車人数【人】"::INT AS 乗車人数
FROM KUMAMOTO_OPENDATA.PUBLIC.T11051_TRAM_RIDERSHIP_REVENUE_MONTHLY
WHERE "総数/定期/定期外" = ''総数''
ORDER BY "年度" DESC, "月次" DESC
LIMIT 24'
        ),
        "火災件数年次推移" AS (
            QUESTION '熊本市の火災件数の年次推移を教えて'
            ONBOARDING_QUESTION false
            SQL 'SELECT "年次", SUM("件数"::INT) AS 火災件数, SUM("損害額【円】"::INT) AS 総損害額
FROM KUMAMOTO_OPENDATA.PUBLIC.T15191_FIRE_INCIDENTS_DAMAGE

GROUP BY "年次"
ORDER BY "年次" DESC'
        ),
        "博物館動植物園月次入館者数" AS (
            QUESTION '熊本博物館と動植物園の月次入館者数を見せて'
            ONBOARDING_QUESTION false
            SQL 'SELECT
    m."年度",
    m."月次",
    SUM(m."人数【人】"::INT) AS 博物館入館者数,
    MAX(z."入園者総数【人】"::INT) AS 動植物園入園者数
FROM KUMAMOTO_OPENDATA.PUBLIC.T18172_MUSEUM_VISITORS_MONTHLY m
LEFT JOIN KUMAMOTO_OPENDATA.PUBLIC.T18201_ZOO_MONTHLY_OVERVIEW z
    ON m."年度" = z."年度" AND m."月次" = z."月次"
GROUP BY m."年度", m."月次"
ORDER BY m."年度" DESC, m."月次" DESC
LIMIT 24'
        ),
        "月次ごみ収集量推移" AS (
            QUESTION '熊本市の月次ごみ収集量の推移を教えて'
            ONBOARDING_QUESTION false
            SQL 'SELECT "年度", "月次", SUM("数量【t】"::FLOAT) AS ごみ収集量_t
FROM KUMAMOTO_OPENDATA.PUBLIC.T13180_WASTE_PROCESSING_MONTHLY
WHERE "収集および搬入量/処理量" = ''収集および搬入量''
GROUP BY "年度", "月次"
ORDER BY "年度" DESC, "月次" DESC
LIMIT 24'
        ),
        "有効求人倍率推移" AS (
            QUESTION '熊本市の有効求人倍率の直近の推移を教えて'
            ONBOARDING_QUESTION false
            SQL 'SELECT "年度", "年月", "比率"::FLOAT AS 有効求人倍率
FROM KUMAMOTO_OPENDATA.PUBLIC.T12055_JOB_VACANCY_RATE_MONTHLY
WHERE "種別" = ''有効求人倍率''
ORDER BY "年度" DESC, "年月" DESC
LIMIT 24'
        ),
        "家計支出費目別年次" AS (
            QUESTION '熊本市の費目別家計支出の年次推移を教えて'
            ONBOARDING_QUESTION false
            SQL 'SELECT "年次", "大項目", SUM("支出【円】"::INT) AS 年間支出額
FROM KUMAMOTO_OPENDATA.PUBLIC.T09011_HOUSEHOLD_MONTHLY_EXPENDITURE
GROUP BY "年次", "大項目"
ORDER BY "年次" DESC, 年間支出額 DESC'
        ),
        "人口と出生死亡の月次推移" AS (
            QUESTION '熊本市の人口・出生数・死亡数の月次推移を一覧で見せて'
            ONBOARDING_QUESTION false
            SQL 'SELECT
    p."年次",
    p."月次",
    MAX(CASE WHEN p."性別" = ''総数'' THEN p."人数【人】"::INT END) AS 推計人口,
    SUM(CASE WHEN bd."種別" = ''出生'' AND bd."性別" = ''総数''
             THEN bd."人数【人】"::INT ELSE 0 END) AS 出生数,
    SUM(CASE WHEN bd."種別" = ''死亡'' AND bd."性別" = ''総数''
             THEN bd."人数【人】"::INT ELSE 0 END) AS 死亡数,
    MAX(CASE WHEN p."性別" = ''総数'' THEN p."人数【人】"::INT END)
        - LAG(MAX(CASE WHEN p."性別" = ''総数'' THEN p."人数【人】"::INT END))
            OVER (ORDER BY p."年次", p."月次") AS 人口増減
FROM KUMAMOTO_OPENDATA.PUBLIC.T02031_POPULATION_MONTHLY p
LEFT JOIN KUMAMOTO_OPENDATA.PUBLIC.T02040_BIRTHS_DEATHS_MONTHLY bd
    ON p."年次" = bd."年次" AND p."月次" = bd."月次"
GROUP BY p."年次", p."月次"
ORDER BY p."年次" DESC, p."月次" DESC
LIMIT 24'
        ),
        "市電と空港の月次輸送量比較" AS (
            QUESTION '熊本市電の乗車人数と熊本空港の乗降客数を月次で比較して'
            ONBOARDING_QUESTION false
            SQL 'SELECT
    t."年度",
    t."月次",
    SUM(CASE WHEN t."総数/定期/定期外" = ''総数''
             THEN t."乗車人数【人】"::INT ELSE 0 END) AS 市電乗車人数,
    SUM(a."人数【人】"::INT) AS 空港乗降客数合計
FROM KUMAMOTO_OPENDATA.PUBLIC.T11051_TRAM_RIDERSHIP_REVENUE_MONTHLY t
LEFT JOIN KUMAMOTO_OPENDATA.PUBLIC.T11031_AIRPORT_PASSENGERS_MONTHLY a
    ON t."年度" = a."年度" AND t."月次" = a."月次"
GROUP BY t."年度", t."月次"
ORDER BY t."年度" DESC, t."月次" DESC
LIMIT 24'
        ),
        "火災件数と交通事故件数の年次比較" AS (
            QUESTION '熊本市の火災件数と交通事故件数を年次で比較して'
            ONBOARDING_QUESTION false
            SQL 'SELECT
    f."年次",
    SUM(CASE WHEN f."種別" = ''計'' THEN f."件数"::INT ELSE 0 END) AS 火災件数,
    SUM(CASE WHEN f."種別" = ''計'' THEN f."損害額【円】"::INT ELSE 0 END) AS 火災損害額,
    SUM(CASE WHEN t."件数/死者/傷者" = ''件数''
             THEN t."件数【件】・人数【人】"::INT ELSE 0 END) AS 交通事故件数,
    SUM(CASE WHEN t."件数/死者/傷者" = ''死者''
             THEN t."件数【件】・人数【人】"::INT ELSE 0 END) AS 交通事故死者数
FROM KUMAMOTO_OPENDATA.PUBLIC.T15191_FIRE_INCIDENTS_DAMAGE f
LEFT JOIN KUMAMOTO_OPENDATA.PUBLIC.T15120_TRAFFIC_ACCIDENTS_BY_STATION t
    ON f."年次" = t."年次" AND f."月次" = t."月次"
GROUP BY f."年次"
ORDER BY f."年次" DESC'
        ),
        "人口とごみ収集量の年次推移" AS (
            QUESTION '熊本市の人口とごみ収集量の関係を年次で見せて'
            ONBOARDING_QUESTION false
            SQL 'SELECT
    pop."年次",
    SUM(CASE WHEN pop."性別" = ''総数'' THEN pop."人数【人】"::INT ELSE 0 END) / 12 AS 月平均推計人口,
    SUM(CASE WHEN waste."収集および搬入量/処理量" = ''収集および搬入量''
             THEN waste."数量【t】"::FLOAT ELSE 0 END) AS 年間ごみ収集量_t
FROM KUMAMOTO_OPENDATA.PUBLIC.T02031_POPULATION_MONTHLY pop
LEFT JOIN KUMAMOTO_OPENDATA.PUBLIC.T13180_WASTE_PROCESSING_MONTHLY waste
    ON pop."年次" = waste."年度" AND pop."月次" = waste."月次"
GROUP BY pop."年次"
ORDER BY pop."年次" DESC'
        ),
        "市電定期定期外割合の年度推移" AS (
            QUESTION '熊本市電の定期利用者と定期外利用者の割合はどう変化しているか'
            ONBOARDING_QUESTION false
            SQL 'SELECT
    "年度",
    SUM(CASE WHEN "総数/定期/定期外" = ''定期'' THEN "乗車人数【人】"::INT ELSE 0 END) AS 定期乗車人数,
    SUM(CASE WHEN "総数/定期/定期外" = ''定期外'' THEN "乗車人数【人】"::INT ELSE 0 END) AS 定期外乗車人数,
    SUM(CASE WHEN "総数/定期/定期外" = ''総数'' THEN "乗車人数【人】"::INT ELSE 0 END) AS 総乗車人数,
    ROUND(100.0 * SUM(CASE WHEN "総数/定期/定期外" = ''定期'' THEN "乗車人数【人】"::INT ELSE 0 END)
        / NULLIF(SUM(CASE WHEN "総数/定期/定期外" = ''総数'' THEN "乗車人数【人】"::INT ELSE 0 END), 0), 1) AS 定期利用率_pct
FROM KUMAMOTO_OPENDATA.PUBLIC.T11051_TRAM_RIDERSHIP_REVENUE_MONTHLY
GROUP BY "年度"
ORDER BY "年度" DESC'
        ),
        "博物館と動植物園の年度別入館者比較" AS (
            QUESTION '熊本博物館と動植物園の年間入館者数を年度別に比較して'
            ONBOARDING_QUESTION false
            SQL 'SELECT
    m."年度",
    SUM(m."人数【人】"::INT) AS 博物館年間入館者数,
    SUM(z."入園者総数【人】"::INT) AS 動植物園年間入園者数
FROM KUMAMOTO_OPENDATA.PUBLIC.T18172_MUSEUM_VISITORS_MONTHLY m
LEFT JOIN KUMAMOTO_OPENDATA.PUBLIC.T18201_ZOO_MONTHLY_OVERVIEW z
    ON m."年度" = z."年度" AND m."月次" = z."月次"
GROUP BY m."年度"
ORDER BY m."年度" DESC'
        )
    )
;

-- ============================================================
-- STEP 3-2: 作成確認
-- ============================================================
SHOW SEMANTIC VIEWS IN SCHEMA KUMAMOTO_OPENDATA.PUBLIC;

-- DDL の確認
SELECT GET_DDL('SEMANTIC_VIEW', 'KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_CITY_STATISTICS');

-- ============================================================
-- STEP 3-3: アクセス権限の付与
-- ============================================================
-- -- Snowflake Intelligence が参照できるよう SELECT 権限を付与します。
-- GRANT SELECT ON ALL TABLES IN SCHEMA KUMAMOTO_OPENDATA.PUBLIC TO ROLE PUBLIC;
-- GRANT SELECT ON SEMANTIC VIEW KUMAMOTO_OPENDATA.PUBLIC.KUMAMOTO_CITY_STATISTICS TO ROLE PUBLIC;

-- ============================================================
-- STEP 3 完了
-- ============================================================
-- ✅ Semantic View KUMAMOTO_CITY_STATISTICS が作成されました
-- 次は STEP4_cortex_agent.sql を実行してください。
-- ============================================================
