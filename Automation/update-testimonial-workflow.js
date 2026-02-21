// Updates the Beta Testimonial Handler workflow in N8N
// Usage: node update-testimonial-workflow.js
// Mode: deactivate -> PUT update -> reactivate (workflow RdkQGJM2qC52qP7e)
//
// Webhook: POST /webhook/beta-testimonial
// Pipeline: Webhook -> Respond OK (parallel) + Extract Data ->
//           Save to Notion + Notify Adrian + Send Thank You Email
// Notion DB: Beta Feedback (30a762ba3bc180beae59ec7eac37d2d1)
// Tagged: testimonial-form, Testimonial Candidate: true
//
// IMPORTANT: This script is the source of truth for this workflow.
// To update Code node logic, edit the jsCode fields in the workflow object below,
// then run: node update-testimonial-workflow.js
// DO NOT edit the workflow directly in the N8N UI without also updating this script.
// Workflow definition last fetched from N8N: 2026-02-20

const N8N_URL = 'https://n8n.beekz.uk/api/v1';
const N8N_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJjNDkyZGQyMy04YTc2LTQ2ODAtOGI3ZC0wMzk0ZGMxOTdiYjkiLCJpc3MiOiJuOG4iLCJhdWQiOiJwdWJsaWMtYXBpIiwianRpIjoiMzU5YzRiYTEtMGRiMy00NDVhLWEzNjMtMjI4YTY3ZjgyNTk2IiwiaWF0IjoxNzcxNDQzODk3fQ.H8iQ3dWfX9CUfLd0wFu79SSOSH71HCiyYZdwmQwUGdk';
const WORKFLOW_ID = 'RdkQGJM2qC52qP7e';

