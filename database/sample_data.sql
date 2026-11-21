-- ============================================================
-- 随行条件 · 旅游攻略 Agent
-- 演示数据：1 篇杭州攻略、3 个片段、1 次完整生成、1 次未覆盖降级
-- 版本：V1.0    日期：2026-11-10
-- 依赖：先执行 schema.sql 与 seed.sql
-- ============================================================

USE travel_conditions;
SET NAMES utf8mb4;

START TRANSACTION;

-- 攻略原文
INSERT INTO guide_text (text_id, title, city_code, source, source_url, raw_content, content_hash, char_count, status, chunk_count, imported_by, import_time, processed_at) VALUES (
  'guide_202611080001', '杭州两日亲子游攻略（团队整理）', '330100', '团队整理', NULL, '西湖湖滨步道适合全家出游。湖边步道平坦，推婴儿车方便，湖滨三公园至断桥段全程无台阶，沿途设有多处休息椅与直饮水点。建议上午 9 点前到达，避开人流。

浙江省博物馆孤山馆区免费预约。一层有无障碍坡道与轮椅租借，馆内走廊平坦，电梯直达各层。母婴室位于一楼服务台旁。雨天可作为室内备选。

河坊街与南宋御街适合傍晚散步。街区以石板路为主，部分路段有台阶，推婴儿车需绕行。街边小吃较多，建议选择有儿童座椅的餐厅。', 'a9c5845c73873273ea90b6bab0743e647cd8b7513a19a21685d5ef26542c91d3', 203, 'SUCCESS', 3, 1, '2026-11-08 10:24:00', '2026-11-08 10:24:03');

-- 结构化片段
INSERT INTO guide_chunk (chunk_id, text_id, seq_no, content, char_offset, char_length, location, walking_level, rainy_backup, duration_suggestion, transport, tips, source_ref, confidence, review_flag) VALUES
  ('chunk_202611080001_1', 'guide_202611080001', 1, '西湖湖滨步道适合全家出游。湖边步道平坦，推婴儿车方便，湖滨三公园至断桥段全程无台阶，沿途设有多处休息椅与直饮水点。建议上午 9 点前到达，避开人流。', 0, 74, '西湖湖滨步道', 'LOW', '西湖湖滨步道全线无台阶，雨天可改走湖滨银泰室内段', '1.5 小时', '步行', '上午 9 点前到达，避开人流', 'offset:0', 0.96, 0),
  ('chunk_202611080001_2', 'guide_202611080001', 2, '浙江省博物馆孤山馆区免费预约。一层有无障碍坡道与轮椅租借，馆内走廊平坦，电梯直达各层。母婴室位于一楼服务台旁。雨天可作为室内备选。', 76, 65, '浙江省博物馆孤山馆区', 'LOW', '浙江省博物馆孤山馆区为室内场馆，可作为雨天备选', '2 小时', '步行/公交', '免费预约，周一闭馆（以官方公告为准）', 'offset:76', 0.95, 0),
  ('chunk_202611080001_3', 'guide_202611080001', 3, '河坊街与南宋御街适合傍晚散步。街区以石板路为主，部分路段有台阶，推婴儿车需绕行。街边小吃较多，建议选择有儿童座椅的餐厅。', 143, 60, '河坊街与南宋御街', 'MEDIUM', '现有攻略未覆盖该场景的雨天备选', '1.5 小时', '步行', '石板路，部分路段有台阶，推车需绕行', 'offset:143', 0.82, 0);

-- 片段-人群/场景标签
INSERT INTO chunk_tag (chunk_id, tag_id, confidence) VALUES
  ('chunk_202611080001_1', 1, 0.95),
  ('chunk_202611080001_1', 2, 0.95),
  ('chunk_202611080001_1', 3, 0.95),
  ('chunk_202611080001_1', 12, 0.95),
  ('chunk_202611080001_1', 13, 0.95),
  ('chunk_202611080001_2', 1, 0.95),
  ('chunk_202611080001_2', 2, 0.95),
  ('chunk_202611080001_2', 11, 0.95),
  ('chunk_202611080001_2', 13, 0.95),
  ('chunk_202611080001_3', 3, 0.95),
  ('chunk_202611080001_3', 12, 0.95);

-- 片段-设施状态
INSERT INTO chunk_facility (chunk_id, tag_id, status, note, confidence) VALUES
  ('chunk_202611080001_1', 5, 'YES', '湖滨三公园游客中心', 0.90),
  ('chunk_202611080001_1', 6, 'YES', '全线无台阶', 0.90),
  ('chunk_202611080001_1', 8, 'YES', '龙翔桥站', 0.90),
  ('chunk_202611080001_1', 7, 'UNKNOWN', NULL, 0.90),
  ('chunk_202611080001_2', 5, 'YES', '一楼服务台旁', 0.90),
  ('chunk_202611080001_2', 6, 'YES', '坡道+电梯', 0.90),
  ('chunk_202611080001_2', 9, 'YES', '一楼服务台租借', 0.90),
  ('chunk_202611080001_2', 8, 'YES', '凤起路站', 0.90),
  ('chunk_202611080001_3', 7, 'YES', '部分餐厅有儿童座椅', 0.90),
  ('chunk_202611080001_3', 5, 'UNKNOWN', NULL, 0.90),
  ('chunk_202611080001_3', 6, 'NO', '石板路且有台阶', 0.90);

-- 查询
INSERT INTO search_query (query_id, raw_input, city_code, days, walking_limit, extra_input, result_count, status, created_at) VALUES (
  '11111111-1111-4111-8111-111111111111', '杭州 2 天，带 3 岁小孩和腿脚不便的老人，第二天可能下雨，步行别太多。', '330100', 2, 'LOW', '老人腿脚不便，希望每天有两次以上休息点。', 3, 'COMPLETED', '2026-11-10 14:52:06');

-- 查询条件标签
INSERT INTO query_tag (query_id, tag_id) VALUES
  ('11111111-1111-4111-8111-111111111111', 1),
  ('11111111-1111-4111-8111-111111111111', 2),
  ('11111111-1111-4111-8111-111111111111', 5),
  ('11111111-1111-4111-8111-111111111111', 6),
  ('11111111-1111-4111-8111-111111111111', 10);

-- 检索命中
INSERT INTO retrieval_hit (query_id, chunk_id, score, rank_no, hit_reason) VALUES
  ('11111111-1111-4111-8111-111111111111', 'chunk_202611080001_1', 12.00, 1, '城市+儿童/长者+步行低+母婴+无障碍+雨天'),
  ('11111111-1111-4111-8111-111111111111', 'chunk_202611080001_2', 10.00, 2, '城市+儿童/长者+步行低+母婴+无障碍+室内'),
  ('11111111-1111-4111-8111-111111111111', 'chunk_202611080001_3', 6.00, 3, '城市+长者+步行中');

-- 生成请求
INSERT INTO agent_request (request_id, query_id, prompt, model, stream, temperature, status, retry_count, started_at, finished_at) VALUES (
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '11111111-1111-4111-8111-111111111111', '你是旅游行程规划助手。你只能基于用户提供的攻略片段生成行程，不得编造片段之外的地点、设施、价格或开放时间。

用户条件：杭州，2 天，同行人员：儿童、长者，天气：雨天，步行上限：低，设施需求：母婴室、无障碍。
检索片段：
[片段1] 西湖湖滨步道：湖边步道平坦，推婴儿车方便，全程无台阶。
[片段2] 浙江省博物馆孤山馆区：一层有无障碍坡道与轮椅租借，母婴室位于一楼服务台旁，雨天可作为室内备选。
[片段3] 河坊街与南宋御街：石板路，部分路段有台阶，推婴儿车需绕行。

请按【分时段行程】【雨天备选】【出处与标签】三部分输出，每条建议用 [片段N] 标注出处。', 'deepseek-chat', 1, 0.70, 'SUCCESS', 0, '2026-11-10 14:52:07.120', '2026-11-10 14:52:09.840');

-- 请求上下文（Prompt 编号映射）
INSERT INTO request_context (request_id, chunk_id, marker_no, rank_no) VALUES
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'chunk_202611080001_1', 1, 1),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'chunk_202611080001_2', 2, 2),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'chunk_202611080001_3', 3, 3);

