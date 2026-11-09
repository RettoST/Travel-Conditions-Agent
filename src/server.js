import express from 'express';
import cors from 'cors';
import 'dotenv/config';
import { chatOnce } from './deepseek.js';
import { chunkText, extractBasicFields } from './preprocess.js';
import { saveRawGuide, saveChunks, loadChunks, listGuides } from './store.js';
import { retrieve } from './retrieve.js';
import { buildMessages } from './prompt.js';

const app = express();
app.use(cors());
app.use(express.json({ limit: '2mb' }));
app.use(express.static('public'));

app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', deepseek: process.env.DEEPSEEK_API_KEY ? 'configured' : 'missing' });
});

// 非流式接口（第 2 步保留）
app.post('/api/chat', async (req, res) => {
  try {
    const { messages } = req.body;
    if (!Array.isArray(messages) || messages.length === 0) {
      return res.status(400).json({ error: 'messages required' });
    }
    const completion = await chatOnce(messages, { stream: false });
    res.json({ content: completion.choices[0].message.content });
  } catch (err) {
    console.error('[chat error]', err.message);
    res.status(500).json({ error: 'Agent 调用失败' });
  }
});

// 新增：SSE 流式接口
app.post('/api/query/stream', async (req, res) => {
  const query = req.body || {};

  res.writeHead(200, {
    'Content-Type': 'text/event-stream; charset=utf-8',
    'Cache-Control': 'no-cache',
    Connection: 'keep-alive',
    'X-Accel-Buffering': 'no',
  });
  res.flushHeaders?.();

  const send = (event, data) => {
    res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
  };

  const keepAlive = setInterval(() => res.write(': keep-alive\n\n'), 30000);
  req.on('close', () => clearInterval(keepAlive));

  try {
    const chunks = retrieve(query, 8);

    // 检索为空：不调用 Agent，直接返回提示（对应 FR-FALLBACK-02）
    if (chunks.length === 0) {
      send('error', {
        type: 'no_result',
        message: '当前攻略库未覆盖该城市或条件组合，请更换城市或放宽条件',
      });
      return;
    }

    send('meta', {
      model: 'deepseek-flash',
      retrievedChunks: chunks.length,
      chunkIds: chunks.map((c) => c.chunkId),
    });

    const messages = buildMessages(query, chunks);
    const stream = await chatOnce(messages, { stream: true });

    for await (const chunk of stream) {
      const delta = chunk.choices?.[0]?.delta?.content;
      if (delta) send('chunk', { text: delta });
    }

    send('done', { status: 'ok', retrievedChunks: chunks.length });
  } catch (err) {
    console.error('[query stream error]', err.message);
    send('error', { type: 'agent_error', message: '生成失败，请重试' });
  } finally {
    clearInterval(keepAlive);
    res.end();
  }
});

// 导入攻略长文本并自动预处理
app.post('/api/admin/import', async (req, res) => {
  try {
    const { title, city, source, rawText } = req.body || {};
    if (!rawText || rawText.length < 50) {
      return res.status(400).json({ error: 'rawText 太短，至少 50 字符' });
    }

    const guide = saveRawGuide({
      title: title || '未命名攻略',
      city: city || '未知',
      source: source || '来源待补充',
      rawText,
    });

    const chunks = chunkText(rawText).map((c) => ({
      ...extractBasicFields(c),
      textId: guide.textId,
      city: guide.city,
      source: guide.source,
    }));

    const total = saveChunks(chunks);

    res.json({ textId: guide.textId, imported: chunks.length, totalChunks: total });
  } catch (err) {
    console.error('[import error]', err.message);
    res.status(500).json({ error: '导入失败' });
  }
});

// 攻略列表（只返回元数据）
app.get('/api/admin/guides', (req, res) => {
  try {
    res.json({ guides: listGuides() });
  } catch (err) {
    console.error('[list guides error]', err.message);
    res.status(500).json({ error: '读取失败' });
  }
});

// 查看结构化片段（分页）
app.get('/api/admin/chunks', (req, res) => {
  try {
    const page = Math.max(1, Number(req.query.page) || 1);
    const size = Math.min(50, Math.max(1, Number(req.query.size) || 10));
    const all = loadChunks();
    const start = (page - 1) * size;
    res.json({
      total: all.length,
      page,
      size,
      items: all.slice(start, start + size),
    });
  } catch (err) {
    console.error('[list chunks error]', err.message);
    res.status(500).json({ error: '读取失败' });
  }
});

// 按 chunkId 查询单个片段，供前端出处浮层使用
app.get('/api/chunks/:chunkId', (req, res) => {
  try {
    const all = loadChunks();
    const chunk = all.find((c) => c.chunkId === req.params.chunkId);
    if (!chunk) {
      return res.status(404).json({ error: '出处暂不可用' });
    }
    res.json(chunk);
  } catch (err) {
    console.error('[get chunk error]', err.message);
    res.status(500).json({ error: '读取失败' });
  }
});

const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`http://localhost:${port}`));