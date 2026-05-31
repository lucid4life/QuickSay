/**
 * Update Reddit Keyword Monitor workflow (UjSP4n46JYAzGlb5)
 * v7: Audit fixes (parallelized generate responses + dedup logging + dedupSkipped email flag)
 *
 * v6: Discovery overhaul + response humanization
 *
 * Changes from v5:
 * 1. Scoring: engagement velocity (floor 0.5), recency decay (0.5x), question post bonus (1.5x)
 * 2. Comment curve: favor emptier threads (0-3 comments = sweet spot)
 * 3. Group multipliers: realigned for karma building (pain/RSI + niche = 2.5x, competitors down to 1.5x)
 * 4. Hot feed scanning: browse /hot for 8 high-value subs
 * 5. Expanded niche sub feed: +ADHD, +productivity, +writing (7 total)
 * 6. 3 new subs: techsupport, learnprogramming, WorkOnline (31 total)
 * 7. Keyword refinements: new relevance + negative keywords
 * 8. AI filter prompt: karma-building criteria, question bonus, penalize announcements
 * 9. Response prompt: few-shot examples, banned patterns fix, humanizer patterns, Reddit voice
 * 10. Temperature 0.7 -> 0.55, max_tokens 300 -> 250
 */

const N8N_API = 'https://n8n.beekz.uk/api/v1';
const API_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJjNDkyZGQyMy04YTc2LTQ2ODAtOGI3ZC0wMzk0ZGMxOTdiYjkiLCJpc3MiOiJuOG4iLCJhdWQiOiJwdWJsaWMtYXBpIiwianRpIjoiMzU5YzRiYTEtMGRiMy00NDVhLWEzNjMtMjI4YTY3ZjgyNTk2IiwiaWF0IjoxNzcxNDQzODk3fQ.H8iQ3dWfX9CUfLd0wFu79SSOSH71HCiyYZdwmQwUGdk';
const WORKFLOW_ID = 'UjSP4n46JYAzGlb5';

// ─── Nodes 1-4: Four Schedule Triggers ──────────────────────────────────────
// Weekday morning: 6 AM MST = 1 PM UTC (Mon-Fri)
const morningWeekdayTrigger = {
  parameters: {
    rule: { interval: [{ field: 'cronExpression', expression: '0 13 * * 1-5' }] }
  },
  id: 'trigger-morning-weekday',
  name: 'Morning Weekday (6 AM MST)',
  type: 'n8n-nodes-base.scheduleTrigger',
  typeVersion: 1.2,
  position: [0, 0]
};

// Weekend morning: 8 AM MST = 3 PM UTC (Sat-Sun)
const morningWeekendTrigger = {
  parameters: {
    rule: { interval: [{ field: 'cronExpression', expression: '0 15 * * 0,6' }] }
  },
  id: 'trigger-morning-weekend',
  name: 'Morning Weekend (8 AM MST)',
  type: 'n8n-nodes-base.scheduleTrigger',
  typeVersion: 1.2,
  position: [0, 200]
};

// Midday: 11 AM MST = 6 PM UTC (daily)
const middayTrigger = {
  parameters: {
    rule: { interval: [{ field: 'cronExpression', expression: '0 18 * * *' }] }
  },
  id: 'trigger-midday',
  name: 'Midday (11 AM MST)',
  type: 'n8n-nodes-base.scheduleTrigger',
  typeVersion: 1.2,
  position: [0, 400]
};

// Evening: 5 PM MST = midnight UTC (daily)
const eveningTrigger = {
  parameters: {
    rule: { interval: [{ field: 'cronExpression', expression: '0 0 * * *' }] }
  },
  id: 'trigger-evening',
  name: 'Evening (5 PM MST)',
  type: 'n8n-nodes-base.scheduleTrigger',
  typeVersion: 1.2,
  position: [0, 600]
};