-- 生成响应
INSERT INTO agent_response (response_id, request_id, content, status, finish_reason, prompt_tokens, completion_tokens, total_tokens, latency_ms, created_at) VALUES (
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '【分时段行程】
第一天上午：西湖湖滨步道（湖滨三公园至断桥段），全程平坦无台阶，推婴儿车方便，沿途有休息椅与直饮水点。[片段1]
第一天下午：浙江省博物馆孤山馆区，室内走廊平坦，电梯直达各层，母婴室在一楼服务台旁。[片段2]
第二天傍晚：河坊街与南宋御街，石板路且有部分台阶，推婴儿车需绕行，建议只走主线并减少停留。[片段3]

【雨天备选】
第二天若降雨，可将河坊街替换为浙江省博物馆孤山馆区或湖滨银泰室内段；现有攻略对河坊街的雨天备选未覆盖。[片段2]

【出处与标签】
[片段1] 西湖湖滨步道｜步行强度：低｜母婴：有｜无障碍：有
[片段2] 浙江省博物馆孤山馆区｜步行强度：低｜母婴：有｜无障碍：有
[片段3] 河坊街与南宋御街｜步行强度：中｜母婴：未知｜无障碍：无', 'SUCCESS', 'stop', 1680, 620, 2300, 2720, '2026-11-10 14:52:09.860');

-- 引用
INSERT INTO citation (response_id, chunk_id, marker_no, excerpt, source_ref) VALUES
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'chunk_202611080001_1', 1, '西湖湖滨步道适合全家出游。湖边步道平坦，推婴儿车方便，湖滨三公园至断桥段全程无台阶，沿途设有多处休息椅与直饮水点。', 'offset:0'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'chunk_202611080001_2', 2, '浙江省博物馆孤山馆区免费预约。一层有无障碍坡道与轮椅租借，馆内走廊平坦，电梯直达各层。母婴室位于一楼服务台旁。', 'offset:76'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'chunk_202611080001_3', 3, '河坊街与南宋御街适合傍晚散步。街区以石板路为主，部分路段有台阶，推婴儿车需绕行。', 'offset:143');

-- 未覆盖城市：北京（不调用模型，直接降级）
INSERT INTO search_query (query_id, raw_input, city_code, days, walking_limit, extra_input, result_count, status, created_at) VALUES (
  '22222222-2222-4222-8222-222222222222', '北京 3 天，带小孩，想看故宫', '110100', 3, 'MEDIUM', NULL, 0, 'NO_RESULT', '2026-11-10 13:58:20');
INSERT INTO fallback_log (request_id, query_id, error_type, error_code, message, retry_count, occurred_at) VALUES (NULL, '22222222-2222-4222-8222-222222222222', 'NO_RESULT', 'CITY_NOT_COVERED', '当前攻略库未覆盖北京，已拦截生成请求', 0, '2026-11-10 13:58:20.100');

COMMIT;
