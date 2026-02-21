// Creates or updates the Social Media Auto-Poster workflow in N8N
// Usage: node create-social-poster-workflow.js
// Mode: deactivate -> PUT update -> reactivate (workflow mGeOQKr0JmMBxiyM)

const N8N_URL = 'https://n8n.beekz.uk/api/v1';
const N8N_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJjNDkyZGQyMy04YTc2LTQ2ODAtOGI3ZC0wMzk0ZGMxOTdiYjkiLCJpc3MiOiJuOG4iLCJhdWQiOiJwdWJsaWMtYXBpIiwianRpIjoiMzU5YzRiYTEtMGRiMy00NDVhLWEzNjMtMjI4YTY3ZjgyNTk2IiwiaWF0IjoxNzcxNDQzODk3fQ.H8iQ3dWfX9CUfLd0wFu79SSOSH71HCiyYZdwmQwUGdk';

// --- Constants embedded in Code nodes ---
const NOTION_TOKEN = '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';
const NOTION_DB_ID = '30c762ba3bc181b9b26ff20bf62ff4c5';
const RUBE_TOKEN = 'eyJhbGciOiJIUzI1NiJ9.eyJ1c2VySWQiOiJ1c2VyXzAxS0g1TjhDMEVRV1FTM0gyNEpDSFo2QkZYIiwib3JnSWQiOiJvcmdfMDFLSDVOOFRSMDVSNFdTQTdSQTcyWU4xMUQiLCJpYXQiOjE3NzEzNjg5NDl9.FPu6WNqbIAyJkTDR8KKsbc4Oq49AyHVUM4mrNDpvUbg';
const TWITTER_CA = 'ca_zmFzeri40WXI';
const LINKEDIN_CA = 'ca_nG6Z3tCtMXoR';
const LINKEDIN_URN = 'urn:li:person:Rqf5guezWz';

// ==========================================
// CODE NODE: Query Notion for Today's Posts
// ==========================================
const queryNotionCode = `
const NOTION_TOKEN = '${NOTION_TOKEN}';
const DB_ID = '${NOTION_DB_ID}';
const platform = $input.item.json.platform;

// Today's date in MST (America/Denver) -- robust against DST and early-morning schedule shifts.
// en-CA locale returns YYYY-MM-DD format which Notion's date filter expects.
const today = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Denver', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());

const data = await this.helpers.httpRequest({
  method: 'POST',
  url: 'https://api.notion.com/v1/databases/' + DB_ID + '/query',
  headers: {
    'Authorization': 'Bearer ' + NOTION_TOKEN,
    'Notion-Version': '2022-06-28'
  },
  body: {
    filter: {
      and: [
        { property: 'Date', date: { equals: today } },
        { property: 'Status', select: { equals: 'Not Posted' } },
        { property: 'Platform', select: { equals: platform } }
      ]
    }
  },
  json: true
});
const results = data.results || [];

if (results.length === 0) {
  return [];
}

return results.map(page => {
  const props = page.properties;
  const content = (props.Content?.rich_text || []).map(t => t.plain_text).join('');
  const hashtags = (props.Hashtags?.rich_text || []).map(t => t.plain_text).join('');
  const notes = (props.Notes?.rich_text || []).map(t => t.plain_text).join('');
  const title = (props.Title?.title || []).map(t => t.plain_text).join('');
  const postNumber = props['Post Number']?.number;
  const linkUrl = props['Link URL']?.url || '';

  let postText = content;

  if (platform === 'Twitter') {
    if (hashtags && !content.includes(hashtags.trim())) {
      postText = content.trimEnd() + '\\n\\n' + hashtags;
    }
    // Twitter wraps all URLs as 23-char t.co links regardless of original length.
    // Count against limit using t.co-sized placeholders so long URLs don't cause truncation.
    const charCount = postText.replace(/https?:\/\/\S+/g, 'x'.repeat(23)).length;
    if (charCount > 280) {
      postText = postText.substring(0, 277) + '...';
    }
  }

  return {
    json: {
      platform,
      title,
      content,
      postText,
      hashtags,
      notes,
      pageId: page.id,
      postNumber,
      linkUrl
    }
  };
});
`;