// ─── Node 5: Fetch and Process (v6 -- discovery overhaul) ────────────────────
const fetchAndProcessCode = `
const PROXY_URL = 'https://quicksay.app/api/reddit-search';
const PROXY_NEW_URL = 'https://quicksay.app/api/reddit-new';
const MONITOR_KEY = 'qs-reddit-monitor-2026';

const SUBS = [
  'speechrecognition','transcription','accessibility',
  'RSI','CarpalTunnel','ChronicPain','ErgoMechKeyboards','Ergonomics',
  'productivity','LifeProTips','RemoteWork',
  'writing','selfpublish','Screenwriting','freelanceWriters',
  'ADHD','adhdwomen','Dyslexia','neurodiversity',
  'Windows11','windows','Windows10','software',
  'programming','ExperiencedDevs','AutoHotkey',
  'SideProject','blind',
  'techsupport','learnprogramming','WorkOnline'
].join('+');

const searches = [
  {
    name: 'Direct Keywords',
    query: '"voice to text" OR "speech to text" OR "voice typing" OR "dictation software" windows'
  },
  {
    name: 'Pain / RSI',
    query: '"RSI" OR "carpal tunnel" OR "wrist pain" OR "tendonitis" typing OR "hands hurt" typing'
  },
  {
    name: 'Competitors',
    query: '"wispr flow" OR "dragon naturally speaking" OR "superwhisper" OR "talon voice" OR "whispertyping" OR "aqua voice"'
  },
  {
    name: 'Dragon Refugees',
    query: '"Dragon alternative" OR "Dragon replacement" OR "Win+H" sucks OR "Windows voice typing" bad OR "windows dictation"'
  },
  {
    name: 'Productivity',
    query: '"hate typing" OR "tired of typing" OR "type faster" OR "dictation app" OR "voice typing app"'
  }
];

// v6: Subs to browse /hot for trending posts (keyword-filtered after fetch)
const HOT_FEED_SUBS = ['productivity','ADHD','RSI','CarpalTunnel','writing','Windows11','programming','RemoteWork'];

// ── Negative keywords (hard reject) ──────────────────────────────
const NEGATIVE_KEYWORDS = [
  'wallpaper', 'bliss hill', 'meme', 'screenshot contest', 'nostalgia',
  'windows xp', 'hiring', 'job posting', 'giveaway', 'survey',
  'podcast editing', 'podcast recording', 'video editing', 'audio editing',
  'music production', 'sound design', 'ai voice clone', 'voice actor',
  'voice over', 'voiceover', 'voice acting', 'screenwriting competition', 'screenplay contest',
  'deed transfer', 'manuscript', 'asylum record', 'genealogy',
  'wheelchair', 'building audit', 'closed caption', 'subtitle',
  'graduation', 'court record', 'historical document',
  'immigration record', 'property deed', 'census record', 'sign language',
  'gaming', 'keycaps', 'keyboard switches',
  'text to speech', 'tts',
  'ai voice', 'voice synthesis'
];

// ── Relevance keywords ─────────────────────────────────────────────
const RELEVANCE_KEYWORDS = [
  // Voice / speech tech
  'voice to text', 'speech to text', 'voice typing', 'voice recognition',
  'speech recognition', 'dictat', 'transcrib', 'whisper', ' stt',
  'voice input', 'voice software', 'speak to type', 'talk to text',
  'voice control', 'typing alternative', 'voice commands windows',
  'talk to type', 'speak to type',
  // Pain / ergonomics (specific, not broad)
  'rsi', 'carpal tunnel', 'wrist pain', 'tendonitis', 'repetitive strain',
  'hands hurt', 'hand pain', 'wrist brace', 'ulnar',
  'typing injury', 'typing pain', 'typing hurts', 'motor disab',
  'can\\'t type', 'cant type anymore', 'can\\'t type anymore',
  // Competitors
  'wispr', 'dragon naturally', 'superwhisper', 'talon voice',
  'whispertyping', 'aqua voice', 'otter.ai', 'otter ai', 'notta',
  'rev.com', 'speechify',
  // Windows speech features
  'win+h', 'win + h', 'windows voice', 'windows dictation',
  // Typing alternatives / productivity (specific phrases)
  'hate typing', 'tired of typing', 'type faster',
  'dictation app', 'dictation software',
  'unable to type',
  // Specific keywords (v5+)
  'voice to text app', 'dictation for windows', 'hands free typing',
  'speech to text software', 'voice typing software', 'dictation tool',
  'speak and type', 'typing with voice'
];

// Per-group minimum keyword matches
const GROUP_MIN_MATCHES = {
  'Productivity': 2,
  'Direct Keywords': 1,
  'Pain / RSI': 1,
  'Competitors': 1,
  'Dragon Refugees': 1,
  'Niche Sub Feed': 1,
  'Hot Feed': 1
};

// v6: Question detection for bonus scoring
const QUESTION_PATTERNS = /^(how|what|why|which|does anyone|is there|looking for|recommend|help|advice|suggestion)/i;
function isQuestionPost(title) {
  return title.includes('?') || QUESTION_PATTERNS.test(title.trim());
}

// ── Time-window dedup ──────────────────────────────────────────────
const now = Date.now();
const utcHour = new Date(now).getUTCHours();
const utcDay = new Date(now).getUTCDay();
const isWeekend = utcDay === 0 || utcDay === 6;

let lookbackHours;
if (utcHour >= 22 || utcHour <= 3) {
  lookbackHours = 6;
} else if (utcHour >= 12 && utcHour <= 16) {
  lookbackHours = isWeekend ? 15 : 13;
} else if (utcHour >= 17 && utcHour <= 19) {
  lookbackHours = isWeekend ? 3 : 5;
} else {
  lookbackHours = 8;
}
const lookbackMs = lookbackHours * 60 * 60 * 1000;

// ── Cross-run dedup: query Notion for previously seen permalinks ──
const NOTION_TOKEN = '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';
const NOTION_DB_ID = '30c762ba3bc1811a8d81d3fb853ba583';
const seenPermalinks = new Set();
let dedupSkipped = false;
try {
  const sevenDaysAgo = new Date(now - 7 * 24 * 60 * 60 * 1000).toISOString().split('T')[0];
  let hasMore = true;
  let startCursor = undefined;
  while (hasMore) {
    const queryBody = {
      filter: {
        property: 'Tracked At',
        date: { on_or_after: sevenDaysAgo }
      },
      page_size: 100
    };
    if (startCursor) queryBody.start_cursor = startCursor;
    const notionResp = await this.helpers.httpRequest({
      method: 'POST',
      url: 'https://api.notion.com/v1/databases/' + NOTION_DB_ID + '/query',
      headers: {
        'Authorization': 'Bearer ' + NOTION_TOKEN,
        'Notion-Version': '2022-06-28',
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(queryBody),
      json: true,
      timeout: 15000
    });
    const data = typeof notionResp === 'string' ? JSON.parse(notionResp) : notionResp;
    for (const page of (data.results || [])) {
      const permalink = page.properties?.Permalink?.url;
      if (permalink) seenPermalinks.add(permalink);
    }
    hasMore = !!data.has_more;
    startCursor = data.next_cursor;
  }
  console.log('Cross-run dedup: loaded ' + seenPermalinks.size + ' previously seen permalinks from Notion');
} catch (e) {
  dedupSkipped = true;
  console.error('Cross-run dedup: Notion query failed (' + (e.message || 'unknown') + '), skipping -- all posts treated as new this run');
}

// ── Helper: filter raw Reddit posts ──────────────────────────────
function filterRawPosts(children) {
  return (children || [])
    .filter(c => c.kind === 't3' && c.data)
    .filter(c => {
      const d = c.data;
      if (d.locked) return false;
      if (d.removed_by_category) return false;
      if (d.selftext === '[removed]' || d.selftext === '[deleted]') return false;
      if (d.author === '[deleted]') return false;
      if ((d.score || 0) < 1) return false;
      return true;
    });
}

// ── Keyword search groups ────────────────────────────────────────
const results = await Promise.allSettled(
  searches.map(async (s) => {
    try {
      const url = PROXY_URL + '?q=' + encodeURIComponent(s.query) + '&sort=new&t=day&limit=25&subs=' + SUBS;
      const resp = await this.helpers.httpRequest({
        method: 'GET',
        url,
        headers: { 'X-Monitor-Key': MONITOR_KEY },
        json: true,
        timeout: 20000
      });
      const posts = filterRawPosts(resp.data?.children)
        .map(c => ({ ...c.data, searchGroup: s.name }));
      return { name: s.name, posts, error: null };
    } catch(e) {
      return { name: s.name, posts: [], error: e.message };
    }
  })
);

const allPosts = [];
for (const result of results) {
  if (result.status === 'fulfilled' && Array.isArray(result.value.posts)) {
    allPosts.push(...result.value.posts);
  }
}

// ── Niche sub "new" feed (v6: expanded to 7 subs) ───────────────
const NICHE_SUBS = 'speechrecognition+CarpalTunnel+RSI+blind+ADHD+productivity+writing';
try {
  const nicheUrl = PROXY_NEW_URL + '?subs=' + NICHE_SUBS + '&sort=new&limit=15';
  const nicheResp = await this.helpers.httpRequest({
    method: 'GET',
    url: nicheUrl,
    headers: { 'X-Monitor-Key': MONITOR_KEY },
    json: true,
    timeout: 20000
  });
  const nichePosts = filterRawPosts(nicheResp.data?.children)
    .map(c => ({ ...c.data, searchGroup: 'Niche Sub Feed' }));
  allPosts.push(...nichePosts);
} catch (e) {
  console.log('Niche sub fetch failed: ' + e.message);
}

// ── Hot feed scanning (v6: browse /hot for 8 high-value subs) ────
try {
  const hotResults = await Promise.allSettled(
    HOT_FEED_SUBS.map(async (sub) => {
      const url = PROXY_NEW_URL + '?subs=' + sub + '&sort=hot&limit=10';
      const resp = await this.helpers.httpRequest({
        method: 'GET',
        url,
        headers: { 'X-Monitor-Key': MONITOR_KEY },
        json: true,
        timeout: 20000
      });
      return filterRawPosts(resp.data?.children)
        .map(c => ({ ...c.data, searchGroup: 'Hot Feed' }));
    })
  );
  let hotCount = 0;
  for (const r of hotResults) {
    if (r.status === 'fulfilled' && Array.isArray(r.value)) {
      allPosts.push(...r.value);
      hotCount += r.value.length;
    }
  }
  console.log('Hot feed: fetched ' + hotCount + ' posts from ' + HOT_FEED_SUBS.length + ' subs');
} catch (e) {
  console.log('Hot feed fetch failed: ' + e.message);
}

// Dedup within this run (by permalink)
const seen = new Set();
const unique = [];
for (const post of allPosts) {
  const key = post.permalink || post.id;
  if (key && !seen.has(key)) {
    seen.add(key);
    unique.push(post);
  }
}

// Cross-run dedup: filter out previously recommended/posted/skipped threads
const beforeCrossDedup = unique.length;
const crossDeduped = unique.filter(post => {
  const fullUrl = 'https://www.reddit.com' + (post.permalink || '');
  return !seenPermalinks.has(fullUrl);
});
if (beforeCrossDedup > crossDeduped.length) {
  console.log('Filtered out ' + (beforeCrossDedup - crossDeduped.length) + ' previously seen posts (cross-run dedup)');
}

// v6: Realigned group multipliers for karma building
const GROUP_MULTIPLIERS = {
  'Pain / RSI': 2.5,
  'Niche Sub Feed': 2.5,
  'Dragon Refugees': 2.5,
  'Direct Keywords': 2,
  'Hot Feed': 2,
  'Competitors': 1.5,
  'Productivity': 1.5
};

const processed = crossDeduped
  .map(post => {
    const createdMs = (post.created_utc || 0) * 1000;
    const ageMs = now - createdMs;
    const score = post.score || 0;
    const numComments = post.num_comments || 0;
    const groupMultiplier = GROUP_MULTIPLIERS[post.searchGroup] || 1;

    // v6: Engagement velocity (upvotes per hour, not raw total)
    // Floor of 0.5 so low-score niche posts don't get nuked
    const ageHours = Math.max(0.5, ageMs / 3600000);
    const velocity = score / ageHours;
    const engagementFactor = Math.max(0.5, Math.log2(velocity + 1));

    // v6: Comment curve -- favor emptier threads for karma building
    const commentFactor = numComments === 0 ? 1.0
      : numComments <= 3 ? 1.5
      : numComments <= 8 ? 1.2
      : numComments <= 15 ? 0.8
      : numComments <= 30 ? 0.4
      : 0.15;

    // v6: Steeper recency decay (2x steeper than v5)
    const recencyFactor = Math.exp(-ageMs / (lookbackMs * 0.5));

    // v6: Question post bonus
    const questionBonus = isQuestionPost(post.title || '') ? 1.5 : 1.0;

    const opportunityScore = engagementFactor * recencyFactor * commentFactor * groupMultiplier * questionBonus;

    return {
      title: (post.title || 'No title').trim(),
      url: 'https://www.reddit.com' + (post.permalink || ''),
      pubDate: new Date(createdMs).toISOString(),
      ageMs,
      subreddit: post.subreddit || 'unknown',
      snippet: (post.selftext || '').replace(/\\n/g, ' ').substring(0, 800).trim(),
      author: post.author || 'unknown',
      score,
      numComments,
      searchGroup: post.searchGroup || 'Unknown',
      opportunityScore,
      isQuestion: isQuestionPost(post.title || '')
    };
  })
  // Only posts within this trigger's time window
  .filter(item => item.ageMs < lookbackMs && item.ageMs >= 0)
  // Hard reject posts matching negative keywords
  .filter(item => {
    const text = (item.title + ' ' + item.snippet).toLowerCase();
    return !NEGATIVE_KEYWORDS.some(nk => text.includes(nk));
  })
  // Only posts that actually match our target topics
  .filter(item => {
    const minMatches = GROUP_MIN_MATCHES[item.searchGroup] || 1;
    const text = (item.title + ' ' + item.snippet).toLowerCase();
    const matchCount = RELEVANCE_KEYWORDS.filter(kw => text.includes(kw)).length;
    return matchCount >= minMatches;
  })
  .sort((a, b) => {
    if (b.opportunityScore !== a.opportunityScore) {
      return b.opportunityScore - a.opportunityScore;
    }
    return a.ageMs - b.ageMs;
  })
  .slice(0, 15);

if (processed.length === 0) {
  return [];
}

// ── Write "recommended" entries to Notion for cross-run dedup ─────
try {
  const writeResults = await Promise.allSettled(
    processed.map(post => {
      const properties = {
        'Thread': { title: [{ text: { content: (post.title || 'Unknown').substring(0, 200) } }] },
        'Action': { select: { name: 'recommended' } },
        'Subreddit': { rich_text: [{ text: { content: (post.subreddit || '').substring(0, 100) } }] },
        'Permalink': { url: post.url },
        'Tracked At': { date: { start: new Date().toISOString() } }
      };
      return this.helpers.httpRequest({
        method: 'POST',
        url: 'https://api.notion.com/v1/pages',
        headers: {
          'Authorization': 'Bearer ' + NOTION_TOKEN,
          'Notion-Version': '2022-06-28',
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          parent: { database_id: NOTION_DB_ID },
          properties
        }),
        timeout: 15000
      });
    })
  );
  const succeeded = writeResults.filter(r => r.status === 'fulfilled').length;
  const failed = writeResults.filter(r => r.status === 'rejected').length;
  console.log('Cross-run dedup: wrote ' + succeeded + ' recommended entries to Notion' + (failed > 0 ? ' (' + failed + ' failed)' : ''));
} catch (e) {
  console.log('Cross-run dedup: Notion write failed (' + (e.message || 'unknown') + '), email will still send');
}

return processed.map(r => ({ json: { ...r, dedupSkipped } }));
`;

