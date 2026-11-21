# 数据库设计交付说明

本目录是《随行条件 · 旅游攻略 Agent》数据库设计的配套材料，与 `docs/数据库设计说明书.docx/.pdf` 配套使用。

## 1. 文件清单

| 文件 | 说明 |
| --- | --- |
| `schema.sql` | 15 张表、4 个视图的完整 MySQL 8.0 DDL |
| `seed.sql` | 城市、标签、后台账号种子数据（可重复执行） |
| `sample_data.sql` | 1 篇杭州攻略、3 个片段、1 次完整生成、1 次未覆盖降级的演示数据 |
| `ER图-全局.png` / `.svg` | 全局 E-R 图（Crow's Foot 表示法） |
| `ER图-核心溯源.png` / `.svg` | 核心溯源链路 E-R 图 |
| `../一二三队-系统设计说明书（含数据库设计）.pdf` | 系统设计说明书与本文档的合并提交版（69 页） |
| `README.md` | 本文件 |

## 2. 快速执行

```bash
mysql -u root -p < schema.sql
mysql -u root -p < seed.sql
mysql -u root -p < sample_data.sql
```

> `schema.sql` 含 `DROP TABLE` 语句，仅用于开发/演示环境初始化；生产环境请删除 DROP 或改用迁移工具，避免误删数据。`sample_data.sql` 使用固定演示 ID，重复执行会主键冲突，请先重建 schema。

执行后可验证：

```sql
USE travel_conditions;

-- 攻略列表（含城市、导入人、片段数、状态）
SELECT * FROM v_guide_admin;

-- 片段预览（含人群/场景标签、母婴/无障碍状态）
SELECT * FROM v_chunk_detail;

-- 调用链路（查询 → 请求 → 响应 → 引用/降级）
SELECT * FROM v_query_trace;

-- 降级统计
SELECT * FROM v_fallback_daily;
```

预期：`v_query_trace` 中杭州查询返回 3 条引用，北京查询返回 1 条 `NO_RESULT` 降级；`v_chunk_detail` 中三个片段分别显示西湖、浙江省博物馆、河坊街的标签与设施。

## 3. 设计要点（答辩用）

### 3.1 一句话

> 15 张表把“攻略原文 → 结构化片段 → 条件检索 → Prompt 上下文 → 生成响应 → 引用”这条链路完整落库，核心是**每一步都可追溯、每次生成都可复现**。

### 3.2 六个数据域

| 数据域 | 表 |
| --- | --- |
| 基础与权限 | `city`、`sys_user` |
| 攻略库 | `guide_text`、`guide_chunk` |
| 标签与设施 | `tag`、`chunk_tag`、`chunk_facility` |
| 查询与检索 | `search_query`、`query_tag`、`retrieval_hit` |
| 生成与溯源 | `agent_request`、`request_context`、`agent_response`、`citation` |
| 异常与审计 | `fallback_log` |

### 3.3 三个关键设计

1. **多值属性拆表**：同行人员、天气、设施需求、适合人群不用逗号分隔字符串/JSON 数组，而是 `tag` + `chunk_tag` / `chunk_facility` / `query_tag`，可索引、可约束、可统计。
2. **引用快照**：`citation` 保存 `excerpt`、`source_ref`，片段事后被人工修正，历史回答仍能展示“当时看到的那段话”。
3. **上下文快照**：`request_context` 保存 `marker_no`、`rank_no`，Prompt 中的 `[片段N]` 与片段一一对应；检索规则以后调整，历史请求仍可复现。

### 3.4 可溯源怎么走

```text
前端点击 [片段N]
  → citation（response_id + marker_no）
  → guide_chunk（chunk_id）
  → guide_text（text_id）
  → 展示 excerpt + source_ref + 当前片段
```

`citation.marker_no` 与 `request_context.marker_no` 对应，保证“模型输出的编号”和“当时给模型的片段”一致；编号缺失时前端标“出处待核对”，不补不猜。

### 3.5 ORM 映射

- `GuideText` → `guide_text`
- `GuideChunk` → `guide_chunk`（`suitableCrowd` 走 `chunk_tag`，`babyFacility/accessibility` 走 `chunk_facility`）
- `Query` → `search_query`（`companions/weather/facilityNeeds` 走 `query_tag`）
- `AgentRequest` → `agent_request`（`contextChunks` 走 `request_context`）
- `AgentResponse` → `agent_response`
- `Citation` → `citation`（`textId` 由 `chunk_id` 派生）
- `FallbackLog` → `fallback_log`

详细字段级映射见说明书第 5 章与表 5-2～5-12。

## 4. 可能被问到的问题

**Q1：为什么不用 MongoDB？**
A：本系统的条件大多是硬条件（城市必须匹配、步行不能超、设施要满足），关系表的组合索引、外键、事务和 JOIN 更合适；50–100 篇规模也不需要文档库的水平扩展。

**Q2：为什么不用向量数据库？**
A：当前检索是“标签过滤 + 关键词打分”，50–100 篇规模足够，且能解释“为什么召回这条”。后续扩到数千篇，可以加 Embedding 作为召回补充，但不替代主存储。

**Q3：为什么 `citation` 要存摘录，直接 JOIN `guide_chunk` 不行吗？**
A：片段是可变对象，管理员可以修正抽取错误。存摘录是审计快照，保证历史回答不被“事后修改”影响；当前片段仍可通过 `chunk_id` 查到，二者可以对比。

**Q4：为什么攻略不物理删除？**
A：`citation.chunk_id` 与 `request_context.chunk_id` 是 `ON DELETE RESTRICT`，只要片段被引用过就不能删；攻略用 `ARCHIVED` 状态归档，保证历史回答可复核。

**Q5：15 张表是不是太多？**
A：7 张是类图核心实体，8 张是支撑表：城市/账号维表、3 张多值关联表、检索命中、请求上下文、标签字典。它们分别解决“多值属性”“1:1 唯一性”“检索与上下文快照”，不是为拆而拆。

**Q6：当前代码用 JSON，为什么先做数据库设计？**
A：MVP 用 JSON 验证链路，数据库设计面向 V1.1 落地。说明书第 4.5 节给出了 JSON → 关系表的逐字段迁移映射，切换时不需要改类图与接口语义。
