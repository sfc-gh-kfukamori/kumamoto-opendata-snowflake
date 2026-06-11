USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE DATABASE GIT_INTGRATION_DB;

-- Git連携のため、API統合を作成する
CREATE OR REPLACE API INTEGRATION git_api_integration
  API_PROVIDER = git_https_api
  API_ALLOWED_PREFIXES = ('https://github.com/sfc-gh-kfukamori/')
  ENABLED = TRUE;

-- GIT統合の作成
CREATE OR REPLACE GIT REPOSITORY GIT_INTEGRATION_FOR_HANDSON
  API_INTEGRATION = git_api_integration
  ORIGIN = 'https://github.com/sfc-gh-kfukamori/kumamoto-opendata-snowflake.git';