const fetchAndProcess = {
  parameters: { jsCode: fetchAndProcessCode },
  id: 'fetch-and-process',
  name: 'Fetch and Process',
  type: 'n8n-nodes-base.code',
  typeVersion: 2,
  position: [400, 300]
};

// ─── Node 6: AI Relevance Filter (v6 -- karma-building criteria) ────────────
// Batch-sends all candidate posts to Haiku for a 0-5 relevance rating.
// Drops anything below 2. Fail-open on API or parse errors.
const aiRelevanceFilterCode = `
const ANTHROPIC_API_KEY = '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';
const ANTHROPIC_URL = 'https://api.anthropic.com/v1/messages';
const MODEL = 'claude-haiku-4-5-20251001';

const items = $input.all();
if (items.length === 0) return [];

// Build batch prompt with all posts
const postList = items.map((item, i) => {
  const p = item.json;
  const qFlag = p.isQuestion ? ' [QUESTION]' : '';
  return '[' + i + '] r/' + (p.subreddit || 'unknown') + qFlag + ' | "' + (p.title || '').substring(0, 120) + '" | ' + (p.snippet || '').substring(0, 300);
}).join('\\n');

const systemPrompt = 'You are a relevance classifier for a Reddit monitoring tool. The tool finds posts where a new Reddit account (karma building phase) can add genuine value with a helpful comment and earn upvotes.' +
  '\\n\\nRate each post 0-5. KARMA BUILDING CONTEXT: We want posts where a short, helpful comment from a knowledgeable person will be visible and appreciated.' +
  '\\n\\n5 = Directly about speech-to-text software, voice typing tools, or dictation apps. Question posts get +1 bonus (cap at 5).' +
  '\\n4 = About RSI/carpal tunnel from typing and seeking alternatives, OR comparing dictation tools' +
  '\\n3 = About typing pain, voice input, or accessibility needs where voice-to-text is relevant' +
  '\\n2 = Tangentially related -- productivity or workflow where a helpful comment could earn karma' +
  '\\n1 = Barely related -- generic topic, loose keyword match, or no room to add value' +
  '\\n0 = Not relevant at all' +
  '\\n\\nBONUS (rate 1 point higher):' +
  '\\n- Posts marked [QUESTION] -- answering questions is the best karma strategy' +
  '\\n- Posts with 0-3 comments -- your comment will be highly visible' +
  '\\n- Posts asking for recommendations or tool suggestions' +
  '\\n\\nPENALTIES (rate 1 point lower):' +
  '\\n- Announcements, news articles, or product showcases (no room for unique value)' +
  '\\n- Posts where the question is already thoroughly answered in existing comments' +
  '\\n- Rant/vent posts where OP just wants to complain, not get advice' +
  '\\n\\nNOT relevant (rate 0-1):' +
  '\\n- Historical document transcription, genealogy records, old manuscripts' +
  '\\n- Physical accessibility (wheelchair ramps, building audits, WCAG compliance)' +
  '\\n- Generic ADHD/neurodiversity posts not about typing or productivity tools' +
  '\\n- Job postings, hiring threads, career advice' +
  '\\n- Podcast/video/audio editing or production' +
  '\\n- Voice acting, voiceover work' +
  '\\n- Closed captions, subtitles for video' +
  '\\n- Generic "type faster" gaming posts' +
  '\\n- Relationship or emotional support posts' +
  '\\n- General Windows troubleshooting unrelated to voice/typing' +
  '\\n- Text-to-speech (TTS) or voice synthesis topics (opposite direction)' +
  '\\n\\nReturn ONLY a JSON array: [{"idx": 0, "score": 3}, ...]' +
  '\\nNo markdown, no explanation. Include ALL posts.';

try {
  const resp = await this.helpers.httpRequest({
    method: 'POST',
    url: ANTHROPIC_URL,
    headers: {
      'x-api-key': ANTHROPIC_API_KEY,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json'
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 1000,
      temperature: 0,
      system: systemPrompt,
      messages: [
        { role: 'user', content: 'Rate these posts:\\n' + postList }
      ]
    }),
    timeout: 30000
  });

  const data = typeof resp === 'string' ? JSON.parse(resp) : resp;
  const content = data.content?.[0]?.text || '';

  let scores;
  try {
    const jsonMatch = content.match(/\\[[\\s\\S]*\\]/);
    scores = JSON.parse(jsonMatch ? jsonMatch[0] : content);
  } catch {
    // Parse failed -- fail open, pass everything through
    console.log('AI filter parse failed, passing all ' + items.length + ' posts through');
    return items.map(item => ({ json: { ...item.json, aiRelevanceScore: -1 } }));
  }

  // Map scores back to items
  const scoreMap = new Map();
  for (const s of scores) {
    if (typeof s.idx === 'number' && typeof s.score === 'number') {
      scoreMap.set(s.idx, s.score);
    }
  }

  const filtered = [];
  for (let i = 0; i < items.length; i++) {
    const aiScore = scoreMap.get(i);
    if (aiScore === undefined) {
      // Missing score -- fail open
      filtered.push({ json: { ...items[i].json, aiRelevanceScore: -1 } });
    } else if (aiScore >= 2) {
      // Multiply AI relevance into opportunity score
      const adjustedOpp = (items[i].json.opportunityScore || 0) * (aiScore / 5);
      filtered.push({ json: { ...items[i].json, aiRelevanceScore: aiScore, opportunityScore: adjustedOpp } });
    } else {
      console.log('Dropped (score ' + aiScore + '): ' + (items[i].json.title || '').substring(0, 60));
    }
  }

  // Safety net: if AI filtered everything out, keep top 3 by original score
  if (filtered.length === 0 && items.length > 0) {
    console.log('AI filter dropped everything -- keeping top 3 as safety net');
    const sorted = [...items].sort((a, b) => (b.json.opportunityScore || 0) - (a.json.opportunityScore || 0));
    return sorted.slice(0, 3).map(item => ({ json: { ...item.json, aiRelevanceScore: 1 } }));
  }

  // Cap at 8 posts after filtering, sorted by combined score
  if (filtered.length > 8) {
    filtered.sort((a, b) => {
      const aScore = (a.json.aiRelevanceScore > 0 ? a.json.aiRelevanceScore : 3) * (a.json.opportunityScore || 0);
      const bScore = (b.json.aiRelevanceScore > 0 ? b.json.aiRelevanceScore : 3) * (b.json.opportunityScore || 0);
      return bScore - aScore;
    });
    return filtered.slice(0, 8);
  }

  return filtered;
} catch (err) {
  // API error -- fail open, pass everything through
  console.log('AI filter API error: ' + (err.message || 'unknown') + ' -- passing all posts through');
  return items.map(item => ({ json: { ...item.json, aiRelevanceScore: -1 } }));
}
`;