// ==========================================
// CODE NODE: Post via Rube MCP
// ==========================================
const postViaRubeCode = `
const RUBE_TOKEN = '${RUBE_TOKEN}';
const platform = $json.platform;
let postText = $json.postText;
const linkUrl = $json.linkUrl || '';

// For LinkedIn with a linkUrl, strip the URL from post text before posting
if (platform === 'LinkedIn' && linkUrl) {
  postText = postText.replace(linkUrl, '').replace(/\\n{3,}/g, '\\n\\n').trim();
}

// Base64 encode the text to avoid escaping issues in Python
const b64Text = Buffer.from(postText, 'utf-8').toString('base64');

// Helper: call Rube MCP and parse SSE response
async function callRube(pythonCode, thought, step) {
  const text = await this.helpers.httpRequest({
    method: 'POST',
    url: 'https://rube.app/mcp',
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream',
      'Authorization': 'Bearer ' + RUBE_TOKEN
    },
    body: JSON.stringify({
      jsonrpc: '2.0',
      method: 'tools/call',
      params: {
        name: 'RUBE_REMOTE_WORKBENCH',
        arguments: {
          code_to_execute: pythonCode,
          thought: thought,
          current_step: step
        }
      },
      id: 1
    }),
    timeout: 60000
  });

  // httpRequest may auto-parse JSON or return raw SSE text
  let parsed;
  if (typeof text === 'object') {
    parsed = text;
  } else {
    const dataLine = String(text).split('\\n').find(l => l.startsWith('data: '));
    if (!dataLine) return { ok: false, error: 'No SSE data line in response', stdout: '' };
    parsed = JSON.parse(dataLine.slice(6));
  }
  if (parsed.error) return { ok: false, error: parsed.error.message || JSON.stringify(parsed.error), stdout: '' };

  const content = parsed.result?.content?.[0]?.text;
  if (!content) return { ok: false, error: 'No content in response', stdout: '' };

  const inner = JSON.parse(content);
  const stdout = inner.data?.data?.stdout || '';
  const resultLine = stdout.split('\\n').find(l => l.startsWith('POSTRESULT:'));
  if (!resultLine) return { ok: false, error: 'No POSTRESULT in stdout: ' + stdout.substring(0, 500), stdout };

  return { ...JSON.parse(resultLine.slice(11)), stdout };
}

// Retry wrapper: retries once on thrown exceptions (network error, timeout).
// Does NOT retry on application-level errors (postResult.ok === false) since those
// likely mean LinkedIn/Twitter rejected the content, not a transient issue.
async function callRubeWithRetry(pythonCode, thought, step) {
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      return await callRube(pythonCode, thought, step);
    } catch (e) {
      if (attempt === 0) {
        console.log('Rube call failed (attempt 1), retrying in 4s: ' + e.message);
        await new Promise(r => setTimeout(r, 4000));
      } else {
        throw e;
      }
    }
  }
}

let pythonCode;
if (platform === 'Twitter') {
  pythonCode = [
    'import json, base64',
    "text = base64.b64decode('" + b64Text + "').decode('utf-8')",
    "result, error = run_composio_tool(tool_slug='TWITTER_CREATION_OF_A_POST', arguments={'text': text})",
    'if error:',
    "    print('POSTRESULT:' + json.dumps({'ok': False, 'error': str(error)}))",
    'else:',
    "    print('POSTRESULT:' + json.dumps({'ok': True, 'data': result}))"
  ].join('\\n');
} else {
  pythonCode = [
    'import json, base64',
    "text = base64.b64decode('" + b64Text + "').decode('utf-8')",
    "result, error = run_composio_tool(tool_slug='LINKEDIN_CREATE_LINKED_IN_POST', arguments={'author': '${LINKEDIN_URN}', 'commentary': text, 'visibility': 'PUBLIC'})",
    'if error:',
    "    print('POSTRESULT:' + json.dumps({'ok': False, 'error': str(error)}))",
    'else:',
    "    print('POSTRESULT:' + json.dumps({'ok': True, 'data': result}))"
  ].join('\\n');
}

let success = false;
let postResult = {};
let errorMsg = '';
let commentSuccess = false;
let commentError = '';

try {
  postResult = await callRubeWithRetry(pythonCode, 'Post to ' + platform, 'POSTING');
  success = postResult.ok === true;
  if (!success) errorMsg = postResult.error || 'Unknown post error';
} catch (e) {
  errorMsg = 'HTTP error: ' + e.message;
}

// LinkedIn auto-comment: post the link as a first comment
if (success && platform === 'LinkedIn' && linkUrl) {
  try {
    // Extract post URN from the response data
    const postData = postResult.data || {};
    let postUrn = postData['\\$URN'] || postData.id || '';

    // If no URN found, try to find it in the stringified result
    if (!postUrn) {
      const dataStr = JSON.stringify(postData);
      const urnMatch = dataStr.match(/urn:li:(share|ugcPost):[A-Za-z0-9]+/);
      if (urnMatch) postUrn = urnMatch[0];
    }

    if (postUrn) {
      const b64Link = Buffer.from(linkUrl, 'utf-8').toString('base64');
      const b64Urn = Buffer.from(postUrn, 'utf-8').toString('base64');

      // Python code to post a comment, with retry on threadUrn mismatch
      const commentPython = [
        'import json, base64, re',
        "link = base64.b64decode('" + b64Link + "').decode('utf-8')",
        "post_urn = base64.b64decode('" + b64Urn + "').decode('utf-8')",
        "actor = '${LINKEDIN_URN}'",
        '',
        "result, error = run_composio_tool(tool_slug='LINKEDIN_CREATE_COMMENT_ON_POST', arguments={'target_urn': post_urn, 'object': post_urn, 'actor': actor, 'message': {'text': link}})",
        '',
        '# Retry with corrected URN if LinkedIn returns a threadUrn mismatch',
        "if error and 'threadUrn' in str(error):",
        "    err_str = str(error)",
        "    match = re.search(r'urn:li:(share|ugcPost):[A-Za-z0-9]+', err_str)",
        '    if match:',
        '        corrected_urn = match.group(0)',
        "        result, error = run_composio_tool(tool_slug='LINKEDIN_CREATE_COMMENT_ON_POST', arguments={'target_urn': corrected_urn, 'object': corrected_urn, 'actor': actor, 'message': {'text': link}})",
        '',
        'if error:',
        "    print('POSTRESULT:' + json.dumps({'ok': False, 'error': str(error)}))",
        'else:',
        "    print('POSTRESULT:' + json.dumps({'ok': True, 'data': result}))"
      ].join('\\n');

      const commentResult = await callRube(commentPython, 'Comment link on LinkedIn post', 'COMMENTING');
      commentSuccess = commentResult.ok === true;
      if (!commentSuccess) commentError = commentResult.error || 'Unknown comment error';
    } else {
      commentError = 'Could not extract post URN from response';
    }
  } catch (e) {
    commentError = 'Comment HTTP error: ' + e.message;
  }
}

return [{
  json: {
    ...$json,
    postText,
    postSuccess: success,
    postResult,
    postError: errorMsg,
    commentSuccess,
    commentError,
    linkUrl
  }
}];
`;

