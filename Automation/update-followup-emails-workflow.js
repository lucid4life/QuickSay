// Updates the Beta Follow-Up Emails workflow in N8N
// Usage: node update-followup-emails-workflow.js
// Mode: deactivate -> PUT update -> reactivate (workflow EA49TPho6MH1kWN5)
//
// Trigger: Scheduled every 4 hours
// Pipeline: Schedule -> Prepare Due Emails (queries Notion, computes due) ->
//           Build Email HTML (day1/day3/day7/day14 templates) ->
//           Send Follow-Up Email -> Update Notion Stage
// Notion DB: Beta Signups (571a51b1a860406b99d68ded2be2226c)
// Email stages: 1->2 (day 1), 2->3 (day 3), 3->4 (day 7), 4->5 (day 14)
// Day 14 email links to /beta/testimonial page
//
// IMPORTANT: This script is the source of truth for this workflow.
// To update Code node logic, edit the jsCode fields in the workflow object below,
// then run: node update-followup-emails-workflow.js
// DO NOT edit the workflow directly in the N8N UI without also updating this script.
// Workflow definition last fetched from N8N: 2026-02-20

const N8N_URL = 'https://n8n.beekz.uk/api/v1';
const N8N_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJjNDkyZGQyMy04YTc2LTQ2ODAtOGI3ZC0wMzk0ZGMxOTdiYjkiLCJpc3MiOiJuOG4iLCJhdWQiOiJwdWJsaWMtYXBpIiwianRpIjoiMzU5YzRiYTEtMGRiMy00NDVhLWEzNjMtMjI4YTY3ZjgyNTk2IiwiaWF0IjoxNzcxNDQzODk3fQ.H8iQ3dWfX9CUfLd0wFu79SSOSH71HCiyYZdwmQwUGdk';
const WORKFLOW_ID = 'EA49TPho6MH1kWN5';