// ==========================================
// WORKFLOW DEFINITION
// To edit Code node logic: find the node by name, update its parameters.jsCode field,
// then run this script to deploy.
// ==========================================
const workflow = {
  "name": "QuickSay Beta Testimonial Handler",
  "nodes": [
    {
      "id": "webhook-testimonial",
      "name": "Beta Testimonial Webhook",
      "type": "n8n-nodes-base.webhook",
      "typeVersion": 2,
      "position": [
        0,
        224
      ],
      "webhookId": "beta-testimonial-wh",
      "parameters": {
        "path": "beta-testimonial",
        "httpMethod": "POST",
        "responseMode": "responseNode",
        "options": {}
      }
    },
    {
      "id": "respond-ok",
      "name": "Respond OK",
      "type": "n8n-nodes-base.respondToWebhook",
      "typeVersion": 1.1,
      "position": [
        240,
        128
      ],
      "parameters": {
        "respondWith": "json",
        "responseBody": "={{ JSON.stringify({ success: true }) }}",
        "options": {}
      }
    },
    {
      "id": "extract-data",
      "name": "Extract Testimonial Data",
      "type": "n8n-nodes-base.set",
      "typeVersion": 3.4,
      "position": [
        240,
        320
      ],
      "parameters": {
        "assignments": {
          "assignments": [
            {
              "id": "name",
              "name": "name",
              "value": "={{ $json.body.name }}",
              "type": "string"
            },
            {
              "id": "email",
              "name": "email",
              "value": "={{ $json.body.email }}",
              "type": "string"
            },
            {
              "id": "testimonialText",
              "name": "testimonialText",
              "value": "={{ $json.body.testimonialText }}",
              "type": "string"
            },
            {
              "id": "testimonialConsent",
              "name": "testimonialConsent",
              "value": "={{ $json.body.testimonialConsent }}",
              "type": "string"
            },
            {
              "id": "timestamp",
              "name": "timestamp",
              "value": "={{ $now.toISO() }}",
              "type": "string"
            }
          ]
        },
        "options": {}
      }
    },
    {
      "id": "save-notion",
      "name": "Save to Notion",
      "type": "n8n-nodes-base.code",
      "typeVersion": 2,
      "position": [
        480,
        224
      ],
      "parameters": {
        "jsCode": "\nconst NOTION_TOKEN = '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';\nconst DB_ID = '30a762ba3bc180beae59ec7eac37d2d1';\nconst d = $('Extract Testimonial Data').item.json;\n\nconst text = (content) => ({ type: 'text', text: { content: content || '' } });\nconst bold = (content) => ({ type: 'text', text: { content: content || '' }, annotations: { bold: true } });\n\nconst children = [];\n\n// Testimonial callout\nchildren.push({\n  object: 'block', type: 'callout',\n  callout: {\n    icon: { type: 'emoji', emoji: '💬' },\n    color: 'green_background',\n    rich_text: [bold('Standalone Testimonial Submission')]\n  }\n});\n\nchildren.push({ object: 'block', type: 'divider', divider: {} });\n\n// About\nchildren.push({\n  object: 'block', type: 'heading_2',\n  heading_2: { rich_text: [text('👤 About')] }\n});\nchildren.push({\n  object: 'block', type: 'paragraph',\n  paragraph: { rich_text: [text(d.name + ' · ' + d.email)] }\n});\n\n// Testimonial\nchildren.push({ object: 'block', type: 'divider', divider: {} });\nchildren.push({\n  object: 'block', type: 'heading_2',\n  heading_2: { rich_text: [text('💬 Testimonial')] }\n});\nchildren.push({\n  object: 'block', type: 'quote',\n  quote: { rich_text: [text('\"' + d.testimonialText + '\"')] }\n});\n\nconst consentLabel = d.testimonialConsent === 'first-name'\n  ? '✅ Consent: Use first name'\n  : '✅ Consent: Keep anonymous';\nchildren.push({\n  object: 'block', type: 'paragraph',\n  paragraph: { rich_text: [{ type: 'text', text: { content: consentLabel }, annotations: { italic: true, color: 'green' } }] }\n});\n\nconst payload = {\n  parent: { database_id: DB_ID },\n  properties: {\n    'Name': { title: [{ text: { content: d.name || '' } }] },\n    'Email': { email: d.email || null },\n    'Testimonial Consent': { checkbox: true },\n    'Testimonial Text': { rich_text: [{ text: { content: (d.testimonialText || '').substring(0, 2000) } }] },\n    'Testimonial Candidate': { checkbox: true },\n    'Submitted': { date: { start: d.timestamp } },\n    'Auto Tags': { multi_select: [{ name: 'testimonial-form' }] }\n  },\n  children: children\n};\n\nconst response = await this.helpers.httpRequest({\n  method: 'POST',\n  url: 'https://api.notion.com/v1/pages',\n  headers: {\n    'Authorization': `Bearer ${NOTION_TOKEN}`,\n    'Content-Type': 'application/json',\n    'Notion-Version': '2022-06-28'\n  },\n  body: payload,\n  json: true\n});\n\nreturn [{ json: response }];\n"
      }
    },
    {
      "id": "notify-adrian",
      "name": "Notify Adrian",
      "type": "n8n-nodes-base.emailSend",
      "typeVersion": 2.1,
      "position": [
        480,
        416
      ],
      "credentials": {
        "smtp": {
          "id": "b5Tw1HSnP7f1QovZ",
          "name": "QuickSay - beta@ SMTP"
        }
      },
      "parameters": {
        "fromEmail": "beta@quicksay.app",
        "toEmail": "say@quicksay.app",
        "subject": "={{ \"New Testimonial from \" + $(\"Extract Testimonial Data\").item.json.name }}",
        "html": "={{ \"<h2>New Testimonial Submitted</h2>\" + \"<p><strong>From:</strong> \" + $(\"Extract Testimonial Data\").item.json.name + \" (\" + $(\"Extract Testimonial Data\").item.json.email + \")</p>\" + \"<p><strong>Credit:</strong> \" + ($(\"Extract Testimonial Data\").item.json.testimonialConsent === \"first-name\" ? \"Use first name\" : \"Keep anonymous\") + \"</p>\" + \"<blockquote style=\\\"border-left:4px solid #22d3c5; padding:12px 16px; margin:16px 0; background:#1a1a1e; color:#f0f0f0; font-size:16px; line-height:1.7;\\\">\" + $(\"Extract Testimonial Data\").item.json.testimonialText + \"</blockquote>\" + \"<p style=\\\"color:#8a8a95; font-size:13px;\\\">Submitted via the standalone testimonial form (Day 14 email).</p>\" }}",
        "options": {
          "appendAttribution": false
        },
        "emailFormat": "html"
      }
    },
    {
      "id": "send-thanks",
      "name": "Send Thank You Email",
      "type": "n8n-nodes-base.emailSend",
      "typeVersion": 2.1,
      "position": [
        480,
        32
      ],
      "credentials": {
        "smtp": {
          "id": "b5Tw1HSnP7f1QovZ",
          "name": "QuickSay - beta@ SMTP"
        }
      },
      "parameters": {
        "fromEmail": "beta@quicksay.app",
        "toEmail": "={{ $(\"Extract Testimonial Data\").item.json.email }}",
        "subject": "Thanks for the kind words!",
        "html": "=<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n  <meta charset=\"UTF-8\" />\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\" />\n  <meta name=\"color-scheme\" content=\"dark\" />\n  <title>Thanks for the kind words!</title>\n</head>\n<body style=\"margin:0; padding:0; background-color:#121214;\">\n  <div style=\"display:none; max-height:0; overflow:hidden;\">Your testimonial means a lot.</div>\n  <table role=\"presentation\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\" width=\"100%\" style=\"background-color:#121214;\">\n    <tr>\n      <td align=\"center\">\n        <table role=\"presentation\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\" width=\"600\" style=\"max-width:600px; width:100%; background-color:#121214;\">\n          <tr>\n            <td align=\"center\" style=\"padding:40px 30px 16px 30px;\">\n              <a href=\"https://quicksay.app\" target=\"_blank\" style=\"text-decoration:none;\">\n                <img src=\"https://quicksay.app/logo-128.png\" alt=\"QuickSay\" width=\"48\" height=\"48\" style=\"display:block; border:0;\" />\n              </a>\n            </td>\n          </tr>\n          <tr>\n            <td align=\"center\" style=\"padding:0 30px 32px 30px;\">\n              <a href=\"https://quicksay.app\" target=\"_blank\" style=\"text-decoration:none; font-family:Arial,Helvetica,sans-serif; font-size:28px; font-weight:700; color:#f0f0f0;\">\n                <span style=\"color:#22d3c5;\">Q</span>uickSay\n              </a>\n            </td>\n          </tr>\n          <tr>\n            <td style=\"padding:0 30px 16px 30px; font-family:Arial,Helvetica,sans-serif; font-size:20px; font-weight:700; color:#f0f0f0; line-height:1.4;\">\n              Hey {{ $(\"Extract Testimonial Data\").item.json.name }},\n            </td>\n          </tr>\n          <tr>\n            <td style=\"padding:0 30px 24px 30px; font-family:Arial,Helvetica,sans-serif; font-size:16px; color:#f0f0f0; line-height:1.7;\">\n              Thank you for sharing your experience with QuickSay. Your testimonial means a lot &mdash; you might be one of the first real voices featured on the website when we launch.\n            </td>\n          </tr>\n          <tr>\n            <td style=\"padding:0 30px 8px 30px; font-family:Arial,Helvetica,sans-serif; font-size:16px; color:#f0f0f0; line-height:1.7;\">\n              If there's anything else you'd like to share, just reply to this email.\n            </td>\n          </tr>\n          <tr>\n            <td style=\"padding:24px 30px 8px 30px; font-family:Arial,Helvetica,sans-serif; font-size:16px; color:#f0f0f0; line-height:1.5;\">\n              &mdash; Adrian\n            </td>\n          </tr>\n          <tr>\n            <td style=\"padding:0 30px 40px 30px; font-family:Arial,Helvetica,sans-serif; font-size:13px; color:#8a8a95; line-height:1.5;\">\n              Solo developer &middot; Alberta, Canada<br />\n              <a href=\"https://quicksay.app\" target=\"_blank\" style=\"color:#22d3c5; text-decoration:none;\">quicksay.app</a>\n            </td>\n          </tr>\n          <tr>\n            <td style=\"padding:0 30px;\">\n              <table role=\"presentation\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\" width=\"100%\">\n                <tr>\n                  <td style=\"border-top:1px solid #2a2a30;\">&nbsp;</td>\n                </tr>\n              </table>\n            </td>\n          </tr>\n          <tr>\n            <td align=\"center\" style=\"padding:20px 30px 40px 30px; font-family:Arial,Helvetica,sans-serif; font-size:12px; color:#5a5a65; line-height:1.6;\">\n              You're receiving this because you submitted a testimonial for the QuickSay beta.<br />\n              <a href=\"https://quicksay.app\" target=\"_blank\" style=\"color:#5a5a65; text-decoration:underline;\">quicksay.app</a>\n            </td>\n          </tr>\n        </table>\n      </td>\n    </tr>\n  </table>\n</body>\n</html>",
        "options": {
          "appendAttribution": false,
          "replyTo": "beta@quicksay.app"
        },
        "emailFormat": "html"
      }
    }
  ],
  "connections": {
    "Beta Testimonial Webhook": {
      "main": [
        [
          {
            "node": "Respond OK",
            "type": "main",
            "index": 0
          },
          {
            "node": "Extract Testimonial Data",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Extract Testimonial Data": {
      "main": [
        [
          {
            "node": "Save to Notion",
            "type": "main",
            "index": 0
          },
          {
            "node": "Notify Adrian",
            "type": "main",
            "index": 0
          },
          {
            "node": "Send Thank You Email",
            "type": "main",
            "index": 0
          }
        ]
      ]
    }
  },
  "settings": {
    "executionOrder": "v1",
    "callerPolicy": "workflowsFromSameOwner",
    "availableInMCP": false
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
        try { resolve({ status: res.statusCode, data: JSON.parse(data) }); }
        catch (e) { resolve({ status: res.statusCode, data: data.substring(0, 2000) }); }
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
