import express from 'express';
import cors from 'cors';
import 'dotenv/config';
import { chatOnce } from './deepseek.js';

const app = express();
app.use(cors());
app.use(express.json({ limit: '2mb' }));

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
  const { messages } = req.body || {};
  if (!Array.isArray(messages) || messages.length === 0) {
    return res.status(400).json({ error: 'messages required' });
  }

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

  req.on('close', () => {
    clearInterval(keepAlive);
  });

  try {
    send('meta', { model: 'deepseek-flash' });

    const stream = await chatOnce(messages, { stream: true });

    for await (const chunk of stream) {
      const delta = chunk.choices?.[0]?.delta?.content;
      if (delta) send('chunk', { text: delta });
    }

    send('done', { status: 'ok' });
  } catch (err) {
    console.error('[stream error]', err.message);
    send('error', { message: '生成失败，请重试' });
  } finally {
    clearInterval(keepAlive);
    res.end();
  }
});

const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`http://localhost:${port}`));