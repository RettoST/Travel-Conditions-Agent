# 随行条件 · 旅游攻略 Agent

面向多代同游的条件化攻略决策助手。

## 📂 目录说明
- `/src`：后端 Node.js 核心逻辑（含 DeepSeek API 接入、检索、预处理）（暂未完成）
- `/data`：结构化片段模拟数据库 (JSON) （与上者构成MVP）

- `/prototype`：交互原型（ `home.html` ）
- `/docs`：系统设计说明书、数据库设计说明书及 UML 图表


## 🚀 快速运行 MVP 代码
1. 复制 `.env.example` 为 `.env` 并填入 DeepSeek API Key
2. 运行 `npm install`
3. 运行 `npm start`
4. 访问 `http://localhost:3000/api/health` 查看服务状态
