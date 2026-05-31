// Updates the Beta Email Sequence workflow in N8N
// Usage: node update-email-sequence.js
// Mode: deactivate -> PUT update -> reactivate (workflow EC4Fzts88a2dSB7q)
//
// Changes:
//   v1: Use Case property switched from rich_text to select (Notion DB optimization)
//       Mapping: general/other -> General, writing -> Writing / Blogging, coding -> Code / Development,
//                accessibility -> Accessibility
//   v2: Added email -> Email / Communication, notes -> Notes / Documentation mappings (Issue #2)
//       Added null safety to Update Stage when Notion save fails (Issue #3)
//   v3: Error isolation -- Send Welcome Email now runs in parallel with Save to Notion (Issue #1)
//       Email fires even if Notion is down. Update Stage to 1 still depends on Notion (needs page ID).

const N8N_URL = 'https://n8n.beekz.uk/api/v1';
const N8N_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJjNDkyZGQyMy04YTc2LTQ2ODAtOGI3ZC0wMzk0ZGMxOTdiYjkiLCJpc3MiOiJuOG4iLCJhdWQiOiJwdWJsaWMtYXBpIiwianRpIjoiMzU5YzRiYTEtMGRiMy00NDVhLWEzNjMtMjI4YTY3ZjgyNTk2IiwiaWF0IjoxNzcxNDQzODk3fQ.H8iQ3dWfX9CUfLd0wFu79SSOSH71HCiyYZdwmQwUGdk';
const WORKFLOW_ID = 'EC4Fzts88a2dSB7q';

// --- Constants embedded in Code nodes ---
const NOTION_TOKEN = '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';
const SIGNUPS_DB_ID = '571a51b1a860406b99d68ded2be2226c';

// ==========================================
// CODE NODE: Save to Notion (UPDATED — Use Case: select)
// ==========================================
const saveToNotionCode = `const NOTION_TOKEN = '${NOTION_TOKEN}';
const DB_ID = '${SIGNUPS_DB_ID}';
const d = $('Extract Signup Data').item.json;

function mapUseCase(raw) {
  const map = {
    'writing': 'Writing / Blogging',
    'coding': 'Code / Development',
    'accessibility': 'Accessibility',
    'email': 'Email / Communication',
    'notes': 'Notes / Documentation',
    'general': 'General',
    'other': 'General'
  };
  return map[(raw || '').toLowerCase()] || 'General';
}

const payload = {
  parent: { database_id: DB_ID },
  properties: {
    'Name': { title: [{ text: { content: d.name || '' } }] },
    'Email': { email: d.email || null },
    'Use Case': { select: { name: mapUseCase(d.useCase) } },
    'Windows Version': { rich_text: [{ text: { content: (d.windowsVersion || '').substring(0, 2000) } }] },
    'Source': { select: { name: d.source || 'website-beta-form' } },
    'Submitted': { date: { start: d.timestamp } },
    'Email Stage': { number: 0 }
  }
};
const response = await this.helpers.httpRequest({
  method: 'POST', url: 'https://api.notion.com/v1/pages',
  headers: {
    'Authorization': 'Bearer ' + NOTION_TOKEN,
    'Content-Type': 'application/json',
    'Notion-Version': '2022-06-28'
  },
  body: payload, json: true
});
return [{ json: response }];`;

// ==========================================
// CODE NODE: Update Stage to 1 (unchanged)
// ==========================================
const updateStageCode = `const pageId = $('Save to Notion').item.json.id;
const NOTION_TOKEN = '${NOTION_TOKEN}';

if (!pageId) {
  // Notion save failed upstream (continueOnFail active) -- nothing to update
  return [{ json: { success: false, reason: 'No Notion page ID -- save may have failed' } }];
}

const response = await this.helpers.httpRequest({
  method: 'PATCH',
  url: 'https://api.notion.com/v1/pages/' + pageId,
  headers: {
    'Authorization': 'Bearer ' + NOTION_TOKEN,
    'Content-Type': 'application/json',
    'Notion-Version': '2022-06-28'
  },
  body: {
    properties: {
      'Email Stage': { number: 1 }
    }
  },
  json: true
});

return [{ json: response }];`;