// ==========================================
// CODE NODE: Update Notion Status
// ==========================================
const updateNotionCode = `
const NOTION_TOKEN = '${NOTION_TOKEN}';
const pageId = $json.pageId;
const success = $json.postSuccess;

const now = new Date().toISOString();

const properties = success
  ? {
      Status: { select: { name: 'Posted' } },
      'Posted At': { date: { start: now } }
    }
  : {
      Status: { select: { name: 'Failed' } }
    };

try {
  await this.helpers.httpRequest({
    method: 'PATCH',
    url: 'https://api.notion.com/v1/pages/' + pageId,
    headers: {
      'Authorization': 'Bearer ' + NOTION_TOKEN,
      'Notion-Version': '2022-06-28'
    },
    body: { properties },
    json: true
  });
} catch (e) {
  // Non-fatal: post already published even if Notion update fails
}

return [{ json: $json }];
`;

// ==========================================
// CODE NODE: Format Confirmation Email
// ==========================================
const formatEmailCode = `
const platform = $json.platform;
const success = $json.postSuccess;
const title = $json.title;
const postText = $json.postText;
const notes = $json.notes;
const postNumber = $json.postNumber;
const error = $json.postError;
const linkUrl = $json.linkUrl || '';
const commentSuccess = $json.commentSuccess || false;
const commentError = $json.commentError || '';

const platformColor = platform === 'Twitter' ? '#1DA1F2' : '#0A66C2';
const statusColor = success ? '#16a34a' : '#dc2626';
const statusText = success ? 'Published' : 'FAILED';
const preview = postText.length > 200 ? postText.substring(0, 200) + '...' : postText;

let notesHtml = '';

// Link auto-comment feedback (replaces old manual-move notes for link posts)
if (linkUrl && success) {
  if (commentSuccess) {
    notesHtml += '<div style="background:#f0fdf4;border:1px solid #16a34a;border-radius:6px;padding:10px 14px;margin-top:12px;">'
      + '<strong style="color:#16a34a;">Link auto-commented:</strong> ' + linkUrl.replace(/</g, '&lt;')
      + '</div>';
  } else {
    notesHtml += '<div style="background:#fef2f2;border:1px solid #dc2626;border-radius:6px;padding:10px 14px;margin-top:12px;">'
      + '<strong style="color:#dc2626;">Link comment failed:</strong> '
      + (commentError || 'Unknown error').replace(/</g, '&lt;').substring(0, 300)
      + '<br><em>Please manually add this link as a first comment: ' + linkUrl.replace(/</g, '&lt;') + '</em>'
      + '</div>';
  }
}

// Non-link notes still show as orange callout
if (notes) {
  notesHtml += '<div style="background:#fff7ed;border:1px solid #f97316;border-radius:6px;padding:10px 14px;margin-top:12px;">'
    + '<strong style="color:#ea580c;">Note:</strong> ' + notes.replace(/</g, '&lt;')
    + '</div>';
}

let errorHtml = '';
if (!success && error) {
  errorHtml = '<div style="background:#fef2f2;border:1px solid #dc2626;border-radius:6px;padding:10px 14px;margin-top:12px;">'
    + '<strong style="color:#dc2626;">Error:</strong> ' + (error || 'Unknown error').replace(/</g, '&lt;').substring(0, 500)
    + '</div>';
}

const subject = success
  ? platform + ': Post #' + postNumber + ' published'
  : platform + ': Post #' + postNumber + ' FAILED';

const html = \`<!DOCTYPE html>
<html><head><meta charset="UTF-8"></head>
<body style="margin:0;padding:0;background:#f4f4f5;font-family:Arial,sans-serif;">
<div style="max-width:560px;margin:20px auto;background:#fff;border-radius:10px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,0.1);">
  <div style="background:\${platformColor};color:#fff;padding:16px 20px;">
    <h2 style="margin:0;font-size:18px;">\${platform} Auto-Post</h2>
  </div>
  <div style="padding:20px;">
    <div style="display:inline-block;background:\${statusColor};color:#fff;padding:4px 12px;border-radius:20px;font-size:13px;font-weight:bold;margin-bottom:12px;">
      \${statusText}
    </div>
    <h3 style="margin:8px 0 4px;color:#18181b;">Post #\${postNumber}: \${title}</h3>
    <div style="background:#f9fafb;border:1px solid #e5e7eb;border-radius:6px;padding:12px;margin-top:8px;white-space:pre-wrap;font-size:14px;color:#374151;line-height:1.5;">
\${preview.replace(/</g, '&lt;')}
    </div>
    \${notesHtml}
    \${errorHtml}
    <p style="margin-top:16px;font-size:12px;color:#9ca3af;">Sent automatically by QuickSay Social Media Poster</p>
  </div>
</div>
</body></html>\`;

return [{ json: { subject, html, platform, postSuccess: success } }];
`;