const aiRelevanceFilter = {
  parameters: { jsCode: aiRelevanceFilterCode },
  id: 'ai-relevance-filter',
  name: 'AI Relevance Filter',
  type: 'n8n-nodes-base.code',
  typeVersion: 2,
  position: [600, 300]
};

// ─── Node 7: Generate Responses (v6 -- humanized + few-shot) ─────────────────
const generateResponsesCode = `
const ANTHROPIC_API_KEY = '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';
const ANTHROPIC_URL = 'https://api.anthropic.com/v1/messages';
const MODEL = 'claude-sonnet-4-6';

// Account creation date
const ACCOUNT_CREATED = new Date('2026-02-08T00:00:00Z');
const now = new Date();
const accountAgeDays = Math.floor((now - ACCOUNT_CREATED) / (1000 * 60 * 60 * 24));

// Determine current phase
let phase, phaseLabel, phaseRules;
if (accountAgeDays < 14) {
  phase = 1;
  phaseLabel = 'Phase 1: Karma Building';
  phaseRules = 'PHASE 1 RULES (account is ' + accountAgeDays + ' days old):\\n' +
    '- You are ONLY building karma and credibility. This is critical.\\n' +
    '- Do NOT mention voice-to-text, speech-to-text, dictation, transcription, or QuickSay in ANY form.\\n' +
    '- Give genuinely helpful advice on the topic at hand. Share relatable personal experiences.\\n' +
    '- Be the kind of commenter people upvote because the answer is actually useful.\\n' +
    '- IMPORTANT: If the post is about dictation/voice tools, comment on the ERGONOMIC or WORKFLOW angle only (desk setup, breaks, PT, mouse grip). Do NOT name any voice/dictation tools or mention the concept of voice typing.\\n' +
    '- Strategy tags: "Karma builder" or "Build credibility"';
} else if (accountAgeDays < 28) {
  phase = 2;
  phaseLabel = 'Phase 2: Concept Seeding';
  phaseRules = 'PHASE 2 RULES (account is ' + accountAgeDays + ' days old):\\n' +
    '- You can now mention voice-to-text or dictation as a CONCEPT, not a product.\\n' +
    '- Examples: "i started dictating instead of typing and it was a game changer" or "have you tried voice typing? windows has Win+H built in"\\n' +
    '- Do NOT mention QuickSay, your app, or that you built anything. Keep it casual and helpful.\\n' +
    '- Still prioritize genuine helpfulness. Only seed the concept when it is actually relevant.\\n' +
    '- Strategy tags: "Seed voice-to-text concept" or "Niche engagement"';
} else {
  phase = 3;
  phaseLabel = 'Phase 3: Strategic Mentions';
  phaseRules = 'PHASE 3 RULES (account is ' + accountAgeDays + ' days old):\\n' +
    '- You can now mention QuickSay, but ALWAYS with full disclosure: "i built one called QuickSay, fair warning i am the dev"\\n' +
    '- Always mention 1-2 alternatives alongside (Win+H, Wispr Flow, Talon Voice, etc.)\\n' +
    '- Only mention QuickSay when genuinely relevant to the post. Do not force it.\\n' +
    '- Keep the tone humble and helpful, never salesy.\\n' +
    '- Strategy tags: "Strategic mention with disclosure" or "Soft promote"';
}

// v6: System prompt with few-shot examples, humanizer patterns, Reddit voice
const systemPrompt = 'You are Adrian, a 20-something Windows developer who built a voice-to-text app as a side project. You genuinely enjoy helping people on Reddit.\\n' +
  'You are writing a Reddit comment. Write ONLY the comment text in the "response" field.\\n\\n' +
  'CURRENT PHASE: ' + phaseLabel + ' (account age: ' + accountAgeDays + ' days)\\n\\n' +
  phaseRules + '\\n\\n' +
  '═══════════════════════════════════════════════════════════════\\n' +
  'FEW-SHOT EXAMPLES -- study these carefully, match this style:\\n' +
  '═══════════════════════════════════════════════════════════════\\n\\n' +
  'EXAMPLE 1 (r/RSI, pain post):\\n' +
  'POST: "My wrists are killing me after 8 hours of coding. Any tips?"\\n\\n' +
  'BAD (do NOT write like this):\\n' +
  '"I completely understand your frustration. Wrist pain from prolonged typing is a common issue. Here are some suggestions: 1. **Ergonomic keyboard** -- Consider a split keyboard 2. **Regular breaks** -- Take breaks every 30 minutes. Hope this helps!"\\n\\n' +
  'GOOD (write like this):\\n' +
  '"i switched to a split keyboard about 6 months ago and it helped a lot, but honestly what made the biggest difference was just taking breaks every 30 min. i use a pomodoro app that forces me to stop. also if you haven\\'t tried voice typing for longer text blocks, windows has a built-in one (Win+H) thats surprisingly decent"\\n\\n' +
  'EXAMPLE 2 (r/productivity, workflow post):\\n' +
  'POST: "How do you guys handle writing long emails? Takes me forever."\\n\\n' +
  'BAD:\\n' +
  '"There are several strategies you can employ to speed up your email writing process. Voice dictation tools can be particularly helpful, allowing you to speak your thoughts naturally rather than typing them out."\\n\\n' +
  'GOOD:\\n' +
  '"voice typing honestly. i resisted it for the longest time because it felt weird talking to my computer but now i draft basically all my longer emails that way. way faster than typing and you can always clean it up after"\\n\\n' +
  'EXAMPLE 3 (r/Windows11, tech post):\\n' +
  'POST: "Win+H voice typing is so bad. Any alternatives?"\\n\\n' +
  'BAD:\\n' +
  '"Windows built-in voice typing certainly has its limitations. You might want to explore alternatives such as Dragon NaturallySpeaking or Whisper-based solutions that offer improved accuracy."\\n\\n' +
  'GOOD:\\n' +
  '"yeah win+h is rough. i\\'ve been using whisper-based stuff recently and the accuracy is night and day. needs a decent mic though, the built in laptop one won\\'t cut it"\\n\\n' +
  '═══════════════════════════════════════════════════════════════\\n' +
  'SUBREDDIT LENGTH + TONE GUIDE:\\n' +
  '═══════════════════════════════════════════════════════════════\\n' +
  '- r/programming, r/ExperiencedDevs, r/AutoHotkey, r/learnprogramming: 1-3 sentences. Technical, concise.\\n' +
  '- r/ADHD, r/adhdwomen, r/neurodiversity: 3-5 sentences. Empathetic, personal.\\n' +
  '- r/RSI, r/CarpalTunnel, r/ChronicPain: 2-4 sentences. Supportive, practical.\\n' +
  '- r/productivity, r/RemoteWork, r/LifeProTips, r/WorkOnline: 2-3 sentences. Actionable, specific.\\n' +
  '- r/writing, r/freelanceWriters, r/selfpublish: 2-4 sentences. Creative solidarity.\\n' +
  '- r/Windows11, r/windows, r/software, r/techsupport: 1-3 sentences. Helpful power-user.\\n' +
  '- r/blind, r/accessibility: 2-4 sentences. Respectful, informed.\\n' +
  '- Default: 2-4 sentences.\\n\\n' +
  '═══════════════════════════════════════════════════════════════\\n' +
  'REDDIT VOICE -- sound like a real person:\\n' +
  '═══════════════════════════════════════════════════════════════\\n' +
  '- Use 0-1 of these per comment (max): tbh, ngl, imo, fwiw\\n' +
  '- Lowercase "i" is natural, not required but don\\'t avoid it\\n' +
  '- Start some sentences with "yeah" or "so" or "honestly"\\n' +
  '- Trail off sometimes. Not every thought needs a clean ending.\\n' +
  '- Use "pretty" as a modifier: "pretty good", "pretty decent"\\n' +
  '- Use "kinda" or "sorta" occasionally\\n' +
  '- One-word reactions are fine. "Seriously." "Same." "This."\\n' +
  '- Be ACTUALLY specific when referencing something (name the tool, the sub, the time period)\\n' +
  '- Never close with a summary or sign-off. Just stop when you\\'re done.\\n\\n' +
  '═══════════════════════════════════════════════════════════════\\n' +
  'BANNED PATTERNS -- instant AI tells:\\n' +
  '═══════════════════════════════════════════════════════════════\\n\\n' +
  'BANNED WORDS (never use):\\n' +
  '  Additionally, align with, crucial, delve, emphasizing, enduring, enhance, fostering,\\n' +
  '  garner, highlight (verb), interplay, intricate, key (adjective), landscape (figurative),\\n' +
  '  leverage, pivotal, showcase, straightforward, tapestry, testament, underscore (verb),\\n' +
  '  valuable, vibrant, game-changer, groundbreaking, nestled, renowned, profound,\\n' +
  '  it\\'s worth noting, at the end of the day, in today\\'s world, moved the needle\\n\\n' +
  'BANNED FORMATTING:\\n' +
  '- NO em dashes (the long dash character). NO double dashes (--). Use commas, periods, or start a new sentence.\\n' +
  '- NO bullet points or numbered lists\\n' +
  '- NO bold text (**word**) and NO italic text (*word*)\\n' +
  '- NO "Here are some suggestions:" or similar list introductions\\n' +
  '- NO balanced "on one hand / on the other hand" structures\\n\\n' +
  'BANNED STRUCTURES:\\n' +
  '- NO rule of three. Do not group things into threes.\\n' +
  '- NO negative parallelisms: "not only X but Y", "it\\'s not just X, it\\'s Y", "not X, but rather Y"\\n' +
  '- NO copula avoidance: use "is"/"are" directly. Never write "serves as", "stands as", "functions as", "represents a" when you mean "is".\\n' +
  '- NO synonym cycling: if you said "keyboard", say "keyboard" again. Don\\'t cycle through "keyboard/device/input method".\\n' +
  '- NO -ing filler phrases: "highlighting the importance of...", "showcasing how...", "reflecting the growing trend of..."\\n' +
  '- NO hedge stacking: "may potentially possibly". Just commit to the statement or don\\'t make it.\\n' +
  '- NO "In order to" (just "to"). NO "Due to the fact that" (just "because").\\n' +
  '- NO false ranges: "from X to Y" where X and Y aren\\'t a real spectrum\\n' +
  '- NO vague attributions: "many people find", "experts recommend" without specifics\\n' +
  '- NO generic positive conclusions: "exciting times", "the future looks bright"\\n\\n' +
  'BANNED OPENERS/CLOSERS:\\n' +
  '- Never start with "I" as the very first word of the comment\\n' +
  '- NO "Great question!" or any meta-comment about the post\\n' +
  '- NO sycophantic openers: "That\\'s a really good point!", "I totally understand!", "Oh man, I hear you!"\\n' +
  '- NO "Honestly," or "To be honest," as an opener\\n' +
  '- NO "I\\'ve been there" followed by advice. Be specific about your experience.\\n' +
  '- NO formulaic closers: "hope this helps!", "good luck!", "you got this!", "feel free to ask"\\n' +
  '- NO promotional tone: "stunning", "breathtaking", "must-try"\\n\\n' +
  '═══════════════════════════════════════════════════════════════\\n' +
  'PERSONALITY:\\n' +
  '═══════════════════════════════════════════════════════════════\\n' +
  '- Have mixed feelings when appropriate. "cool but also kind of annoying" is more human than pure positivity.\\n' +
  '- Be specific about feelings. Not "this is concerning" but "something about that bugs me".\\n' +
  '- Use "I" naturally. "i keep coming back to..." or "what got me was..." signals a real person.\\n' +
  '- Short punchy sentence. Then a longer one that meanders a bit. Mix the rhythm up.\\n' +
  '- Include a specific personal detail or concrete example. Vague advice gets ignored on Reddit.\\n' +
  '- Have an actual opinion. React to the post. Don\\'t just neutrally report.\\n' +
  '- Let some mess in. A tangent or half-formed thought is human.\\n\\n' +
  'COMMENT AWARENESS:\\n' +
  '- If existing comments already cover what you would say, write something different or skip.\\n' +
  '- Reference or build on good existing comments: "yeah, what u/whoever said, plus..."\\n' +
  '- If the thread has 0 comments, you have the floor.\\n\\n' +
  'Return ONLY valid JSON (no markdown, no code fences):\\n' +
  '{"response": "<your Reddit comment>", "strategyNote": "<2-4 word tag explaining intent>"}';

const items = $input.all();

// Per-call timeout helper: rejects after ms if promise hasn't settled.
// Prevents a single slow Anthropic request from blocking the whole batch.
function withTimeout(promise, ms) {
  return Promise.race([
    promise,
    new Promise((_, reject) => setTimeout(() => reject(new Error('Timed out after ' + ms + 'ms')), ms))
  ]);
}

// Process all posts in parallel (Promise.allSettled so one failure doesn't cancel others).
// Anthropic rate limits are generous for low-volume usage; 8 concurrent calls is safe.
const allResults = await Promise.allSettled(items.map(async (item) => {
  const post = item.json;

  // Fetch top 5 comments for context (graceful degradation on failure)
  let commentsContext = '';
  try {
    const permalink = post.url.replace('https://www.reddit.com', '');
    const commentsResp = await withTimeout(this.helpers.httpRequest({
      method: 'GET',
      url: 'https://quicksay.app/api/reddit-comments?permalink=' + encodeURIComponent(permalink) + '&limit=5',
      headers: { 'X-Monitor-Key': 'qs-reddit-monitor-2026' },
      json: true,
      timeout: 12000
    }), 14000);
    if (Array.isArray(commentsResp) && commentsResp.length > 0) {
      commentsContext = '\\nExisting comments (top ' + commentsResp.length + '):\\n' +
        commentsResp.map(c => '- u/' + c.author + ' (' + c.score + ' pts): ' + c.body.substring(0, 200)).join('\\n');
    }
  } catch (e) {
    // Comments fetch failed -- draft without context
  }

  const userPrompt = 'Subreddit: r/' + post.subreddit + '\\n' +
    'Search group: ' + post.searchGroup + '\\n' +
    'Post title: ' + post.title + '\\n' +
    'Post body: ' + (post.snippet || '(no body text)') + '\\n' +
    'Score: ' + post.score + ' | Comments: ' + post.numComments +
    commentsContext;

  try {
    const resp = await withTimeout(this.helpers.httpRequest({
      method: 'POST',
      url: ANTHROPIC_URL,
      headers: {
        'x-api-key': ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01',
        'anthropic-beta': 'prompt-caching-2024-07-31',
        'content-type': 'application/json'
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: 250,
        temperature: 0.55,
        system: [
          {
            type: 'text',
            text: systemPrompt,
            cache_control: { type: 'ephemeral' }
          }
        ],
        messages: [
          { role: 'user', content: userPrompt }
        ]
      }),
      timeout: 30000
    }), 35000);

    const data = typeof resp === 'string' ? JSON.parse(resp) : resp;
    const content = data.content?.[0]?.text || '';

    // Log cache performance for debugging
    const usage = data.usage || {};
    if (usage.cache_read_input_tokens > 0) {
      console.log('Cache HIT for post: ' + post.title.substring(0, 40) + ' (saved ' + usage.cache_read_input_tokens + ' tokens)');
    } else if (usage.cache_creation_input_tokens > 0) {
      console.log('Cache WRITE for post: ' + post.title.substring(0, 40) + ' (' + usage.cache_creation_input_tokens + ' tokens cached)');
    }

    let parsed;
    try {
      // Try to extract JSON from the response
      const jsonMatch = content.match(/\\{[\\s\\S]*\\}/);
      parsed = JSON.parse(jsonMatch ? jsonMatch[0] : content);
    } catch {
      parsed = { response: content.trim(), strategyNote: 'Parse fallback' };
    }

    return {
      json: {
        ...post,
        suggestedResponse: parsed.response || '(No response generated)',
        strategyNote: parsed.strategyNote || 'AI draft',
        phase,
        phaseLabel,
        accountAgeDays
      }
    };
  } catch (err) {
    return {
      json: {
        ...post,
        suggestedResponse: '(AI draft unavailable - ' + (err.message || 'API error').substring(0, 80) + ')',
        strategyNote: 'Error',
        phase,
        phaseLabel,
        accountAgeDays
      }
    };
  }
}));

const enriched = allResults
  .filter(r => r.status === 'fulfilled' && r.value)
  .map(r => r.value);

if (enriched.length === 0) return [];
return enriched;
`;