// ==========================================
// Welcome email HTML (verbatim from live workflow)
// N8N expression prefix "=" tells N8N to evaluate {{ }} expressions
// ==========================================
const welcomeEmailHtml = `=<!--
  QuickSay Beta Welcome Email
  Subject: You're in - QuickSay Beta Access
  From: Adrian <beta@quicksay.app>

  Target clients: Gmail (web + mobile), Outlook (desktop + web + mobile), Apple Mail (macOS + iOS)
  Layout: table-based, all styles inline, max-width 600px
  Dark theme: #121214 background, #f0f0f0 text, #22d3c5 accent teal, #ff783c accent orange
  Fonts: Arial, Helvetica, sans-serif (web-safe fallbacks for Outfit / DM Sans)
-->
<!DOCTYPE html>
<html lang="en" xmlns="http://www.w3.org/1999/xhtml" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <meta http-equiv="X-UA-Compatible" content="IE=edge" />
  <meta name="color-scheme" content="dark" />
  <meta name="supported-color-schemes" content="dark" />
  <title>You're in \\u2014 QuickSay Beta Access</title>
  <!--[if mso]>
  <noscript>
    <xml>
      <o:OfficeDocumentSettings>
        <o:PixelsPerInch>96</o:PixelsPerInch>
      </o:OfficeDocumentSettings>
    </xml>
  </noscript>
  <![endif]-->
</head>
<body style="margin:0; padding:0; background-color:#121214; -webkit-text-size-adjust:100%; -ms-text-size-adjust:100%;">

  <!-- Preheader text (hidden, shown in inbox preview) -->
  <div style="display:none; max-height:0; overflow:hidden; mso-hide:all;">
    Welcome to the QuickSay beta! Here's everything you need to get started.
  </div>

  <!-- Outer wrapper table -->
  <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="background-color:#121214;">
    <tr>
      <td align="center" style="padding:0;">

        <!-- Inner container: 600px max -->
        <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="600" style="max-width:600px; width:100%; background-color:#121214;">

          <!-- Logo / Header -->
          <tr>
            <td align="center" style="padding:40px 30px 16px 30px;">
              <a href="https://quicksay.app" target="_blank" style="text-decoration:none;">
                <img src="https://quicksay.app/logo-128.png" alt="QuickSay" width="48" height="48" style="display:block; border:0; outline:none;" />
              </a>
            </td>
          </tr>
          <tr>
            <td align="center" style="padding:0 30px 24px 30px;">
              <a href="https://quicksay.app" target="_blank" style="text-decoration:none; font-family:Arial,Helvetica,sans-serif; font-size:28px; font-weight:700; color:#f0f0f0; letter-spacing:-0.5px;">
                <span style="color:#22d3c5;">Q</span>uickSay
              </a>
            </td>
          </tr>

          <!-- Beta badge -->
          <tr>
            <td align="center" style="padding:0 30px 32px 30px;">
              <table role="presentation" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td style="font-family:'Courier New',Courier,monospace; font-size:11px; font-weight:700; color:#22d3c5; text-transform:uppercase; letter-spacing:2px; border:1px solid rgba(34,211,197,0.3); border-radius:20px; padding:6px 16px;">
                    Beta Access
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- Greeting -->
          <tr>
            <td style="padding:0 30px 16px 30px; font-family:Arial,Helvetica,sans-serif; font-size:20px; font-weight:700; color:#f0f0f0; line-height:1.4;">
              Hey {{ $('Extract Signup Data').item.json.name }},
            </td>
          </tr>

          <!-- Body copy -->
          <tr>
            <td style="padding:0 30px 24px 30px; font-family:Arial,Helvetica,sans-serif; font-size:16px; color:#f0f0f0; line-height:1.7;">
              Welcome to the QuickSay beta! You're one of the first people to test what I've been building &mdash; a voice-to-text app for Windows that actually works everywhere you type.
            </td>
          </tr>

          <tr>
            <td style="padding:0 30px 32px 30px; font-family:Arial,Helvetica,sans-serif; font-size:16px; color:#f0f0f0; line-height:1.7;">
              Here's everything you need to get started:
            </td>
          </tr>

          <!-- CTA 1: Download QuickSay -->
          <tr>
            <td align="center" style="padding:0 30px 8px 30px;">
              <table role="presentation" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td align="center" style="border-radius:8px; background-color:#22d3c5;">
                    <a href="https://quicksay.app/downloads/QuickSay-Setup.exe" target="_blank" style="background-color:#22d3c5; color:#121214; font-family:Arial,Helvetica,sans-serif; font-weight:700; text-decoration:none; padding:14px 32px; border-radius:8px; display:inline-block; font-size:16px; line-height:1.4; mso-padding-alt:0; text-align:center;">
                      <!--[if mso]><i style="mso-font-width:300%; mso-text-raise:21pt;" hidden>&emsp;</i><![endif]-->
                      <span style="mso-text-raise:10pt;">Download QuickSay</span>
                      <!--[if mso]><i style="mso-font-width:300%;" hidden>&emsp;&#8203;</i><![endif]-->
                    </a>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td align="center" style="padding:0 30px 28px 30px; font-family:Arial,Helvetica,sans-serif; font-size:13px; color:#8a8a95; line-height:1.5;">
              ~105 MB &middot; Windows 10/11 &middot; No bloat, no background services
            </td>
          </tr>

          <!-- CTA 2: Getting Started Guide -->
          <tr>
            <td align="center" style="padding:0 30px 8px 30px;">
              <table role="presentation" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td align="center" style="border-radius:8px; border:2px solid #8a8a95;">
                    <a href="https://quicksay.app/beta/getting-started" target="_blank" style="background-color:transparent; color:#f0f0f0; font-family:Arial,Helvetica,sans-serif; font-weight:700; text-decoration:none; padding:12px 28px; border-radius:8px; display:inline-block; font-size:15px; line-height:1.4;">
                      Getting Started Guide
                    </a>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td align="center" style="padding:0 30px 28px 30px; font-family:Arial,Helvetica,sans-serif; font-size:13px; color:#8a8a95; line-height:1.5;">
              Install, connect your free AI account, and start dictating in under 5 minutes.
            </td>
          </tr>

          <!-- CTA 3: Share Your Feedback -->
          <tr>
            <td align="center" style="padding:0 30px 8px 30px;">
              <table role="presentation" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td align="center" style="border-radius:8px; border:2px solid #8a8a95;">
                    <a href="https://quicksay.app/beta/feedback" target="_blank" style="background-color:transparent; color:#f0f0f0; font-family:Arial,Helvetica,sans-serif; font-weight:700; text-decoration:none; padding:12px 28px; border-radius:8px; display:inline-block; font-size:15px; line-height:1.4;">
                      Share Your Feedback
                    </a>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td align="center" style="padding:0 30px 36px 30px; font-family:Arial,Helvetica,sans-serif; font-size:13px; color:#8a8a95; line-height:1.5;">
              After you've used QuickSay for a day or two, fill out the feedback form (~5 minutes).
            </td>
          </tr>

          <!-- Divider -->
          <tr>
            <td style="padding:0 30px;">
              <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%">
                <tr>
                  <td style="border-top:1px solid #2a2a30; font-size:1px; line-height:1px;">&nbsp;</td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- What to expect section -->
          <tr>
            <td style="padding:28px 30px 12px 30px; font-family:Arial,Helvetica,sans-serif; font-size:14px; font-weight:700; color:#22d3c5; text-transform:uppercase; letter-spacing:1.5px;">
              What to Expect
            </td>
          </tr>
          <tr>
            <td style="padding:0 30px 6px 46px; font-family:Arial,Helvetica,sans-serif; font-size:15px; color:#f0f0f0; line-height:1.8;">
              &bull;&nbsp; The beta runs for ~2-3 weeks before launch
            </td>
          </tr>
          <tr>
            <td style="padding:0 30px 6px 46px; font-family:Arial,Helvetica,sans-serif; font-size:15px; color:#f0f0f0; line-height:1.8;">
              &bull;&nbsp; QuickSay is yours to keep &mdash; no expiration, no catch
            </td>
          </tr>
          <tr>
            <td style="padding:0 30px 6px 46px; font-family:Arial,Helvetica,sans-serif; font-size:15px; color:#f0f0f0; line-height:1.8;">
              &bull;&nbsp; You'll be one of the first real users featured on the site
            </td>
          </tr>
          <tr>
            <td style="padding:0 30px 28px 46px; font-family:Arial,Helvetica,sans-serif; font-size:15px; color:#f0f0f0; line-height:1.8;">
              &bull;&nbsp; I personally read every piece of feedback
            </td>
          </tr>

          <!-- Divider -->
          <tr>
            <td style="padding:0 30px;">
              <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%">
                <tr>
                  <td style="border-top:1px solid #2a2a30; font-size:1px; line-height:1px;">&nbsp;</td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- Reply prompt -->
          <tr>
            <td style="padding:28px 30px 8px 30px; font-family:Arial,Helvetica,sans-serif; font-size:16px; color:#f0f0f0; line-height:1.7;">
              If you run into ANY issues, reply to this email &mdash; I read everything.
            </td>
          </tr>

          <!-- Sign-off -->
          <tr>
            <td style="padding:24px 30px 8px 30px; font-family:Arial,Helvetica,sans-serif; font-size:16px; color:#f0f0f0; line-height:1.5;">
              &mdash; Adrian
            </td>
          </tr>
          <tr>
            <td style="padding:0 30px 40px 30px; font-family:Arial,Helvetica,sans-serif; font-size:13px; color:#8a8a95; line-height:1.5;">
              Solo developer &middot; Alberta, Canada<br />
              <a href="https://quicksay.app" target="_blank" style="color:#22d3c5; text-decoration:none;">quicksay.app</a>
            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td style="padding:0 30px;">
              <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%">
                <tr>
                  <td style="border-top:1px solid #2a2a30; font-size:1px; line-height:1px;">&nbsp;</td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td align="center" style="padding:20px 30px 40px 30px; font-family:Arial,Helvetica,sans-serif; font-size:12px; color:#5a5a65; line-height:1.6;">
              You're receiving this because you signed up for the QuickSay beta.<br />
              <a href="https://quicksay.app" target="_blank" style="color:#5a5a65; text-decoration:underline;">quicksay.app</a>
            </td>
          </tr>

        </table>
        <!-- /Inner container -->

      </td>
    </tr>
  </table>
  <!-- /Outer wrapper -->

<!--
PLAIN TEXT VERSION:
==================

Subject: You're in - QuickSay Beta Access

Hey {{ $('Extract Signup Data').item.json.name }},

Welcome to the QuickSay beta! You're one of the first people to test what I've been building - a voice-to-text app for Windows that actually works everywhere you type.

Here's everything you need to get started:

DOWNLOAD QUICKSAY
https://quicksay.app/downloads/QuickSay-Setup.exe
~105 MB - Windows 10/11 - No bloat, no background services

GETTING STARTED GUIDE
https://quicksay.app/beta/getting-started
Install, connect your free AI account, and start dictating in under 5 minutes.

SHARE YOUR FEEDBACK
https://quicksay.app/beta/feedback
After you've used QuickSay for a day or two, fill out the feedback form (~5 minutes).

WHAT TO EXPECT:
- The beta runs for ~2-3 weeks before launch
- QuickSay is yours to keep - no expiration, no catch
- You'll be one of the first real users featured on the site
- I personally read every piece of feedback

If you run into ANY issues, reply to this email - I read everything.

- Adrian
Solo developer - Alberta, Canada
quicksay.app
-->

</body>
</html>
`;