// ==========================================
// WORKFLOW DEFINITION
// ==========================================
const workflow = {
  name: 'QuickSay Social Media Auto-Poster',
  nodes: [
    // Node 1: Twitter Schedule Trigger
    {
      parameters: {
        rule: {
          interval: [
            {
              field: 'cronExpression',
              expression: '0 16 * * *'
            }
          ]
        }
      },
      id: 'twitter-schedule',
      name: 'Twitter Schedule (9AM MST)',
      type: 'n8n-nodes-base.scheduleTrigger',
      typeVersion: 1.2,
      position: [0, 0]
    },
    // Node 2: LinkedIn Schedule Trigger
    {
      parameters: {
        rule: {
          interval: [
            {
              field: 'cronExpression',
              expression: '0 17 * * *'
            }
          ]
        }
      },
      id: 'linkedin-schedule',
      name: 'LinkedIn Schedule (10AM MST)',
      type: 'n8n-nodes-base.scheduleTrigger',
      typeVersion: 1.2,
      position: [0, 240]
    },
    // Node 3: Set Twitter Platform
    {
      parameters: {
        mode: 'manual',
        duplicateItem: false,
        assignments: {
          assignments: [
            {
              id: 'platform-twitter',
              name: 'platform',
              value: 'Twitter',
              type: 'string'
            }
          ]
        },
        includeOtherFields: false
      },
      id: 'set-twitter',
      name: 'Set Twitter',
      type: 'n8n-nodes-base.set',
      typeVersion: 3.4,
      position: [220, 0]
    },
    // Node 4: Set LinkedIn Platform
    {
      parameters: {
        mode: 'manual',
        duplicateItem: false,
        assignments: {
          assignments: [
            {
              id: 'platform-linkedin',
              name: 'platform',
              value: 'LinkedIn',
              type: 'string'
            }
          ]
        },
        includeOtherFields: false
      },
      id: 'set-linkedin',
      name: 'Set LinkedIn',
      type: 'n8n-nodes-base.set',
      typeVersion: 3.4,
      position: [220, 240]
    },
    // Node 5: Query Notion
    {
      parameters: {
        jsCode: queryNotionCode
      },
      id: 'query-notion',
      name: 'Query Notion for Posts',
      type: 'n8n-nodes-base.code',
      typeVersion: 2,
      position: [460, 120]
    },
    // Node 6: Post via Rube MCP
    {
      parameters: {
        jsCode: postViaRubeCode
      },
      id: 'post-via-rube',
      name: 'Post via Rube MCP',
      type: 'n8n-nodes-base.code',
      typeVersion: 2,
      position: [700, 120]
    },
    // Node 7: Update Notion Status
    {
      parameters: {
        jsCode: updateNotionCode
      },
      id: 'update-notion',
      name: 'Update Notion Status',
      type: 'n8n-nodes-base.code',
      typeVersion: 2,
      position: [940, 120]
    },
    // Node 8: Format Email
    {
      parameters: {
        jsCode: formatEmailCode
      },
      id: 'format-email',
      name: 'Format Confirmation Email',
      type: 'n8n-nodes-base.code',
      typeVersion: 2,
      position: [1180, 120]
    },
    // Node 9: Send Email
    {
      parameters: {
        fromEmail: 'beta@quicksay.app',
        toEmail: 'a.beeksma21@gmail.com',
        subject: '={{ $json.subject }}',
        emailFormat: 'html',
        html: '={{ $json.html }}',
        options: {
          appendAttribution: false,
          replyTo: 'beta@quicksay.app'
        }
      },
      id: 'send-email',
      name: 'Send Confirmation Email',
      type: 'n8n-nodes-base.emailSend',
      typeVersion: 2.1,
      position: [1420, 120],
      credentials: {
        smtp: {
          id: 'b5Tw1HSnP7f1QovZ',
          name: 'QuickSay - beta@ SMTP'
        }
      }
    }
  ],
  connections: {
    'Twitter Schedule (9AM MST)': {
      main: [[{ node: 'Set Twitter', type: 'main', index: 0 }]]
    },
    'LinkedIn Schedule (10AM MST)': {
      main: [[{ node: 'Set LinkedIn', type: 'main', index: 0 }]]
    },
    'Set Twitter': {
      main: [[{ node: 'Query Notion for Posts', type: 'main', index: 0 }]]
    },
    'Set LinkedIn': {
      main: [[{ node: 'Query Notion for Posts', type: 'main', index: 0 }]]
    },
    'Query Notion for Posts': {
      main: [[{ node: 'Post via Rube MCP', type: 'main', index: 0 }]]
    },
    'Post via Rube MCP': {
      main: [[{ node: 'Update Notion Status', type: 'main', index: 0 }]]
    },
    'Update Notion Status': {
      main: [[{ node: 'Format Confirmation Email', type: 'main', index: 0 }]]
    },
    'Format Confirmation Email': {
      main: [[{ node: 'Send Confirmation Email', type: 'main', index: 0 }]]
    }
  },
  settings: {
    executionOrder: 'v1'
  }
};

