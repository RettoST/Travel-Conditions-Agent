import OpenAI from 'openai';
import 'dotenv/config';

const client = new OpenAI({
  apiKey: process.env.DEEPSEEK_API_KEY,
  baseURL: 'https://api.deepseek.com',
});

export async function chatOnce(messages, { stream = false } = {}) {
  return client.chat.completions.create({
    model: 'deepseek-flash',
    messages,
    stream,
    temperature: 0.7,
  });
}