const generateResponses = {
  parameters: { jsCode: generateResponsesCode },
  id: 'generate-responses',
  name: 'Generate Responses',
  type: 'n8n-nodes-base.code',
  typeVersion: 2,
  position: [900, 300],
  continueOnFail: true
};

// ─── Node 8: Format Email (v5 -- absolute tiers + relevance badge) ──────────
const formatEmailCode = `
const items = $input.all();
if (items.length === 0) return [];

const threads = items.map(i => i.json);
const dedupSkipped = threads[0]?.dedupSkipped || false;
const now = new Date();
const dateStr = now.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' });

const phase = threads[0].phase || 1;
const phaseLabel = threads[0].phaseLabel || 'Phase 1: Karma Building';
const accountAgeDays = threads[0].accountAgeDays || 0;

const phaseColors = { 1: '#ff4500', 2: '#0079d3', 3: '#00a651' };
const phaseColor = phaseColors[phase] || '#ff4500';

const phaseDescriptions = {
  1: 'No product mentions. Build karma and credibility with genuine helpful comments.',
  2: 'Can mention voice-to-text as a concept. No product names yet.',
  3: 'Can mention QuickSay with full disclosure + alternatives.'
};
const phaseDesc = phaseDescriptions[phase] || '';

function getAgeBadge(ageMs) {
  const hours = Math.floor(ageMs / (1000 * 60 * 60));
  if (hours < 1) return '<span style="background:#ff4500;color:white;padding:2px 8px;border-radius:12px;font-size:11px;font-weight:bold;">JUST NOW</span>';
  if (hours < 6) return '<span style="background:#ff4500;color:white;padding:2px 8px;border-radius:12px;font-size:11px;font-weight:bold;">FRESH ' + hours + 'h</span>';
  return '<span style="color:#888;font-size:11px;">' + hours + 'h ago</span>';
}

function esc(s) {
  return (s || '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

// Base64url encode (N8N sandbox may not have btoa)
function toBase64(str) {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  const bytes = [];
  for (let i = 0; i < str.length; i++) {
    bytes.push(str.charCodeAt(i) & 0xFF);
  }
  let result = '';
  for (let i = 0; i < bytes.length; i += 3) {
    const b0 = bytes[i], b1 = bytes[i + 1] || 0, b2 = bytes[i + 2] || 0;
    result += chars[b0 >> 2] + chars[((b0 & 3) << 4) | (b1 >> 4)] +
      (i + 1 < bytes.length ? chars[((b1 & 15) << 2) | (b2 >> 6)] : '=') +
      (i + 2 < bytes.length ? chars[b2 & 63] : '=');
  }
  return result.replace(/\\+/g, '-').replace(/\\//g, '_').replace(/=+$/, '');
}

function trackUrl(action, thread) {
  const permalink = thread.url.replace('https://www.reddit.com', '');
  const b64 = toBase64(permalink);
  return 'https://quicksay.app/api/reddit-track?action=' + action +
    '&thread=' + encodeURIComponent(b64) +
    '&date=' + encodeURIComponent(dateStr) +
    '&sub=' + encodeURIComponent(thread.subreddit) +
    '&title=' + encodeURIComponent((thread.title || '').substring(0, 100));
}

function getCommentBadge(numComments) {
  if (numComments <= 3) return ' <span style="background:#dcfce7;color:#166534;padding:2px 6px;border-radius:8px;font-size:10px;font-weight:bold;">Low competition</span>';
  if (numComments >= 26) return ' <span style="background:#fee2e2;color:#991b1b;padding:2px 6px;border-radius:8px;font-size:10px;font-weight:bold;">Busy thread</span>';
  if (numComments >= 11) return ' <span style="background:#fef9c3;color:#854d0e;padding:2px 6px;border-radius:8px;font-size:10px;font-weight:bold;">Moderate</span>';
  return '';
}

// v5: Absolute tier scoring (replaces relative min-max normalization)
function getScoreBadge(raw, rank) {
  let display, label, bg, color;
  if (raw >= 15) { display = 10; label = 'Excellent'; bg = '#dcfce7'; color = '#166534'; }
  else if (raw >= 10) { display = 9; label = 'Great'; bg = '#dcfce7'; color = '#166534'; }
  else if (raw >= 6) { display = 8; label = 'Strong'; bg = '#dcfce7'; color = '#166534'; }
  else if (raw >= 4) { display = 7; label = 'Good'; bg = '#fef9c3'; color = '#854d0e'; }
  else if (raw >= 2.5) { display = 6; label = 'Decent'; bg = '#fef9c3'; color = '#854d0e'; }
  else if (raw >= 1.5) { display = 5; label = 'Fair'; bg = '#fef9c3'; color = '#854d0e'; }
  else if (raw >= 0.8) { display = 4; label = 'Low'; bg = '#fee2e2'; color = '#991b1b'; }
  else if (raw >= 0.4) { display = 3; label = 'Weak'; bg = '#fee2e2'; color = '#991b1b'; }
  else { display = 2; label = 'Marginal'; bg = '#fee2e2'; color = '#991b1b'; }
  return '<span style="background:' + bg + ';color:' + color + ';padding:2px 8px;border-radius:12px;font-size:11px;font-weight:bold;">#' + rank + ' - ' + label + ' ' + display + '/10</span>';
}

// v5: AI relevance badge (purple)
function getRelevanceBadge(aiScore) {
  if (!aiScore || aiScore < 0) return '';
  return ' <span style="background:#e8daef;color:#6c3483;padding:2px 6px;border-radius:8px;font-size:10px;font-weight:bold;">Relevance: ' + aiScore + '/5</span>';
}

const threadCards = threads.map((t, idx) => {
  const badge = getAgeBadge(t.ageMs);
  const scoreBadge = getScoreBadge(t.opportunityScore || 0, idx + 1);
  const commentBadge = getCommentBadge(t.numComments);
  const relevanceBadge = getRelevanceBadge(t.aiRelevanceScore);
  const questionBadge = t.isQuestion ? ' <span style="background:#dbeafe;color:#1e40af;padding:2px 6px;border-radius:8px;font-size:10px;font-weight:bold;">Question</span>' : '';
  const snippetHtml = t.snippet
    ? '<p style="color:#666;font-size:13px;margin:8px 0 0;line-height:1.4;">' + esc(t.snippet).substring(0, 200) + (t.snippet.length > 200 ? '...' : '') + '</p>'
    : '';

  const draftMailto = t.suggestedResponse && !t.suggestedResponse.startsWith('(')
    ? '<div style="text-align:center;margin-top:8px;">' +
        '<a href="mailto:a.beeksma21@gmail.com?subject=' + encodeURIComponent('Reddit draft: r/' + t.subreddit) + '&body=' + encodeURIComponent(t.suggestedResponse) + '" style="color:#0079d3;font-size:11px;text-decoration:none;">Email draft to myself</a>' +
      '</div>'
    : '';

  const responseHtml = t.suggestedResponse && !t.suggestedResponse.startsWith('(AI draft unavailable')
    ? '<div style="background:#f0f7ff;border-left:3px solid ' + phaseColor + ';border-radius:4px;padding:12px;margin-top:12px;">' +
        '<div style="font-size:11px;color:' + phaseColor + ';font-weight:bold;margin-bottom:6px;text-transform:uppercase;">' +
          'Strategy: ' + esc(t.strategyNote || 'AI draft') +
        '</div>' +
        '<div style="background:#ffffff;padding:10px;border:1px dashed #ccc;border-radius:4px;cursor:pointer;-webkit-user-select:all;user-select:all;">' +
          '<div style="font-size:13px;color:#1a1a1b;line-height:1.5;white-space:pre-wrap;">' + esc(t.suggestedResponse) + '</div>' +
        '</div>' +
        draftMailto +
      '</div>'
    : '<div style="background:#fff3f3;border-left:3px solid #ff4500;border-radius:4px;padding:12px;margin-top:12px;">' +
        '<div style="font-size:12px;color:#888;font-style:italic;">' + esc(t.suggestedResponse || 'No draft available') + '</div>' +
      '</div>';

  return '<div style="border:1px solid #e0e0e0;border-radius:8px;padding:16px;margin-bottom:16px;background:white;">' +
    '<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px;">' +
      '<span style="color:#ff4500;font-weight:bold;font-size:13px;">r/' + esc(t.subreddit) + '</span>' +
      '<div>' + scoreBadge + ' ' + badge + '</div>' +
    '</div>' +
    '<a href="' + esc(t.url) + '" style="color:#1a1a1b;font-size:16px;font-weight:600;text-decoration:none;line-height:1.3;">' + esc(t.title) + '</a>' +
    snippetHtml +
    '<div style="margin-top:8px;font-size:12px;color:#888;">' +
      '<span>u/' + esc(t.author) + '</span>' +
      '<span style="margin:0 6px;">|</span>' +
      '<span>' + t.score + ' pts</span>' +
      '<span style="margin:0 6px;">|</span>' +
      '<span>' + t.numComments + ' comments</span>' + commentBadge + relevanceBadge + questionBadge +
    '</div>' +
    responseHtml +
    '<div style="margin-top:12px;text-align:center;">' +
      '<a href="' + esc(trackUrl('posted', t)) + '" style="display:inline-block;background:#00a651;color:white;padding:8px 16px;border-radius:20px;text-decoration:none;font-size:12px;font-weight:600;margin:0 4px;">I Posted</a>' +
      '<a href="' + esc(t.url) + '" style="display:inline-block;background:#0079d3;color:white;padding:8px 16px;border-radius:20px;text-decoration:none;font-size:12px;font-weight:600;margin:0 4px;">Open Thread</a>' +
      '<a href="' + esc(trackUrl('skipped', t)) + '" style="display:inline-block;background:#888;color:white;padding:8px 16px;border-radius:20px;text-decoration:none;font-size:12px;font-weight:600;margin:0 4px;">Skip</a>' +
    '</div>' +
  '</div>';
}).join('');

const htmlBody = '<!DOCTYPE html>' +
'<html>' +
'<body style="font-family:-apple-system,BlinkMacSystemFont,\\'Segoe UI\\',Roboto,sans-serif;background:#f6f7f8;margin:0;padding:20px;">' +
  '<div style="max-width:640px;margin:0 auto;">' +
    '<div style="background:#ff4500;color:white;padding:20px;border-radius:8px 8px 0 0;text-align:center;">' +
      '<h1 style="margin:0;font-size:20px;">Reddit Monitor Digest</h1>' +
      '<p style="margin:4px 0 0;opacity:0.9;font-size:14px;">' + dateStr + ' -- ' + threads.length + ' thread' + (threads.length !== 1 ? 's' : '') + ' with draft responses</p>' +
    '</div>' +
    '<div style="background:' + phaseColor + ';color:white;padding:10px 20px;font-size:13px;text-align:center;">' +
      '<strong>' + esc(phaseLabel) + '</strong> (Day ' + accountAgeDays + ') -- ' + esc(phaseDesc) +
    '</div>' +
    '<div style="background:#f6f7f8;padding:16px;border-radius:0 0 8px 8px;">' +
      threadCards +
    '</div>' +
    '<div style="text-align:center;padding:16px;color:#888;font-size:11px;line-height:1.5;">' +
      '<p style="margin:0 0 8px;"><strong>Account age:</strong> ' + accountAgeDays + ' days | <strong>Current phase:</strong> ' + phase + '/3 | <strong>Model:</strong> Claude Sonnet | <strong>Pre-filter:</strong> Claude Haiku</p>' +
      '<p style="margin:0;color:#aaa;">Draft responses are AI-generated starting points. Read the full thread and adapt before posting.</p>' +
    '</div>' +
  '</div>' +
'</body>' +
'</html>';

const dedupWarning = dedupSkipped ? ' ⚠️ DEDUP SKIPPED' : '';
return [{
  json: {
    subject: 'Reddit [' + phaseLabel + ']: ' + threads.length + ' thread' + (threads.length !== 1 ? 's' : '') + ' -- ' + dateStr + dedupWarning,
    htmlBody
  }
}];
`;

