-- ============================================================
-- 随行条件 · 旅游攻略 Agent
-- 关系数据库建表脚本（MySQL 8.0+ / InnoDB / utf8mb4）
-- 版本：V1.0    日期：2026-11-10
-- 说明：
--   1. 本脚本用于开发与演示环境初始化，包含 15 张表与 4 个视图。
--   2. 生产环境请删除 DROP 语句，并通过迁移工具执行。
--   3. 所有表均使用 utf8mb4_0900_ai_ci，支持中文与 emoji。
-- ============================================================

CREATE DATABASE IF NOT EXISTS travel_conditions
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_0900_ai_ci;

USE travel_conditions;

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

DROP VIEW  IF EXISTS v_fallback_daily;
DROP VIEW  IF EXISTS v_query_trace;
DROP VIEW  IF EXISTS v_chunk_detail;
DROP VIEW  IF EXISTS v_guide_admin;

DROP TABLE IF EXISTS fallback_log;
DROP TABLE IF EXISTS citation;
DROP TABLE IF EXISTS agent_response;
DROP TABLE IF EXISTS request_context;
DROP TABLE IF EXISTS agent_request;
DROP TABLE IF EXISTS retrieval_hit;
DROP TABLE IF EXISTS query_tag;
DROP TABLE IF EXISTS search_query;
DROP TABLE IF EXISTS chunk_facility;
DROP TABLE IF EXISTS chunk_tag;
DROP TABLE IF EXISTS tag;
DROP TABLE IF EXISTS guide_chunk;
DROP TABLE IF EXISTS guide_text;
DROP TABLE IF EXISTS sys_user;
DROP TABLE IF EXISTS city;

SET FOREIGN_KEY_CHECKS = 1;

