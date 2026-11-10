export function buildMessages(query, chunks) {
  const context = chunks
    .map((c, i) => {
      const tags = [
        `步行${c.walkingLevel || '未知'}`,
        `母婴${c.babyFacility || '未知'}`,
        `无障碍${c.accessibility || '未知'}`,
        `适合人群：${(c.suitableCrowd || ['未标注']).join('/')}`,
      ].join('；');
      return `[片段${i + 1}] 地点：${c.location || '未知'}\n${c.content}\n标签：${tags}\n出处：${c.sourceRef || '未标注'}（${c.source || '来源待补充'}）`;
    })
    .join('\n\n');

  const system = `你是旅游行程规划助手。你只能基于用户提供的攻略片段生成行程，不得编造片段之外的地点、设施、价格或开放时间。

输出必须包含以下三部分，用标题分隔：
【分时段行程】按天、按上午/下午/晚上列出安排
【雨天备选】单独列出适合雨天的替代方案
【出处与标签】每条建议后用 [片段N] 标注出处编号，并附步行强度、母婴设施、无障碍情况

规则：
1. 如果某个信息片段中未覆盖，明确写"未覆盖"，不要推测；
2. 主推荐地点必须来自片段，不得引入片段外的地点；
3. 雨天备选如果片段中无相关信息，明确写"现有攻略未覆盖该场景的雨天备选"。`;

  const user = `用户条件：
城市：${query.city || '未指定'}
天数：${query.days || '未指定'}
同行人员：${(query.companions || []).join('、') || '未指定'}
天气：${(query.weather || []).join('、') || '未指定'}
步行强度上限：${query.walkingLevel || '未指定'}
设施需求：${(query.facilityNeeds || []).join('、') || '未指定'}
补充说明：${query.extraInput || '无'}

检索到的攻略片段：
${context || '（无匹配片段）'}`;

  return [
    { role: 'system', content: system },
    { role: 'user', content: user },
  ];
}