import { loadChunks } from './store.js';

export function retrieve(query, limit = 8) {
  const all = loadChunks();
  const q = normalizeQuery(query);

  const scored = all
    .map((c) => ({ ...c, score: scoreChunk(c, q) }))
    .filter((c) => c.score > 0)
    .sort((a, b) => b.score - a.score)
    .slice(0, limit);

  return scored;
}

function normalizeQuery(query) {
  return {
    city: (query.city || '').trim(),
    companions: Array.isArray(query.companions) ? query.companions : [],
    weather: Array.isArray(query.weather) ? query.weather : [],
    walkingLevel: query.walkingLevel || '',
    facilityNeeds: Array.isArray(query.facilityNeeds) ? query.facilityNeeds : [],
    rainy: (query.weather || []).some((w) => String(w).includes('rain')),
  };
}

function scoreChunk(chunk, q) {
  let score = 0;
  const text = (chunk.content || '').toLowerCase();

  // 城市匹配：硬过滤（不匹配直接 0 分，避免跨城市推荐）
  if (q.city) {
    const cityMatch = (chunk.city || '').includes(q.city) || text.includes(q.city.toLowerCase());
    if (!cityMatch) return 0;
    score += 5;
  }

  // 步行强度：用户要低，片段是高则扣分，低则加分
  if (q.walkingLevel === '低') {
    if (chunk.walkingLevel === '低') score += 3;
    if (chunk.walkingLevel === '高') score -= 2;
  }

  // 设施需求
  if (q.facilityNeeds.includes('baby_room') && chunk.babyFacility === '有') score += 2;
  if (q.facilityNeeds.includes('accessible') && chunk.accessibility === '有') score += 2;

  // 雨天条件
  if (q.rainy && chunk.rainyBackup && chunk.rainyBackup !== '未覆盖') score += 2;

  // 同行人员
  for (const tag of q.companions) {
    if (Array.isArray(chunk.suitableCrowd) && chunk.suitableCrowd.includes(tag)) score += 2;
  }

  // 兜底：至少有一个正向得分才保留
  return score > 0 ? score : 0;
}