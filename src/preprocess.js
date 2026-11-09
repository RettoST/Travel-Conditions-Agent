export function chunkText(raw, maxLen = 800) {
  const paragraphs = raw.split(/\n{2,}/).map((p) => p.trim()).filter(Boolean);
  const chunks = [];
  let offset = 0;

  for (const p of paragraphs) {
    if (p.length <= maxLen) {
      chunks.push({ content: p, offset });
    } else {
      for (let i = 0; i < p.length; i += maxLen) {
        chunks.push({ content: p.slice(i, i + maxLen), offset: offset + i });
      }
    }
    offset += p.length + 2;
  }

  return chunks.map((c, i) => ({ chunkId: `chunk_${Date.now()}_${i}`, ...c }));
}

export function extractBasicFields(chunk) {
  const text = chunk.content;
  const locationMatch = text.match(/^[\s\n]*([^\n，。：:]{2,12}?)(?:：|:|\s|$)/);
  return {
    ...chunk,
    location: locationMatch ? locationMatch[1].trim() : '未知',
    suitableCrowd: inferCrowd(text),
    walkingLevel: inferWalking(text),
    babyFacility: /母婴|婴儿车|哺乳/.test(text) ? '有' : '未知',
    accessibility: /无障碍|轮椅|电梯/.test(text) ? '有' : '未知',
    rainyBackup: /雨|室内|备选/.test(text) ? text.slice(0, 200) : '未覆盖',
    sourceRef: `offset:${chunk.offset}`,
    reviewFlag: false,
  };
}

function inferCrowd(text) {
  const tags = [];
  if (/小孩|儿童|宝宝|亲子|孩子/.test(text)) tags.push('child');
  if (/老人|长者|腿脚|老年/.test(text)) tags.push('elderly');
  return tags.length ? tags : ['adult'];
}

function inferWalking(text) {
  if (/爬山|徒步|台阶多|爬台阶|步行长|爬坡/.test(text)) return '高';
  if (/平坦|少走路|轻松|电瓶车/.test(text)) return '低';
  return '中';
}