-- ------------------------------------------------------------
-- 1. 城市维表：把城市从字符串提升为受控字典
-- ------------------------------------------------------------
CREATE TABLE city (
  city_code        CHAR(6)      NOT NULL COMMENT '行政区划代码（GB/T 2260）',
  city_name        VARCHAR(50)  NOT NULL COMMENT '城市名称',
  province         VARCHAR(50)  NOT NULL COMMENT '所属省份',
  coverage_status  ENUM('COVERED','PLANNED','DISABLED') NOT NULL DEFAULT 'PLANNED'
                                COMMENT '攻略覆盖状态：已覆盖/规划中/停用',
  sort_no          SMALLINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '展示排序',
  created_at       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (city_code),
  UNIQUE KEY uk_city_name (city_name),
  KEY idx_city_coverage (coverage_status, sort_no)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='城市维表';

-- ------------------------------------------------------------
-- 2. 后台账号表：只服务于运营后台，不做 C 端用户体系
-- ------------------------------------------------------------
CREATE TABLE sys_user (
  user_id        BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  username       VARCHAR(50)  NOT NULL COMMENT '登录名',
  password_hash  VARCHAR(100) NOT NULL COMMENT 'bcrypt/argon2 哈希，不存明文',
  display_name   VARCHAR(50)  NOT NULL COMMENT '显示名',
  role           ENUM('ADMIN','OPERATOR') NOT NULL DEFAULT 'OPERATOR'
                                COMMENT 'ADMIN=管理员，OPERATOR=运营',
  status         ENUM('ACTIVE','DISABLED') NOT NULL DEFAULT 'ACTIVE',
  last_login_at  DATETIME     NULL COMMENT '最近登录时间',
  created_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id),
  UNIQUE KEY uk_sys_user_username (username)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='后台账号表';

-- ------------------------------------------------------------
-- 3. 攻略原文表：导入的长文本与预处理状态
-- ------------------------------------------------------------
CREATE TABLE guide_text (
  text_id        VARCHAR(40)  NOT NULL COMMENT '攻略ID，如 guide_202611100001',
  title          VARCHAR(200) NOT NULL COMMENT '攻略标题',
  city_code      CHAR(6)      NOT NULL COMMENT '所属城市',
  source         VARCHAR(200) NOT NULL COMMENT '来源说明（团队整理/公开链接等）',
  source_url     VARCHAR(500) NULL COMMENT '来源链接，可为空',
  raw_content    MEDIUMTEXT   NOT NULL COMMENT '攻略原文',
  content_hash   CHAR(64)     NOT NULL COMMENT '原文规范化后的 SHA-256，用于去重',
  char_count     INT UNSIGNED NOT NULL COMMENT '原文字符数',
  status         ENUM('PENDING','PROCESSING','SUCCESS','FAILED','ARCHIVED')
                                NOT NULL DEFAULT 'PENDING' COMMENT '预处理状态',
  chunk_count    INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '已生成片段数（缓存计数）',
  error_message  VARCHAR(500) NULL COMMENT '失败原因',
  imported_by    BIGINT UNSIGNED NULL COMMENT '导入人（后台账号）',
  import_time    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '导入时间',
  processed_at   DATETIME     NULL COMMENT '预处理完成时间',
  created_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (text_id),
  UNIQUE KEY uk_guide_text_hash (content_hash),
  KEY idx_guide_text_city_status (city_code, status, import_time),
  KEY idx_guide_text_importer (imported_by),
  CONSTRAINT fk_guide_text_city FOREIGN KEY (city_code)
    REFERENCES city (city_code) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_guide_text_user FOREIGN KEY (imported_by)
    REFERENCES sys_user (user_id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT ck_guide_text_char_count CHECK (char_count BETWEEN 50 AND 20000)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='攻略原文表';

-- ------------------------------------------------------------
-- 4. 结构化片段表：检索与引用的最小单位
-- ------------------------------------------------------------
CREATE TABLE guide_chunk (
  chunk_id            VARCHAR(48)  NOT NULL COMMENT '片段ID，如 chunk_202611100001_1',
  text_id             VARCHAR(40)  NOT NULL COMMENT '所属攻略',
  seq_no              INT UNSIGNED NOT NULL COMMENT '文内顺序，从 1 开始',
  content             TEXT         NOT NULL COMMENT '片段正文（建议 <= 800 字）',
  char_offset         INT UNSIGNED NOT NULL COMMENT '原文起始字符偏移',
  char_length         INT UNSIGNED NOT NULL COMMENT '片段字符数',
  location            VARCHAR(100) NOT NULL DEFAULT '未知' COMMENT '地点/场馆名',
  walking_level       ENUM('LOW','MEDIUM','HIGH','UNKNOWN')
                                   NOT NULL DEFAULT 'UNKNOWN' COMMENT '步行强度',
  rainy_backup        VARCHAR(500) NOT NULL DEFAULT '未覆盖' COMMENT '雨天备选说明',
  duration_suggestion VARCHAR(100) NULL COMMENT '建议游玩时长',
  transport           VARCHAR(100) NULL COMMENT '交通方式',
  tips                VARCHAR(500) NULL COMMENT '注意事项',
  source_ref          VARCHAR(100) NOT NULL COMMENT '原文位置，如 offset:1234',
  confidence          DECIMAL(3,2) NOT NULL DEFAULT 1.00 COMMENT '抽取置信度 0-1',
  review_flag         TINYINT(1)   NOT NULL DEFAULT 0 COMMENT '1=待人工复核',
  created_at          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (chunk_id),
  UNIQUE KEY uk_chunk_text_seq (text_id, seq_no),
  KEY idx_chunk_text (text_id),
  KEY idx_chunk_walking (walking_level),
  FULLTEXT KEY ft_chunk_content (content) WITH PARSER ngram,
  CONSTRAINT fk_chunk_text FOREIGN KEY (text_id)
    REFERENCES guide_text (text_id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT ck_chunk_confidence CHECK (confidence BETWEEN 0 AND 1),
  CONSTRAINT ck_chunk_length CHECK (char_length > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='结构化片段表';

-- ------------------------------------------------------------
-- 5. 标签字典表：人群、设施、天气、场景的统一词表
-- ------------------------------------------------------------
CREATE TABLE tag (
  tag_id      INT UNSIGNED NOT NULL AUTO_INCREMENT,
  tag_code    VARCHAR(30)  NOT NULL COMMENT '稳定编码，如 CROWD_CHILD',
  tag_name    VARCHAR(50)  NOT NULL COMMENT '中文名，如 儿童',
  tag_type    ENUM('CROWD','FACILITY','WEATHER','SCENE') NOT NULL
                           COMMENT '标签类型',
  description VARCHAR(200) NULL COMMENT '业务说明',
  sort_no     SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  enabled     TINYINT(1)   NOT NULL DEFAULT 1,
  created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (tag_id),
  UNIQUE KEY uk_tag_code (tag_code),
  KEY idx_tag_type (tag_type, sort_no)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='标签字典表';

-- ------------------------------------------------------------
-- 6. 片段-标签关联表：适合人群、场景等多值属性
-- ------------------------------------------------------------
CREATE TABLE chunk_tag (
  chunk_id   VARCHAR(48) NOT NULL,
  tag_id     INT UNSIGNED NOT NULL COMMENT '只允许 CROWD/SCENE 类型',
  confidence DECIMAL(3,2) NOT NULL DEFAULT 1.00 COMMENT '标注置信度',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (chunk_id, tag_id),
  KEY idx_chunk_tag_tag (tag_id, chunk_id),
  CONSTRAINT fk_chunk_tag_chunk FOREIGN KEY (chunk_id)
    REFERENCES guide_chunk (chunk_id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_chunk_tag_tag FOREIGN KEY (tag_id)
    REFERENCES tag (tag_id) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT ck_chunk_tag_confidence CHECK (confidence BETWEEN 0 AND 1)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='片段-标签关联表';

-- ------------------------------------------------------------
-- 7. 片段-设施关联表：母婴室、无障碍、亲子餐厅等设施状态
--    使用独立关联表而不是固定列，新增设施无需改表结构。
-- ------------------------------------------------------------
CREATE TABLE chunk_facility (
  chunk_id   VARCHAR(48) NOT NULL,
  tag_id     INT UNSIGNED NOT NULL COMMENT '只允许 FACILITY 类型',
  status     ENUM('YES','NO','UNKNOWN') NOT NULL DEFAULT 'UNKNOWN'
                         COMMENT '设施状态：有/无/未知',
  note       VARCHAR(200) NULL COMMENT '补充说明，如“三楼、需押金”',
  confidence DECIMAL(3,2) NOT NULL DEFAULT 1.00,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (chunk_id, tag_id),
  KEY idx_chunk_facility_tag (tag_id, status),
  CONSTRAINT fk_chunk_facility_chunk FOREIGN KEY (chunk_id)
    REFERENCES guide_chunk (chunk_id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_chunk_facility_tag FOREIGN KEY (tag_id)
    REFERENCES tag (tag_id) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT ck_chunk_facility_confidence CHECK (confidence BETWEEN 0 AND 1)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='片段-设施关联表';

-- ------------------------------------------------------------
-- 8. 查询表：一次条件化检索的输入
-- ------------------------------------------------------------
CREATE TABLE search_query (
  query_id      CHAR(36)     NOT NULL COMMENT '查询ID（UUID）',
  raw_input     VARCHAR(1000) NULL COMMENT '自然语言原始输入',
  city_code     CHAR(6)      NOT NULL COMMENT '目标城市',
  days          TINYINT UNSIGNED NOT NULL DEFAULT 2 COMMENT '行程天数',
  walking_limit ENUM('LOW','MEDIUM','HIGH','ANY') NOT NULL DEFAULT 'ANY'
                             COMMENT '步行强度上限',
  extra_input   VARCHAR(500) NULL COMMENT '补充说明',
  result_count  INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '命中片段数（缓存计数）',
  status        ENUM('CREATED','RETRIEVED','GENERATING','COMPLETED','FAILED','NO_RESULT')
                             NOT NULL DEFAULT 'CREATED' COMMENT '查询状态机',
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (query_id),
  KEY idx_query_city_time (city_code, created_at),
  KEY idx_query_status_time (status, created_at),
  CONSTRAINT fk_query_city FOREIGN KEY (city_code)
    REFERENCES city (city_code) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT ck_query_days CHECK (days BETWEEN 1 AND 7)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='查询表';

-- ------------------------------------------------------------
-- 9. 查询-标签关联表：同行人员、天气、设施需求
-- ------------------------------------------------------------
CREATE TABLE query_tag (
  query_id CHAR(36) NOT NULL,
  tag_id   INT UNSIGNED NOT NULL COMMENT '允许 CROWD/WEATHER/FACILITY/SCENE',
  PRIMARY KEY (query_id, tag_id),
  KEY idx_query_tag_tag (tag_id, query_id),
  CONSTRAINT fk_query_tag_query FOREIGN KEY (query_id)
    REFERENCES search_query (query_id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_query_tag_tag FOREIGN KEY (tag_id)
    REFERENCES tag (tag_id) ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='查询-标签关联表';

-- ------------------------------------------------------------
-- 10. 检索命中表：保存每次查询的 Top-N 片段及排序
-- ------------------------------------------------------------
CREATE TABLE retrieval_hit (
  hit_id     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  query_id   CHAR(36)      NOT NULL,
  chunk_id   VARCHAR(48)   NOT NULL,
  score      DECIMAL(6,2)  NOT NULL DEFAULT 0 COMMENT '相关度得分',
  rank_no    INT UNSIGNED  NOT NULL COMMENT '排名，从 1 开始',
  hit_reason VARCHAR(255)  NULL COMMENT '命中原因快照，便于后台解释',
  created_at DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (hit_id),
  UNIQUE KEY uk_hit_query_rank (query_id, rank_no),
  UNIQUE KEY uk_hit_query_chunk (query_id, chunk_id),
  KEY idx_hit_chunk (chunk_id),
  CONSTRAINT fk_hit_query FOREIGN KEY (query_id)
    REFERENCES search_query (query_id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_hit_chunk FOREIGN KEY (chunk_id)
    REFERENCES guide_chunk (chunk_id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT ck_hit_rank CHECK (rank_no >= 1)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='检索命中表';

-- ------------------------------------------------------------
-- 11. 生成请求表：一次 Agent 调用的 Prompt 与状态
-- ------------------------------------------------------------
CREATE TABLE agent_request (
  request_id  CHAR(36)     NOT NULL COMMENT '请求ID（UUID）',
  query_id    CHAR(36)     NOT NULL COMMENT '所属查询，一对一',
  prompt      MEDIUMTEXT   NOT NULL COMMENT '完整 Prompt（system + user）',
  model       VARCHAR(50)  NOT NULL DEFAULT 'deepseek-chat' COMMENT '模型名',
  stream      TINYINT(1)   NOT NULL DEFAULT 1 COMMENT '是否流式',
  temperature DECIMAL(3,2) NOT NULL DEFAULT 0.70 COMMENT '采样温度',
  status      ENUM('PENDING','STREAMING','SUCCESS','FAILED','CANCELLED')
                           NOT NULL DEFAULT 'PENDING' COMMENT '请求状态',
  retry_count TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '重试次数',
  started_at  DATETIME(3)  NULL COMMENT '开始调用时间',
  finished_at DATETIME(3)  NULL COMMENT '调用结束时间',
  created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (request_id),
  UNIQUE KEY uk_request_query (query_id),
  KEY idx_request_status_time (status, created_at),
  CONSTRAINT fk_request_query FOREIGN KEY (query_id)
    REFERENCES search_query (query_id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT ck_request_temperature CHECK (temperature BETWEEN 0 AND 2)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='生成请求表';

-- ------------------------------------------------------------
-- 12. 请求上下文表：Prompt 中 [片段N] 与 chunk 的映射快照
-- ------------------------------------------------------------
CREATE TABLE request_context (
  request_id CHAR(36)    NOT NULL,
  chunk_id   VARCHAR(48) NOT NULL,
  marker_no  INT UNSIGNED NOT NULL COMMENT 'Prompt 中的片段编号 N',
  rank_no    INT UNSIGNED NOT NULL COMMENT '检索排名',
  PRIMARY KEY (request_id, chunk_id),
  UNIQUE KEY uk_ctx_request_marker (request_id, marker_no),
  KEY idx_ctx_chunk (chunk_id),
  CONSTRAINT fk_ctx_request FOREIGN KEY (request_id)
    REFERENCES agent_request (request_id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_ctx_chunk FOREIGN KEY (chunk_id)
    REFERENCES guide_chunk (chunk_id) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT ck_ctx_marker CHECK (marker_no >= 1)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='请求上下文表';

-- ------------------------------------------------------------
-- 13. 生成响应表：模型完整输出与用量
-- ------------------------------------------------------------
CREATE TABLE agent_response (
  response_id       CHAR(36)     NOT NULL COMMENT '响应ID（UUID）',
  request_id        CHAR(36)     NOT NULL COMMENT '所属请求，一对一',
  content           MEDIUMTEXT   NOT NULL COMMENT '完整生成文本',
  status            ENUM('SUCCESS','PARTIAL','FAILED') NOT NULL DEFAULT 'SUCCESS'
                                 COMMENT '完整/部分/失败',
  finish_reason     VARCHAR(30)  NULL COMMENT 'stop/length/error',
  prompt_tokens     INT UNSIGNED NULL,
  completion_tokens INT UNSIGNED NULL,
  total_tokens      INT UNSIGNED NULL,
  latency_ms        INT UNSIGNED NULL COMMENT '端到端耗时（毫秒）',
  created_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (response_id),
  UNIQUE KEY uk_response_request (request_id),
  CONSTRAINT fk_response_request FOREIGN KEY (request_id)
    REFERENCES agent_request (request_id) ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='生成响应表';

-- ------------------------------------------------------------
-- 14. 引用表：响应中的 [片段N] 到片段的映射
-- ------------------------------------------------------------
CREATE TABLE citation (
  citation_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  response_id CHAR(36)    NOT NULL,
  chunk_id    VARCHAR(48) NOT NULL,
  marker_no   INT UNSIGNED NOT NULL COMMENT '响应中的片段编号 N',
  excerpt     VARCHAR(500) NOT NULL COMMENT '引用时摘录快照',
  source_ref  VARCHAR(100) NOT NULL COMMENT '原文位置快照',
  created_at  DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (citation_id),
  UNIQUE KEY uk_citation_response_marker (response_id, marker_no),
  KEY idx_citation_chunk (chunk_id),
  CONSTRAINT fk_citation_response FOREIGN KEY (response_id)
    REFERENCES agent_response (response_id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_citation_chunk FOREIGN KEY (chunk_id)
    REFERENCES guide_chunk (chunk_id) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT ck_citation_marker CHECK (marker_no >= 1)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='引用表';

-- ------------------------------------------------------------
-- 15. 降级日志表：检索为空、超时、限流、网络错误等
-- ------------------------------------------------------------
CREATE TABLE fallback_log (
  log_id      BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  request_id  CHAR(36)    NULL COMMENT '关联请求，检索为空时可为空',
  query_id    CHAR(36)    NULL COMMENT '关联查询',
  error_type  ENUM('NO_RESULT','TIMEOUT','RATE_LIMIT','NETWORK','HTTP_5XX','PARSE_ERROR','UNKNOWN')
                          NOT NULL COMMENT '降级类型',
  error_code  VARCHAR(50) NULL COMMENT '上游错误码',
  message     VARCHAR(1000) NOT NULL COMMENT '错误说明（不含 Key/隐私）',
  retry_count TINYINT UNSIGNED NOT NULL DEFAULT 0,
  occurred_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (log_id),
  KEY idx_fallback_time (occurred_at),
  KEY idx_fallback_type_time (error_type, occurred_at),
  KEY idx_fallback_request (request_id),
  KEY idx_fallback_query (query_id),
  CONSTRAINT fk_fallback_request FOREIGN KEY (request_id)
    REFERENCES agent_request (request_id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT fk_fallback_query FOREIGN KEY (query_id)
    REFERENCES search_query (query_id) ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='降级日志表';

-- ============================================================
-- 视图
-- ============================================================

-- 后台攻略列表：攻略 + 城市 + 导入人
CREATE VIEW v_guide_admin AS
SELECT g.text_id,
       g.title,
       c.city_name,
       g.source,
       g.import_time,
       g.chunk_count,
       g.status,
       g.error_message,
       u.display_name AS imported_by_name
FROM guide_text g
JOIN city c     ON c.city_code = g.city_code
LEFT JOIN sys_user u ON u.user_id = g.imported_by;

-- 后台片段预览：片段 + 人群/场景标签 + 关键设施状态
CREATE VIEW v_chunk_detail AS
SELECT ch.chunk_id,
       ch.text_id,
       g.title,
       g.source,
       ch.seq_no,
       ch.content,
       ch.location,
       ch.walking_level,
       ch.rainy_backup,
       ch.source_ref,
       ch.review_flag,
       (SELECT GROUP_CONCAT(t.tag_name ORDER BY t.tag_type, t.sort_no SEPARATOR '、')
          FROM chunk_tag ct
          JOIN tag t ON t.tag_id = ct.tag_id
         WHERE ct.chunk_id = ch.chunk_id
           AND t.tag_type IN ('CROWD','SCENE')) AS crowd_scene_tags,
       (SELECT cf.status
          FROM chunk_facility cf
          JOIN tag ft ON ft.tag_id = cf.tag_id
         WHERE cf.chunk_id = ch.chunk_id
           AND ft.tag_code = 'FAC_BABY_ROOM') AS baby_facility,
       (SELECT cf.status
          FROM chunk_facility cf
          JOIN tag ft ON ft.tag_id = cf.tag_id
         WHERE cf.chunk_id = ch.chunk_id
           AND ft.tag_code = 'FAC_ACCESSIBLE') AS accessibility
FROM guide_chunk ch
JOIN guide_text g ON g.text_id = ch.text_id;

-- 调用链路：查询 → 请求 → 响应 → 引用/降级
CREATE VIEW v_query_trace AS
SELECT q.query_id,
       q.city_code,
       c.city_name,
       q.days,
       q.walking_limit,
       q.status AS query_status,
       q.result_count,
       r.request_id,
       r.model,
       r.status AS request_status,
       a.response_id,
       a.status AS response_status,
       a.latency_ms,
       a.total_tokens,
       (SELECT COUNT(*) FROM citation ci WHERE ci.response_id = a.response_id) AS citation_count,
       (SELECT COUNT(*) FROM fallback_log f
         WHERE f.query_id = q.query_id
            OR (r.request_id IS NOT NULL AND f.request_id = r.request_id)) AS fallback_count
FROM search_query q
JOIN city c ON c.city_code = q.city_code
LEFT JOIN agent_request r ON r.query_id = q.query_id
LEFT JOIN agent_response a ON a.request_id = r.request_id;

-- 降级统计：按天、按错误类型
CREATE VIEW v_fallback_daily AS
SELECT DATE(f.occurred_at) AS stat_date,
       f.error_type,
       COUNT(*) AS error_count,
       ROUND(AVG(f.retry_count), 2) AS avg_retry
FROM fallback_log f
GROUP BY DATE(f.occurred_at), f.error_type;