// ==========================================
// UPDATE WORKFLOW VIA API
// ==========================================
const WORKFLOW_ID = 'mGeOQKr0JmMBxiyM';

function n8nRequest(method, path, body) {
  const https = require('https');
  return new Promise((resolve, reject) => {
    const bodyStr = body ? JSON.stringify(body) : '';
    const options = {
      hostname: 'n8n.beekz.uk',
      path: '/api/v1' + path,
      method,
      headers: {
        'Content-Type': 'application/json',
        'X-N8N-API-KEY': N8N_KEY,
        ...(bodyStr ? { 'Content-Length': Buffer.byteLength(bodyStr) } : {})
      }
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, data: JSON.parse(data) });
        } catch (e) {
          resolve({ status: res.statusCode, data: data.substring(0, 2000) });
        }
      });
    });
    req.on('error', reject);
    if (bodyStr) req.write(bodyStr);
    req.end();
  });
}

async function main() {
  // 1. Deactivate
  console.log('Deactivating workflow', WORKFLOW_ID, '...');
  const deact = await n8nRequest('POST', '/workflows/' + WORKFLOW_ID + '/deactivate');
  console.log('Deactivate:', deact.status === 200 ? 'OK' : 'Status ' + deact.status);

  // 2. PUT updated definition (only allowed keys)
  console.log('Updating workflow definition...');
  const { name, nodes, connections, settings } = workflow;
  const putResult = await n8nRequest('PUT', '/workflows/' + WORKFLOW_ID, { name, nodes, connections, settings });
  if (putResult.status === 200 && putResult.data.id) {
    console.log('Update: OK');
    console.log('Name:', putResult.data.name);
  } else {
    console.log('Update FAILED:', JSON.stringify(putResult.data, null, 2).substring(0, 2000));
    return;
  }

  // 3. Reactivate
  console.log('Reactivating workflow...');
  const act = await n8nRequest('POST', '/workflows/' + WORKFLOW_ID + '/activate');
  console.log('Activate:', act.status === 200 ? 'OK' : 'Status ' + act.status);
  console.log('Active:', act.data?.active);

  console.log('Done! Workflow updated and active.');
}

main().catch(console.error);