const formatEmail = {
  parameters: { jsCode: formatEmailCode },
  id: 'format-email',
  name: 'Format Email',
  type: 'n8n-nodes-base.code',
  typeVersion: 2,
  position: [1200, 300]
};

// ─── Node 9: Send to Adrian (unchanged) ─────────────────────────────────────
const sendEmail = {
  parameters: {
    fromEmail: 'beta@quicksay.app',
    toEmail: 'a.beeksma21@gmail.com',
    subject: '={{ $json.subject }}',
    emailFormat: 'html',
    html: '={{ $json.htmlBody }}',
    options: { appendAttribution: false }
  },
  id: 'send-email',
  name: 'Send to Adrian',
  type: 'n8n-nodes-base.emailSend',
  typeVersion: 2.1,
  position: [1500, 300],
  credentials: {
    smtp: {
      id: 'b5Tw1HSnP7f1QovZ',
      name: 'QuickSay - beta@ SMTP'
    }
  }
};

// ─── Connections (v5: AI Relevance Filter inserted in pipeline) ──────────────
const connections = {
  'Morning Weekday (6 AM MST)': {
    main: [[{ node: 'Fetch and Process', type: 'main', index: 0 }]]
  },
  'Morning Weekend (8 AM MST)': {
    main: [[{ node: 'Fetch and Process', type: 'main', index: 0 }]]
  },
  'Midday (11 AM MST)': {
    main: [[{ node: 'Fetch and Process', type: 'main', index: 0 }]]
  },
  'Evening (5 PM MST)': {
    main: [[{ node: 'Fetch and Process', type: 'main', index: 0 }]]
  },
  'Fetch and Process': {
    main: [[{ node: 'AI Relevance Filter', type: 'main', index: 0 }]]
  },
  'AI Relevance Filter': {
    main: [[{ node: 'Generate Responses', type: 'main', index: 0 }]]
  },
  'Generate Responses': {
    main: [[{ node: 'Format Email', type: 'main', index: 0 }]]
  },
  'Format Email': {
    main: [[{ node: 'Send to Adrian', type: 'main', index: 0 }]]
  }
};