// ==========================================
// WORKFLOW DEFINITION
// To edit Code node logic: find the node by name, update its parameters.jsCode field,
// then run this script to deploy.
// ==========================================
const workflow = {
  "name": "QuickSay Beta Follow-Up Emails",
  "nodes": [
    {
      "parameters": {
        "rule": {
          "interval": [
            {
              "field": "hours",
              "hoursInterval": 4
            }
          ]
        }
      },
      "id": "schedule-trigger",
      "name": "Run Every 4 Hours",
      "type": "n8n-nodes-base.scheduleTrigger",
      "typeVersion": 1.2,
      "position": [
        0,
        208
      ]
    },
    {
      "parameters": {
        "jsCode": "\nconst NOTION_TOKEN = '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';\nconst DB_ID = '571a51b1a860406b99d68ded2be2226c';\n\n// Query Notion for contacts with Email Stage 1-4\nconst response = await this.helpers.httpRequest({\n  method: 'POST',\n  url: 'https://api.notion.com/v1/databases/' + DB_ID + '/query',\n  headers: {\n    'Authorization': 'Bearer ' + NOTION_TOKEN,\n    'Content-Type': 'application/json',\n    'Notion-Version': '2022-06-28'\n  },\n  body: {\n    filter: {\n      and: [\n        { property: 'Email Stage', number: { greater_than_or_equal_to: 1 } },\n        { property: 'Email Stage', number: { less_than_or_equal_to: 4 } }\n      ]\n    }\n  },\n  json: true\n});\n\nconst pages = response.results || [];\nconst now = new Date();\nconst results = [];\n\n// Email schedule: stage -> {daysRequired, newStage, subject, emailKey}\nconst schedule = [\n  { fromStage: 1, daysRequired: 1, newStage: 2, subject: \"How's QuickSay working for you?\", emailKey: 'day1' },\n  { fromStage: 2, daysRequired: 3, newStage: 3, subject: 'Tried anything surprising yet?', emailKey: 'day3' },\n  { fromStage: 3, daysRequired: 7, newStage: 4, subject: \"6 things most QuickSay users don't find on their own\", emailKey: 'day7' },\n  { fromStage: 4, daysRequired: 14, newStage: 5, subject: 'Quick favor — would you vouch for QuickSay?', emailKey: 'day14' }\n];\n\nfor (const page of pages) {\n  const props = page.properties;\n  const name = props.Name?.title?.[0]?.plain_text || 'there';\n  const email = props.Email?.email;\n  const stage = props['Email Stage']?.number;\n  const submitted = props.Submitted?.date?.start;\n\n  if (!email || !stage || !submitted) continue;\n\n  const submittedDate = new Date(submitted);\n  const daysSinceSignup = (now - submittedDate) / (1000 * 60 * 60 * 24);\n\n  const entry = schedule.find(s => s.fromStage === stage);\n  if (!entry) continue;\n  if (daysSinceSignup < entry.daysRequired) continue;\n\n  // This contact is due for their next email\n  results.push({\n    json: {\n      name,\n      email,\n      subject: entry.subject,\n      emailKey: entry.emailKey,\n      newStage: entry.newStage,\n      pageId: page.id\n    }\n  });\n}\n\nreturn results;\n",
        "options": {}
      },
      "id": "prepare-due-emails",
      "name": "Prepare Due Emails",
      "type": "n8n-nodes-base.code",
      "typeVersion": 2,
      "position": [
        224,
        208
      ]
    },
    {
      "parameters": {
        "jsCode": "\nconst { name, emailKey } = $input.item.json;\n\n// ── Shared parts ──\nconst hdr = (title, preheader) => `<!--\n  QuickSay Beta Email\n  From: Adrian <beta@quicksay.app>\n-->\n<!DOCTYPE html>\n<html lang=\"en\" xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:v=\"urn:schemas-microsoft-com:vml\" xmlns:o=\"urn:schemas-microsoft-com:office:office\">\n<head>\n  <meta charset=\"UTF-8\" />\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\" />\n  <meta http-equiv=\"X-UA-Compatible\" content=\"IE=edge\" />\n  <meta name=\"color-scheme\" content=\"dark\" />\n  <meta name=\"supported-color-schemes\" content=\"dark\" />\n  <title>${title}</title>\n  <!--[if mso]>\n  <noscript><xml><o:OfficeDocumentSettings><o:PixelsPerInch>96</o:PixelsPerInch></o:OfficeDocumentSettings></xml></noscript>\n  <![endif]-->\n</head>\n<body style=\"margin:0; padding:0; background-color:#121214; -webkit-text-size-adjust:100%; -ms-text-size-adjust:100%;\">\n  <div style=\"display:none; max-height:0; overflow:hidden; mso-hide:all;\">${preheader}</div>\n  <table role=\"presentation\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\" width=\"100%\" style=\"background-color:#121214;\">\n    <tr><td align=\"center\" style=\"padding:0;\">\n        <table role=\"presentation\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\" width=\"600\" style=\"max-width:600px; width:100%; background-color:#121214;\">\n          <tr><td align=\"center\" style=\"padding:40px 30px 16px 30px;\"><a href=\"https://quicksay.app\" target=\"_blank\" style=\"text-decoration:none;\"><img src=\"https://quicksay.app/logo-128.png\" alt=\"QuickSay\" width=\"48\" height=\"48\" style=\"display:block; border:0; outline:none;\" /></a></td></tr>\n          <tr><td align=\"center\" style=\"padding:0 30px 32px 30px;\"><a href=\"https://quicksay.app\" target=\"_blank\" style=\"text-decoration:none; font-family:Arial,Helvetica,sans-serif; font-size:28px; font-weight:700; color:#f0f0f0; letter-spacing:-0.5px;\"><span style=\"color:#22d3c5;\">Q</span>uickSay</a></td></tr>`;\n\nconst greet = `\n          <tr><td style=\"padding:0 30px 16px 30px; font-family:Arial,Helvetica,sans-serif; font-size:20px; font-weight:700; color:#f0f0f0; line-height:1.4;\">Hey ${name},</td></tr>`;\n\nconst p = (text) => `\n          <tr><td style=\"padding:0 30px 24px 30px; font-family:Arial,Helvetica,sans-serif; font-size:16px; color:#f0f0f0; line-height:1.7;\">${text}</td></tr>`;\n\nconst signoff = `\n          <tr><td style=\"padding:24px 30px 8px 30px; font-family:Arial,Helvetica,sans-serif; font-size:16px; color:#f0f0f0; line-height:1.5;\">&mdash; Adrian</td></tr>\n          <tr><td style=\"padding:0 30px 40px 30px; font-family:Arial,Helvetica,sans-serif; font-size:13px; color:#8a8a95; line-height:1.5;\">Solo developer &middot; Alberta, Canada<br /><a href=\"https://quicksay.app\" target=\"_blank\" style=\"color:#22d3c5; text-decoration:none;\">quicksay.app</a></td></tr>\n          <tr><td style=\"padding:0 30px;\"><table role=\"presentation\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\" width=\"100%\"><tr><td style=\"border-top:1px solid #2a2a30; font-size:1px; line-height:1px;\">&nbsp;</td></tr></table></td></tr>\n          <tr><td align=\"center\" style=\"padding:20px 30px 40px 30px; font-family:Arial,Helvetica,sans-serif; font-size:12px; color:#5a5a65; line-height:1.6;\">You're receiving this because you signed up for the QuickSay beta.<br /><a href=\"https://quicksay.app\" target=\"_blank\" style=\"color:#5a5a65; text-decoration:underline;\">quicksay.app</a></td></tr>\n        </table></td></tr></table>\n</body></html>`;\n\nconst div = `\n          <tr><td style=\"padding:0 30px;\"><table role=\"presentation\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\" width=\"100%\"><tr><td style=\"border-top:1px solid #2a2a30; font-size:1px; line-height:1px;\">&nbsp;</td></tr></table></td></tr>`;\n\nconst bullet = (text, last) => `\n          <tr><td style=\"padding:0 30px ${last ? '28px' : '6px'} 46px; font-family:Arial,Helvetica,sans-serif; font-size:15px; color:#f0f0f0; line-height:1.8;\">&bull;&nbsp;${text}</td></tr>`;\n\nconst ctaPrimary = (href, label) => `\n          <tr><td align=\"center\" style=\"padding:0 30px 32px 30px;\"><table role=\"presentation\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\"><tr><td align=\"center\" style=\"border-radius:8px; background-color:#22d3c5;\"><a href=\"${href}\" target=\"_blank\" style=\"background-color:#22d3c5; color:#121214; font-family:Arial,Helvetica,sans-serif; font-weight:700; text-decoration:none; padding:14px 32px; border-radius:8px; display:inline-block; font-size:16px; line-height:1.4;\">${label}</a></td></tr></table></td></tr>`;\n\nconst ctaSecondary = (href, label) => `\n          <tr><td align=\"center\" style=\"padding:0 30px 28px 30px;\"><table role=\"presentation\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\"><tr><td align=\"center\" style=\"border-radius:8px; border:2px solid #8a8a95;\"><a href=\"${href}\" target=\"_blank\" style=\"background-color:transparent; color:#f0f0f0; font-family:Arial,Helvetica,sans-serif; font-weight:700; text-decoration:none; padding:12px 28px; border-radius:8px; display:inline-block; font-size:15px; line-height:1.4;\">${label}</a></td></tr></table></td></tr>`;\n\nconst callout = (text) => `\n          <tr><td style=\"padding:0 30px 24px 30px;\"><table role=\"presentation\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\" width=\"100%\" style=\"background-color:#1c1c20; border-radius:8px; border-left:3px solid #22d3c5;\"><tr><td style=\"padding:20px 24px; font-family:Arial,Helvetica,sans-serif; font-size:15px; color:#f0f0f0; line-height:1.7;\">${text}</td></tr></table></td></tr>`;\n\nconst tip = (title, desc) => `\n          <tr><td style=\"padding:0 30px 16px 30px;\"><table role=\"presentation\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\" width=\"100%\" style=\"background-color:#1c1c20; border-radius:8px; border-left:3px solid #22d3c5;\"><tr><td style=\"padding:20px 24px;\"><span style=\"font-family:Arial,Helvetica,sans-serif; font-size:15px; font-weight:700; color:#22d3c5; line-height:1.5;\">${title}</span><br /><span style=\"font-family:Arial,Helvetica,sans-serif; font-size:15px; color:#f0f0f0; line-height:1.7;\">${desc}</span></td></tr></table></td></tr>`;\n\nlet htmlBody = '';\n\nif (emailKey === 'day1') {\n  htmlBody = hdr(\"How's QuickSay working for you?\", \"Quick check-in — were you able to get set up okay?\")\n    + greet\n    + p(\"You downloaded QuickSay yesterday &mdash; how's it going?\")\n    + '<tr><td style=\"padding:0 30px 8px 30px; font-family:Arial,Helvetica,sans-serif; font-size:16px; font-weight:700; color:#f0f0f0; line-height:1.5;\">Quick questions:</td></tr>'\n    + bullet('Were you able to get set up okay?', false)\n    + bullet('Have you run into any issues?', false)\n    + bullet('Is there anything confusing or unclear?', true)\n    + p(\"If you haven't had a chance to try it yet, no worries &mdash; here's the getting started guide:\")\n    + ctaSecondary('https://quicksay.app/beta/getting-started', 'Getting Started Guide')\n    + p(\"And when you're ready, the feedback form is here:\")\n    + ctaPrimary('https://quicksay.app/beta/feedback', 'Share Your Feedback')\n    + div\n    + p(\"Your feedback matters &mdash; I'm making changes daily based on what beta testers tell me.\")\n    + signoff;\n}\nelse if (emailKey === 'day3') {\n  htmlBody = hdr(\"Tried anything surprising yet?\", \"A few days in — curious how it's going\")\n    + greet\n    + p(\"You've had QuickSay for a few days now. I'm curious &mdash; have you tried it in anything beyond the first app you tested?\")\n    + p(\"A lot of people start with one app and don't realize it works literally everywhere. Try dictating into your email client, Slack, a Google Doc, a code editor &mdash; it works in all of them.\")\n    + p(\"The thing that surprised me most when building it was how different dictation feels in different contexts. Writing an email feels natural. Dictating code comments feels weird at first, then kind of amazing. Slack messages come out sounding more like you actually talk.\")\n    + p(\"So &mdash; how's it going? Anything work better or worse than you expected?\")\n    + p(\"Just hit reply and let me know. Even a one-liner helps me understand how people actually use this thing.\")\n    + signoff;\n}\nelse if (emailKey === 'day7') {\n  htmlBody = hdr(\"6 things most QuickSay users don't find on their own\", \"Hidden features that make dictation way more useful\")\n    + greet\n    + p(\"You've been using QuickSay for about a week now &mdash; which means you probably know the basics. But there are a few things buried in the settings that most people don't find on their own.\")\n    + p(\"Here are 6 that are worth knowing about:\")\n    + tip('Sticky Mode', \"Keeps listening continuously instead of stopping when you release the hotkey. Great for longer dictation &mdash; turn it on in Settings under Hotkey Mode.\")\n    + tip('Floating Widget', \"A small always-visible overlay that shows recording status. No need to alt-tab to check if it's listening. Enable it in Settings &gt; Widget.\")\n    + tip('Dictation History', \"Every transcription is saved locally. If a paste ever fails or you need to grab something from earlier, open Settings &gt; History. It's all there.\")\n    + tip('Smart Modes', \"Code, Email, Casual, and Standard &mdash; each cleans up your dictation differently. Try Code mode in VS Code. It formats variable names and syntax automatically.\")\n    + tip('Custom Dictionary', \"Got jargon, names, or acronyms that keep getting transcribed wrong? Add them to your custom dictionary in Settings. QuickSay will get them right every time.\")\n    + tip('Usage Dashboard', \"Curious how much you've used QuickSay? The dashboard shows total transcriptions, words dictated, and estimated time saved. It's in Settings &gt; Stats.\")\n    + p(\"If any of these don't work as expected, or if you find something else that could be better &mdash; reply to this email. I fix things fast.\")\n    + signoff;\n}\nelse if (emailKey === 'day14') {\n  htmlBody = hdr(\"Quick favor — would you vouch for QuickSay?\", \"You'd be one of the first real voices on the QuickSay website.\")\n    + greet\n    + p(\"You've been using QuickSay for a couple weeks now, and I hope it's been useful.\")\n    + p(\"I'm getting ready to launch publicly on March 31, and here's the thing &mdash; every testimonial on the website right now is a placeholder. You'd literally be one of the first real voices on the site.\")\n    + callout(\"Genuine testimonials from real users make a huge difference for a solo developer competing against well-funded alternatives like Wispr Flow and Aqua Voice.\")\n    + p(\"If QuickSay has helped you, would you mind sharing a quick 1-2 sentence testimonial I can feature on the website?\")\n    + ctaPrimary('https://quicksay.app/beta/testimonial', 'Share a Testimonial')\n    + div\n    + p(\"Totally optional &mdash; no pressure at all. And if there's something I should fix first, tell me that too.\")\n    + '<tr><td style=\"padding:0 30px 8px 30px; font-family:Arial,Helvetica,sans-serif; font-size:16px; color:#f0f0f0; line-height:1.7;\">Thanks for everything.</td></tr>'\n    + signoff;\n}\n\nreturn [{ json: { ...$input.item.json, htmlBody } }];\n",
        "options": {}
      },
      "id": "build-email-html",
      "name": "Build Email HTML",
      "type": "n8n-nodes-base.code",
      "typeVersion": 2,
      "position": [
        672,
        112
      ]
    },
    {
      "parameters": {
        "fromEmail": "beta@quicksay.app",
        "toEmail": "={{ $json.email }}",
        "subject": "={{ $json.subject }}",
        "html": "={{ $json.htmlBody }}",
        "options": {
          "replyTo": "beta@quicksay.app",
          "appendAttribution": false
        },
        "emailFormat": "html"
      },
      "id": "send-followup-email",
      "name": "Send Follow-Up Email",
      "type": "n8n-nodes-base.emailSend",
      "typeVersion": 2.1,
      "position": [
        896,
        112
      ],
      "credentials": {
        "smtp": {
          "id": "b5Tw1HSnP7f1QovZ",
          "name": "QuickSay - beta@ SMTP"
        }
      },
      "continueOnFail": true
    },
    {
      "parameters": {
        "jsCode": "\nconst NOTION_TOKEN = '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';\nconst buildData = $('Build Email HTML').item.json;\nconst pageId = buildData.pageId;\nconst newStage = buildData.newStage;\n\nconst response = await this.helpers.httpRequest({\n  method: 'PATCH',\n  url: 'https://api.notion.com/v1/pages/' + pageId,\n  headers: {\n    'Authorization': 'Bearer ' + NOTION_TOKEN,\n    'Content-Type': 'application/json',\n    'Notion-Version': '2022-06-28'\n  },\n  body: {\n    properties: {\n      'Email Stage': { number: newStage }\n    }\n  },\n  json: true\n});\n\nreturn [{ json: { success: true, pageId, newStage } }];\n",
        "options": {}
      },
      "id": "update-notion-stage",
      "name": "Update Notion Stage",
      "type": "n8n-nodes-base.code",
      "typeVersion": 2,
      "position": [
        1120,
        112
      ]
    }
  ],
  "connections": {
    "Run Every 4 Hours": {
      "main": [
        [
          {
            "node": "Prepare Due Emails",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Prepare Due Emails": {
      "main": [
        [
          {
            "node": "Build Email HTML",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Build Email HTML": {
      "main": [
        [
          {
            "node": "Send Follow-Up Email",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Send Follow-Up Email": {
      "main": [
        [
          {
            "node": "Update Notion Stage",
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