// ==========================================
// WORKFLOW DEFINITION
// ==========================================
const workflow = {
  name: 'QuickSay Beta Email Sequence (SMTP)',
  nodes: [
    // Node 1: Webhook trigger
    {
      parameters: {
        httpMethod: 'POST',
        path: 'beta-signup',
        responseMode: 'responseNode',
        options: {}
      },
      id: 'webhook-trigger-smtp',
      name: 'Beta Signup Webhook',
      type: 'n8n-nodes-base.webhook',
      typeVersion: 2,
      position: [0, 208],
      webhookId: 'beta-signup'
    },
    // Node 2: Respond OK (immediate)
    {
      parameters: {
        respondWith: 'json',
        responseBody: '={{ JSON.stringify({ success: true }) }}',
        options: {}
      },
      id: 'respond-ok-smtp',
      name: 'Respond OK',
      type: 'n8n-nodes-base.respondToWebhook',
      typeVersion: 1.1,
      position: [224, 112]
    },
    // Node 3: Extract Signup Data
    {
      parameters: {
        assignments: {
          assignments: [
            { id: 'name', name: 'name', value: '={{ $json.body.name }}', type: 'string' },
            { id: 'email', name: 'email', value: '={{ $json.body.email }}', type: 'string' },
            { id: 'useCase', name: 'useCase', value: '={{ $json.body.useCase || "" }}', type: 'string' },
            { id: 'windowsVersion', name: 'windowsVersion', value: '={{ $json.body.windowsVersion || "" }}', type: 'string' },
            { id: 'timestamp', name: 'timestamp', value: '={{ $now.toISO() }}', type: 'string' }
          ]
        },
        options: {}
      },
      id: 'set-data-smtp',
      name: 'Extract Signup Data',
      type: 'n8n-nodes-base.set',
      typeVersion: 3.4,
      position: [224, 304]
    },
    // Node 4: Save to Notion (UPDATED — Use Case: select instead of rich_text)
    {
      parameters: {
        jsCode: saveToNotionCode,
        options: {}
      },
      id: 'notion-save-signup',
      name: 'Save to Notion',
      type: 'n8n-nodes-base.code',
      typeVersion: 2,
      position: [448, 112],
      continueOnFail: true
    },
    // Node 5: Send Welcome Email
    // v3: Now parallel to Save to Notion — triggered directly from Extract Signup Data.
    // Email fires regardless of Notion success/failure.
    {
      parameters: {
        fromEmail: 'beta@quicksay.app',
        toEmail: "={{ $('Extract Signup Data').item.json.email }}",
        subject: "You\u2019re in \u2014 QuickSay Beta Access",
        emailFormat: 'html',
        html: welcomeEmailHtml,
        options: {
          replyTo: 'beta@quicksay.app',
          appendAttribution: false
        }
      },
      id: 'smtp-welcome',
      name: 'Send Welcome Email',
      type: 'n8n-nodes-base.emailSend',
      typeVersion: 2.1,
      position: [448, 368],
      webhookId: '69159307-8d4b-47bb-8a49-cf3648a74557',
      credentials: {
        smtp: {
          id: 'b5Tw1HSnP7f1QovZ',
          name: 'QuickSay - beta@ SMTP'
        }
      }
    },
    // Node 6: Update Stage to 1
    // Stays downstream of Save to Notion only — needs the Notion page ID.
    {
      parameters: {
        jsCode: updateStageCode,
        options: {}
      },
      id: 'update-stage-1',
      name: 'Update Stage to 1',
      type: 'n8n-nodes-base.code',
      typeVersion: 2,
      position: [672, 112]
    }
  ],
  connections: {
    'Beta Signup Webhook': {
      main: [[
        { node: 'Respond OK', type: 'main', index: 0 },
        { node: 'Extract Signup Data', type: 'main', index: 0 }
      ]]
    },
    // v3: Extract Signup Data fans out to both Notion save and email in parallel.
    // Email no longer waits for Notion — fires immediately after data extraction.
    'Extract Signup Data': {
      main: [[
        { node: 'Save to Notion', type: 'main', index: 0 },
        { node: 'Send Welcome Email', type: 'main', index: 0 }
      ]]
    },
    // Update Stage stays downstream of Notion only (needs the page ID).
    'Save to Notion': {
      main: [[{ node: 'Update Stage to 1', type: 'main', index: 0 }]]
    }
    // Send Welcome Email is now terminal — no downstream nodes.
  },
  settings: {
    executionOrder: 'v1'
  }
};

// ==========================================
// UPDATE WORKFLOW VIA API
// ==========================================

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
    console.log('Update: OK (' + putResult.data.nodes.length + ' nodes)');
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