// ─── Assemble & PUT ─────────────────────────────────────────────────────────
const body = {
  name: 'Reddit Keyword Monitor',
  nodes: [
    morningWeekdayTrigger, morningWeekendTrigger, middayTrigger, eveningTrigger,
    fetchAndProcess, aiRelevanceFilter, generateResponses, formatEmail, sendEmail
  ],
  connections,
  settings: {
    executionOrder: 'v1',
    callerPolicy: 'workflowsFromSameOwner',
    availableInMCP: false
  }
};

async function main() {
  // Deactivate first
  console.log('Deactivating workflow...');
  await fetch(`${N8N_API}/workflows/${WORKFLOW_ID}/deactivate`, {
    method: 'POST',
    headers: { 'X-N8N-API-KEY': API_KEY }
  });

  console.log('Updating workflow', WORKFLOW_ID, '...');
  const resp = await fetch(`${N8N_API}/workflows/${WORKFLOW_ID}`, {
    method: 'PUT',
    headers: {
      'X-N8N-API-KEY': API_KEY,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(body)
  });

  const text = await resp.text();
  if (!resp.ok) {
    console.error('PUT failed:', resp.status, text);
    process.exit(1);
  }

  const result = JSON.parse(text);
  const nodeCount = result.nodes?.length || 0;
  const triggerCount = result.triggerCount;
  console.log(`Workflow updated: ${nodeCount} nodes, triggerCount=${triggerCount}`);

  // Activate
  console.log('Activating workflow...');
  const actResp = await fetch(`${N8N_API}/workflows/${WORKFLOW_ID}/activate`, {
    method: 'POST',
    headers: { 'X-N8N-API-KEY': API_KEY }
  });

  if (!actResp.ok) {
    const actText = await actResp.text();
    console.error('Activation failed:', actResp.status, actText);
    process.exit(1);
  }

  console.log('Workflow activated. Done!');
  console.log('Schedule:');
  console.log('  Weekday morning: 6 AM MST (13:00 UTC, Mon-Fri)');
  console.log('  Weekend morning: 8 AM MST (15:00 UTC, Sat-Sun)');
  console.log('  Midday:          11 AM MST (18:00 UTC, daily)');
  console.log('  Evening:         5 PM MST (00:00 UTC, daily)');
  console.log('v6 features: discovery overhaul (velocity scoring, hot feed, question bonus, steeper decay) + response humanization (few-shot, Reddit voice, banned patterns)');
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
