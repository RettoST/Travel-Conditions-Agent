import fs from 'fs';
import path from 'path';

const DATA_DIR = path.resolve('data');
const CHUNKS_FILE = path.join(DATA_DIR, 'chunks.json');
const RAW_DIR = path.join(DATA_DIR, 'raw');

function ensureDir() {
  if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
  if (!fs.existsSync(RAW_DIR)) fs.mkdirSync(RAW_DIR, { recursive: true });
}

export function saveRawGuide({ title, city, source, rawText }) {
  ensureDir();
  const textId = `guide_${Date.now()}`;
  const filePath = path.join(RAW_DIR, `${textId}.json`);
  const record = { textId, title, city, source, rawText, importTime: new Date().toISOString() };
  fs.writeFileSync(filePath, JSON.stringify(record, null, 2), 'utf-8');
  return record;
}

export function saveChunks(chunks) {
  ensureDir();
  const existing = loadChunks();
  const merged = [...existing, ...chunks];
  fs.writeFileSync(CHUNKS_FILE, JSON.stringify(merged, null, 2), 'utf-8');
  return merged.length;
}

export function loadChunks() {
  ensureDir();
  if (!fs.existsSync(CHUNKS_FILE)) return [];
  return JSON.parse(fs.readFileSync(CHUNKS_FILE, 'utf-8'));
}

export function listGuides() {
  ensureDir();
  const files = fs.readdirSync(RAW_DIR).filter((f) => f.endsWith('.json'));
  return files.map((f) => {
    const { rawText, ...meta } = JSON.parse(fs.readFileSync(path.join(RAW_DIR, f), 'utf-8'));
    return meta;
  });
}