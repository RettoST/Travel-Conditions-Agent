-- ============================================================
-- 随行条件 · 旅游攻略 Agent
-- 基础字典数据（可重复执行）
-- 版本：V1.0    日期：2026-11-10
-- 说明：演示账号 admin / Admin@123，仅用于本地开发。
--       生产环境请在首次登录后立即修改密码。
-- ============================================================

USE travel_conditions;

SET NAMES utf8mb4;

-- 城市：V1.0 演示覆盖杭州、苏州、成都、厦门；北京用于验证“未覆盖”降级路径
INSERT IGNORE INTO city (city_code, city_name, province, coverage_status, sort_no) VALUES
  ('330100', '杭州', '浙江省', 'COVERED', 10),
  ('320500', '苏州', '江苏省', 'COVERED', 20),
  ('510100', '成都', '四川省', 'COVERED', 30),
  ('350200', '厦门', '福建省', 'COVERED', 40),
  ('110100', '北京', '北京市', 'PLANNED', 90);

-- 后台账号：admin / Admin@123（bcrypt cost=12）
INSERT IGNORE INTO sys_user (username, password_hash, display_name, role, status) VALUES
  ('admin', '$2b$12$Edq.4bgMjJHEwRnqrFkaN.lb18aCA.ciVIjNLcPjW/jdnabS9nVYi', '林女士', 'ADMIN', 'ACTIVE');

-- 标签字典
INSERT IGNORE INTO tag (tag_code, tag_name, tag_type, description, sort_no, enabled) VALUES
  ('CROWD_CHILD',    '儿童',       'CROWD',    '3-12 岁儿童，需要亲子设施与较短步行', 10, 1),
  ('CROWD_ELDERLY',  '长者',       'CROWD',    '65 岁以上，关注台阶、坡道与休息点', 20, 1),
  ('CROWD_ADULT',    '成人',       'CROWD',    '普通成人同行者', 30, 1),
  ('CROWD_PET',      '宠物',       'CROWD',    '原型保留，V1.0 不启用', 40, 0),
  ('FAC_BABY_ROOM',  '母婴室',     'FACILITY', '哺乳、换尿布空间', 10, 1),
  ('FAC_ACCESSIBLE', '无障碍',     'FACILITY', '坡道、电梯、轮椅通行', 20, 1),
  ('FAC_RESTAURANT', '亲子餐厅',   'FACILITY', '儿童座椅、儿童餐', 30, 1),
  ('FAC_METRO',      '地铁直达',   'FACILITY', '步行 500 米内可达地铁站', 40, 1),
  ('FAC_WHEELCHAIR', '轮椅租借',   'FACILITY', '场馆提供轮椅租借服务', 50, 1),
  ('WEATHER_RAINY',  '雨天',       'WEATHER',  '用户条件中出现降雨', 10, 1),
  ('SCENE_INDOOR',   '室内场馆',   'SCENE',    '博物馆、商场、室内乐园等', 10, 1),
  ('SCENE_OUTDOOR',  '户外场景',   'SCENE',    '公园、街区、湖滨等', 20, 1),
  ('SCENE_REST',     '中途休息点', 'SCENE',    '沿途座椅、茶室、驿站', 30, 1);
