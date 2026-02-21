// Updates the Beta Feedback Handler workflow in N8N
// Usage: node update-feedback-workflow.js
// Mode: deactivate -> PUT update -> reactivate (workflow RganQ5YYnTXpS7H9)
//
// Webhook: POST /webhook/beta-feedback
// Pipeline: Webhook -> Respond OK (parallel) + Extract Data -> Auto-Categorize (Groq LLM) ->
//           Save to Notion + Send Confirmation Email + NPS Router
//           NPS Router: detractor -> URGENT Notify Adrian | passive/promoter -> Notify Adrian
// Notion DB: Beta Feedback (30a762ba3bc180beae59ec7eac37d2d1)
//
// IMPORTANT: This script is the source of truth for this workflow.
// To update Code node logic, edit the jsCode fields in the workflow object below,
// then run: node update-feedback-workflow.js
// DO NOT edit the workflow directly in the N8N UI without also updating this script.
// Workflow definition last fetched from N8N: 2026-02-20

const N8N_URL = 'https://n8n.beekz.uk/api/v1';
const N8N_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJjNDkyZGQyMy04YTc2LTQ2ODAtOGI3ZC0wMzk0ZGMxOTdiYjkiLCJpc3MiOiJuOG4iLCJhdWQiOiJwdWJsaWMtYXBpIiwianRpIjoiMzU5YzRiYTEtMGRiMy00NDVhLWEzNjMtMjI4YTY3ZjgyNTk2IiwiaWF0IjoxNzcxNDQzODk3fQ.H8iQ3dWfX9CUfLd0wFu79SSOSH71HCiyYZdwmQwUGdk';
const WORKFLOW_ID = 'RganQ5YYnTXpS7H9';

// ==========================================
// WORKFLOW DEFINITION
// To edit Code node logic: find the node by name, update its parameters.jsCode field,
// then run this script to deploy.
// ==========================================
const workflow = {
  "name": "QuickSay Beta Feedback Handler",
  "nodes": [
    {
      "parameters": {
        "httpMethod": "POST",
        "path": "beta-feedback",
        "responseMode": "responseNode",
        "options": {}
      },
      "id": "webhook-feedback",
      "name": "Beta Feedback Webhook",
      "type": "n8n-nodes-base.webhook",
      "typeVersion": 2,
      "position": [
        0,
        224
      ],
      "webhookId": "beta-feedback"
    },
    {
      "parameters": {
        "respondWith": "json",
        "responseBody": "={{ JSON.stringify({ success: true }) }}",
        "options": {}
      },
      "id": "respond-feedback",
      "name": "Respond OK",
      "type": "n8n-nodes-base.respondToWebhook",
      "typeVersion": 1.1,
      "position": [
        224,
        128
      ]
    },
    {
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
              "id": "referralSource",
              "name": "referralSource",
              "value": "={{ $json.body.referralSource || \"\" }}",
              "type": "string"
            },
            {
              "id": "setupExperience",
              "name": "setupExperience",
              "value": "={{ $json.body.setupExperience }}",
              "type": "string"
            },
            {
              "id": "transcriptionQuality",
              "name": "transcriptionQuality",
              "value": "={{ $json.body.transcriptionQuality }}",
              "type": "string"
            },
            {
              "id": "textCleanup",
              "name": "textCleanup",
              "value": "={{ $json.body.textCleanup }}",
              "type": "string"
            },
            {
              "id": "setupIssues",
              "name": "setupIssues",
              "value": "={{ $json.body.setupIssues || \"\" }}",
              "type": "string"
            },
            {
              "id": "nps",
              "name": "nps",
              "value": "={{ $json.body.nps }}",
              "type": "string"
            },
            {
              "id": "npsCategory",
              "name": "npsCategory",
              "value": "={{ parseInt($json.body.nps) >= 9 ? \"promoter\" : parseInt($json.body.nps) >= 7 ? \"passive\" : \"detractor\" }}",
              "type": "string"
            },
            {
              "id": "favoriteThing",
              "name": "favoriteThing",
              "value": "={{ $json.body.favoriteThing }}",
              "type": "string"
            },
            {
              "id": "topImprovement",
              "name": "topImprovement",
              "value": "={{ $json.body.topImprovement }}",
              "type": "string"
            },
            {
              "id": "bugs",
              "name": "bugs",
              "value": "={{ $json.body.bugs || \"\" }}",
              "type": "string"
            },
            {
              "id": "testimonialConsent",
              "name": "testimonialConsent",
              "value": "={{ $json.body.testimonialConsent || \"\" }}",
              "type": "string"
            },
            {
              "id": "testimonialText",
              "name": "testimonialText",
              "value": "={{ $json.body.testimonialText || \"\" }}",
              "type": "string"
            },
            {
              "id": "anythingElse",
              "name": "anythingElse",
              "value": "={{ $json.body.anythingElse || \"\" }}",
              "type": "string"
            },
            {
              "id": "followUpConsent",
              "name": "followUpConsent",
              "value": "={{ $json.body.followUpConsent === true || $json.body.followUpConsent === \"yes\" ? \"Yes\" : \"No\" }}",
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
      },
      "id": "set-feedback",
      "name": "Extract Feedback Data",
      "type": "n8n-nodes-base.set",
      "typeVersion": 3.4,
      "position": [
        224,
        320
      ]
    },
    {
      "parameters": {
        "fromEmail": "beta@quicksay.app",
        "toEmail": "say@quicksay.app",
        "subject": "={{ \"Beta Feedback: \" + $('Extract Feedback Data').item.json.name + \" (NPS \" + $('Extract Feedback Data').item.json.nps + \" - \" + $('Extract Feedback Data').item.json.npsCategory + \")\" }}",
        "html": "={{ ($json.npsCategory === \"promoter\" ? '<div style=\"background:#dcfce7;border:1px solid #16a34a;border-radius:8px;padding:12px 16px;margin-bottom:16px;\">' + '<strong style=\"color:#16a34a;\">PROMOTER</strong> NPS ' + $json.nps + '/10' + (($json.testimonialConsent || \"\").indexOf(\"yes\") !== -1 ? ' &middot; <strong>Testimonial Candidate</strong>' : '') + '</div>' : '') + '<h2>New Beta Feedback</h2>' + '<p><strong>From:</strong> ' + $json.name + ' (' + $json.email + ')</p>' + ($json.referralSource ? '<p><strong>Referral:</strong> ' + $json.referralSource + '</p>' : '') + '<p><strong>NPS:</strong> ' + $json.nps + '/10 (' + $json.npsCategory + ')</p>' + ($json.autoTags ? '<p><strong>Auto Tags:</strong> ' + $json.autoTags.join(\", \") + '</p>' : '') + '<p><strong>Ratings:</strong> Setup ' + ($json.setupExperience || \"N/A\") + '/5 - Transcription ' + ($json.transcriptionQuality || \"N/A\") + '/5 - Cleanup ' + ($json.textCleanup || \"N/A\") + '/5</p>' + '<p><strong>Favorite:</strong> ' + ($json.favoriteThing || \"N/A\") + '</p>' + '<p><strong>Top improvement:</strong> ' + ($json.topImprovement || \"N/A\") + '</p>' + ($json.setupIssues ? '<p><strong>Setup/performance issues:</strong> ' + $json.setupIssues + '</p>' : '') + ($json.bugs ? '<p><strong>Bugs:</strong> ' + $json.bugs + '</p>' : '') + ($json.anythingElse ? '<p><strong>Additional comments:</strong> ' + $json.anythingElse + '</p>' : '') + '<p><strong>Testimonial:</strong> ' + ($json.testimonialConsent || \"none\") + '</p>' + ($json.testimonialText ? '<blockquote>' + $json.testimonialText + '</blockquote>' : '') }}",
        "options": {
          "appendAttribution": false
        },
        "emailFormat": "html"
      },
      "id": "gmail-notify",
      "name": "Notify Adrian",
      "type": "n8n-nodes-base.emailSend",
      "typeVersion": 2.1,
      "position": [
        896,
        224
      ],
      "webhookId": "d9b67e86-9d69-41b5-896e-cc338966a6ab",
      "credentials": {
        "smtp": {
          "id": "b5Tw1HSnP7f1QovZ",
          "name": "QuickSay - beta@ SMTP"
        }
      }
    },
    {
      "parameters": {
        "fromEmail": "beta@quicksay.app",
        "toEmail": "={{ $('Extract Feedback Data').item.json.email }}",
        "subject": "Got your feedback — thanks!",
        "html": "=<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n  <meta charset=\"UTF-8\" />\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\" />\n  <meta name=\"color-scheme\" content=\"dark\" />\n  <meta name=\"supported-color-schemes\" content=\"dark\" />\n  <title>Got your feedback — thanks!</title>\n</head>\n<body style=\"margin:0; padding:0; background-color:#121214; -webkit-text-size-adjust:100%; -ms-text-size-adjust:100%;\">\n  <div style=\"display:none; max-height:0; overflow:hidden; mso-hide:all;\">I read every submission personally.</div>\n  <table role=\"presentation\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\" width=\"100%\" style=\"background-color:#121214;\">\n    <tr>\n      <td align=\"center\" style=\"padding:0;\">\n        <table role=\"presentation\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\" width=\"600\" style=\"max-width:600px; width:100%; background-color:#121214;\">\n          <tr>\n            <td align=\"center\" style=\"padding:40px 30px 16px 30px;\">\n              <a href=\"https://quicksay.app\" target=\"_blank\" style=\"text-decoration:none;\">\n                <img src=\"https://quicksay.app/logo-128.png\" alt=\"QuickSay\" width=\"48\" height=\"48\" style=\"display:block; border:0; outline:none;\" />\n              </a>\n            </td>\n          </tr>\n          <tr>\n            <td align=\"center\" style=\"padding:0 30px 32px 30px;\">\n              <a href=\"https://quicksay.app\" target=\"_blank\" style=\"text-decoration:none; font-family:Arial,Helvetica,sans-serif; font-size:28px; font-weight:700; color:#f0f0f0; letter-spacing:-0.5px;\">\n                <span style=\"color:#22d3c5;\">Q</span>uickSay\n              </a>\n            </td>\n          </tr>\n          <tr>\n            <td style=\"padding:0 30px 16px 30px; font-family:Arial,Helvetica,sans-serif; font-size:20px; font-weight:700; color:#f0f0f0; line-height:1.4;\">\n              Hey {{ $('Extract Feedback Data').item.json.name }},\n            </td>\n          </tr>\n          <tr>\n            <td style=\"padding:0 30px 24px 30px; font-family:Arial,Helvetica,sans-serif; font-size:16px; color:#f0f0f0; line-height:1.7;\">\n              Thanks for taking the time. I read every submission personally and your feedback is already shaping what I work on next.\n            </td>\n          </tr>\n          <tr>\n            <td style=\"padding:0 30px 8px 30px; font-family:Arial,Helvetica,sans-serif; font-size:16px; color:#f0f0f0; line-height:1.7;\">\n              If anything else comes up, reply to this email.\n            </td>\n          </tr>\n          <tr>\n            <td style=\"padding:24px 30px 8px 30px; font-family:Arial,Helvetica,sans-serif; font-size:16px; color:#f0f0f0; line-height:1.5;\">\n              &mdash; Adrian\n            </td>\n          </tr>\n          <tr>\n            <td style=\"padding:0 30px 40px 30px; font-family:Arial,Helvetica,sans-serif; font-size:13px; color:#8a8a95; line-height:1.5;\">\n              Solo developer &middot; Alberta, Canada<br />\n              <a href=\"https://quicksay.app\" target=\"_blank\" style=\"color:#22d3c5; text-decoration:none;\">quicksay.app</a>\n            </td>\n          </tr>\n          <tr>\n            <td style=\"padding:0 30px;\">\n              <table role=\"presentation\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\" width=\"100%\">\n                <tr>\n                  <td style=\"border-top:1px solid #2a2a30; font-size:1px; line-height:1px;\">&nbsp;</td>\n                </tr>\n              </table>\n            </td>\n          </tr>\n          <tr>\n            <td align=\"center\" style=\"padding:20px 30px 40px 30px; font-family:Arial,Helvetica,sans-serif; font-size:12px; color:#5a5a65; line-height:1.6;\">\n              You're receiving this because you submitted feedback for the QuickSay beta.<br />\n              <a href=\"https://quicksay.app\" target=\"_blank\" style=\"color:#5a5a65; text-decoration:underline;\">quicksay.app</a>\n            </td>\n          </tr>\n        </table>\n      </td>\n    </tr>\n  </table>\n</body>\n</html>",
        "options": {
          "appendAttribution": false,
          "replyTo": "beta@quicksay.app"
        },
        "emailFormat": "html"
      },
      "id": "gmail-confirm",
      "name": "Send Confirmation Email",
      "type": "n8n-nodes-base.emailSend",
      "typeVersion": 2.1,
      "position": [
        672,
        112
      ],
      "webhookId": "f25efc04-5f87-4090-a4dc-8c1f133dbc26",
      "credentials": {
        "smtp": {
          "id": "b5Tw1HSnP7f1QovZ",
          "name": "QuickSay - beta@ SMTP"
        }
      }
    },
    {
      "parameters": {
        "jsCode": "\n// Auto-categorize feedback using Groq LLM\nconst GROQ_KEY = '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';\nconst d = $('Extract Feedback Data').item.json;\n\n// Combine free-text fields for analysis\nconst feedbackText = [\n  d.favoriteThing   ? `Favorite: ${d.favoriteThing}`   : '',\n  d.topImprovement  ? `Improvement: ${d.topImprovement}`  : '',\n  d.bugs            ? `Bugs: ${d.bugs}`                   : '',\n  d.anythingElse    ? `Other: ${d.anythingElse}`           : '',\n  d.setupIssues     ? `Setup/Performance: ${d.setupIssues}` : ''\n].filter(Boolean).join('\\n');\n\nlet autoTags = ['uncategorized'];\n\ntry {\n  const resp = await this.helpers.httpRequest({\n    method: 'POST',\n    url: 'https://api.groq.com/openai/v1/chat/completions',\n    headers: {\n      'Authorization': `Bearer ${GROQ_KEY}`,\n      'Content-Type': 'application/json'\n    },\n    body: {\n      model: 'llama-3.3-70b-versatile',\n      messages: [\n        {\n          role: 'system',\n          content: 'Categorize this user feedback into one or more categories. Return ONLY a JSON array of matching category strings, nothing else.\\nCategories: bug_report, feature_request, ux_issue, praise, performance_issue, setup_difficulty'\n        },\n        { role: 'user', content: feedbackText || 'No feedback text provided' }\n      ],\n      temperature: 0,\n      max_tokens: 100\n    },\n    json: true\n  });\n  const content = resp.choices[0].message.content.trim();\n  const parsed = JSON.parse(content);\n  if (Array.isArray(parsed) && parsed.length > 0) {\n    autoTags = parsed;\n  }\n} catch (e) {\n  // Groq down -- default to uncategorized, don't block workflow\n  autoTags = ['uncategorized'];\n}\n\n// Pass through ALL original fields + autoTags\nreturn [{ json: { ...d, autoTags } }];\n"
      },
      "id": "auto-categorize",
      "name": "Auto-Categorize Feedback",
      "type": "n8n-nodes-base.code",
      "typeVersion": 2,
      "position": [
        448,
        320
      ],
      "continueOnFail": true
    },
    {
      "parameters": {
        "rules": {
          "values": [
            {
              "conditions": {
                "options": {
                  "caseSensitive": true,
                  "leftValue": "",
                  "typeValidation": "strict"
                },
                "conditions": [
                  {
                    "id": "detractor-rule",
                    "leftValue": "={{ $json.npsCategory }}",
                    "rightValue": "detractor",
                    "operator": {
                      "type": "string",
                      "operation": "equals"
                    }
                  }
                ],
                "combinator": "and"
              },
              "renameOutput": true,
              "outputKey": "detractor"
            },
            {
              "conditions": {
                "options": {
                  "caseSensitive": true,
                  "leftValue": "",
                  "typeValidation": "strict"
                },
                "conditions": [
                  {
                    "id": "passive-rule",
                    "leftValue": "={{ $json.npsCategory }}",
                    "rightValue": "passive",
                    "operator": {
                      "type": "string",
                      "operation": "equals"
                    }
                  }
                ],
                "combinator": "and"
              },
              "renameOutput": true,
              "outputKey": "passive"
            },
            {
              "conditions": {
                "options": {
                  "caseSensitive": true,
                  "leftValue": "",
                  "typeValidation": "strict"
                },
                "conditions": [
                  {
                    "id": "promoter-rule",
                    "leftValue": "={{ $json.npsCategory }}",
                    "rightValue": "promoter",
                    "operator": {
                      "type": "string",
                      "operation": "equals"
                    }
                  }
                ],
                "combinator": "and"
              },
              "renameOutput": true,
              "outputKey": "promoter"
            }
          ]
        },
        "options": {}
      },
      "id": "nps-router",
      "name": "NPS Router",
      "type": "n8n-nodes-base.switch",
      "typeVersion": 3,
      "position": [
        672,
        304
      ]
    },
    {
      "parameters": {
        "fromEmail": "beta@quicksay.app",
        "toEmail": "a.beeksma21@gmail.com",
        "subject": "=ACTION REQUIRED: Detractor Feedback from {{ $json.name }} (NPS {{ $json.nps }})",
        "options": {
          "appendAttribution": false,
          "allowUnauthorizedCerts": false,
          "replyTo": "beta@quicksay.app"
        },
        "emailFormat": "html",
        "html": "={{ '<div style=\"font-family:Arial,sans-serif;max-width:600px;\">' + '<div style=\"background:#dc2626;color:white;padding:16px 20px;border-radius:8px 8px 0 0;\">' + '<h2 style=\"margin:0;\">Detractor Alert - NPS ' + $json.nps + '/10</h2>' + '</div>' + '<div style=\"border:2px solid #dc2626;border-top:none;padding:20px;border-radius:0 0 8px 8px;\">' + '<p><strong>From:</strong> ' + $json.name + ' (<a href=\"mailto:' + $json.email + '\">' + $json.email + '</a>)</p>' + '<p><strong>NPS:</strong> ' + $json.nps + '/10 - <span style=\"color:#dc2626;font-weight:bold;\">DETRACTOR</span></p>' + ($json.topImprovement ? '<p><strong>Top Improvement:</strong> ' + $json.topImprovement + '</p>' : '') + ($json.bugs ? '<p><strong>Bugs:</strong> ' + $json.bugs + '</p>' : '') + ($json.setupIssues ? '<p><strong>Setup/Performance Issues:</strong> ' + $json.setupIssues + '</p>' : '') + ($json.favoriteThing ? '<p><strong>What They Liked:</strong> ' + $json.favoriteThing + '</p>' : '') + ($json.anythingElse ? '<p><strong>Additional:</strong> ' + $json.anythingElse + '</p>' : '') + ($json.autoTags ? '<p><strong>Auto Tags:</strong> ' + $json.autoTags.join(', ') + '</p>' : '') + '<hr style=\"margin:16px 0;\">' + '<p style=\"color:#dc2626;\"><strong>Action:</strong> Reply to this user within 24 hours.</p>' + '<p><a href=\"mailto:' + $json.email + '?subject=Re: Your QuickSay Feedback\" style=\"display:inline-block;background:#dc2626;color:white;padding:10px 20px;border-radius:6px;text-decoration:none;font-weight:bold;\">Reply to ' + $json.name + '</a></p>' + '</div></div>' }}"
      },
      "id": "urgent-notify",
      "name": "URGENT: Notify Adrian",
      "type": "n8n-nodes-base.emailSend",
      "typeVersion": 2.1,
      "position": [
        896,
        416
      ],
      "webhookId": "48089e50-9569-4fc7-9ae8-fb8d113e078f",
      "credentials": {
        "smtp": {
          "id": "b5Tw1HSnP7f1QovZ",
          "name": "QuickSay - beta@ SMTP"
        }
      }
    },
    {
      "parameters": {
        "jsCode": "\nconst NOTION_TOKEN = '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';\nconst DB_ID = '30a762ba3bc180beae59ec7eac37d2d1';\n\nconst d = $('Extract Feedback Data').item.json;\nconst autoTags = $input.item.json.autoTags || ['uncategorized'];\nconst nps = d.nps !== undefined && d.nps !== \"\" ? parseInt(d.nps) : null;\nconst category = nps === null ? null : (nps >= 9 ? 'Promoter' : nps >= 7 ? 'Passive' : 'Detractor');\nconst npsEmoji = nps === null ? '❓' : (nps >= 9 ? '🟢' : nps >= 7 ? '🟡' : '🔴');\nconst calloutColor = nps === null ? 'gray_background' : (nps >= 9 ? 'green_background' : nps >= 7 ? 'yellow_background' : 'red_background');\n\n// Parse ratings\nconst setupRating = parseInt(d.setupExperience) || null;\nconst transcriptionRating = parseInt(d.transcriptionQuality) || null;\nconst cleanupRating = parseInt(d.textCleanup) || null;\n\n// Testimonial candidate: promoter + consent includes \"yes\"\nconst isTestimonialCandidate = nps >= 9 && (d.testimonialConsent || '').includes('yes');\n\n// Helpers\nconst text = (content) => ({ type: 'text', text: { content: content || '' } });\nconst bold = (content) => ({ type: 'text', text: { content: content || '' }, annotations: { bold: true } });\n\n// Build children blocks\nconst children = [];\n\n// NPS Callout (color-coded)\nchildren.push({\n  object: 'block', type: 'callout',\n  callout: {\n    icon: { type: 'emoji', emoji: npsEmoji },\n    color: calloutColor,\n    rich_text: [bold(`NPS: ${nps}/10 -- ${category}`)]\n  }\n});\n\n// Auto Tags callout\nif (autoTags.length > 0) {\n  children.push({\n    object: 'block', type: 'callout',\n    callout: {\n      icon: { type: 'emoji', emoji: '🏷️' },\n      color: 'gray_background',\n      rich_text: [bold('Tags: '), text(autoTags.join(', '))]\n    }\n  });\n}\n\nchildren.push({ object: 'block', type: 'divider', divider: {} });\n\n// About section\nchildren.push({\n  object: 'block', type: 'heading_2',\n  heading_2: { rich_text: [text('👤 About')] }\n});\nconst aboutParts = [`${d.name} · ${d.email}`];\nif (d.referralSource) aboutParts.push(`Found via: ${d.referralSource}`);\nchildren.push({\n  object: 'block', type: 'paragraph',\n  paragraph: { rich_text: [text(aboutParts.join('\\n'))] }\n});\n\n// Ratings section\nconst ratingParts = [];\nif (setupRating) ratingParts.push(`Setup: ${setupRating}/5`);\nif (transcriptionRating) ratingParts.push(`Transcription: ${transcriptionRating}/5`);\nif (cleanupRating) ratingParts.push(`Cleanup: ${cleanupRating}/5`);\nif (ratingParts.length > 0) {\n  children.push({ object: 'block', type: 'divider', divider: {} });\n  children.push({\n    object: 'block', type: 'heading_2',\n    heading_2: { rich_text: [text('📝 Ratings')] }\n  });\n  children.push({\n    object: 'block', type: 'paragraph',\n    paragraph: { rich_text: [text(ratingParts.join(' · '))] }\n  });\n  if (d.setupIssues) {\n    children.push({\n      object: 'block', type: 'paragraph',\n      paragraph: { rich_text: [bold('Setup/Performance Issues: '), text(d.setupIssues)] }\n    });\n  }\n}\n\n// What They Love\nif (d.favoriteThing) {\n  children.push({ object: 'block', type: 'divider', divider: {} });\n  children.push({\n    object: 'block', type: 'heading_2',\n    heading_2: { rich_text: [text('⭐ What They Love')] }\n  });\n  children.push({\n    object: 'block', type: 'quote',\n    quote: { rich_text: [text(d.favoriteThing)] }\n  });\n}\n\n// What Needs Fixing\nconst fixes = [];\nif (d.topImprovement) fixes.push({ label: 'Top Improvement', value: d.topImprovement });\nif (d.bugs) fixes.push({ label: 'Bugs', value: d.bugs });\n\nif (fixes.length > 0) {\n  children.push({ object: 'block', type: 'divider', divider: {} });\n  children.push({\n    object: 'block', type: 'heading_2',\n    heading_2: { rich_text: [text('🔧 What Needs Fixing')] }\n  });\n  for (const fix of fixes) {\n    children.push({\n      object: 'block', type: 'paragraph',\n      paragraph: { rich_text: [bold(`${fix.label}: `), text(fix.value)] }\n    });\n  }\n}\n\n// Testimonial\nif ((d.testimonialConsent || '').includes('yes') && d.testimonialText) {\n  children.push({ object: 'block', type: 'divider', divider: {} });\n  children.push({\n    object: 'block', type: 'heading_2',\n    heading_2: { rich_text: [text('💬 Testimonial')] }\n  });\n  children.push({\n    object: 'block', type: 'quote',\n    quote: { rich_text: [text(`\"${d.testimonialText}\"`)] }\n  });\n  children.push({\n    object: 'block', type: 'paragraph',\n    paragraph: { rich_text: [{ type: 'text', text: { content: '✅ Consent given to use as testimonial' }, annotations: { italic: true, color: 'green' } }] }\n  });\n}\n\n// Additional Notes\nif (d.anythingElse) {\n  children.push({ object: 'block', type: 'divider', divider: {} });\n  children.push({\n    object: 'block', type: 'heading_2',\n    heading_2: { rich_text: [text('📌 Additional Notes')] }\n  });\n  children.push({\n    object: 'block', type: 'paragraph',\n    paragraph: { rich_text: [text(d.anythingElse)] }\n  });\n}\n\n// Follow-up consent\nif (d.followUpConsent === 'Yes') {\n  children.push({ object: 'block', type: 'divider', divider: {} });\n  children.push({\n    object: 'block', type: 'paragraph',\n    paragraph: { rich_text: [{ type: 'text', text: { content: '✅ Open to follow-up contact' }, annotations: { italic: true, color: 'green' } }] }\n  });\n}\n\n// Build Notion API payload\nconst payload = {\n  parent: { database_id: DB_ID },\n  properties: {\n    'Name': { title: [{ text: { content: d.name || '' } }] },\n    'Email': { email: d.email || null },\n    'NPS Score': { number: nps },  // null clears the field\n    'NPS Category': category ? { select: { name: category } } : { select: null },\n    'Setup Rating': { number: setupRating },\n    'Transcription Rating': { number: transcriptionRating },\n    'Text Cleanup Rating': { number: cleanupRating },\n    'Favorite Thing': { rich_text: [{ text: { content: (d.favoriteThing || '').substring(0, 2000) } }] },\n    'Top Improvement': { rich_text: [{ text: { content: (d.topImprovement || '').substring(0, 2000) } }] },\n    'Bugs': { rich_text: [{ text: { content: (d.bugs || '').substring(0, 2000) } }] },\n    'Testimonial Consent': { checkbox: (d.testimonialConsent || '').includes('yes') },\n    'Testimonial Text': { rich_text: [{ text: { content: (d.testimonialText || '').substring(0, 2000) } }] },\n    'Referral Source': { rich_text: [{ text: { content: (d.referralSource || '').substring(0, 2000) } }] },\n    'Setup Issues': { rich_text: [{ text: { content: (d.setupIssues || '').substring(0, 2000) } }] },\n    'Anything Else': { rich_text: [{ text: { content: (d.anythingElse || '').substring(0, 2000) } }] },\n    'Follow-up Consent': { checkbox: d.followUpConsent === 'Yes' },\n    'Submitted': { date: { start: d.timestamp } },\n    'Testimonial Candidate': { checkbox: isTestimonialCandidate },\n    'Auto Tags': { multi_select: autoTags.map(t => ({ name: t })) }\n  },\n  children: children\n};\n\nconst response = await this.helpers.httpRequest({\n  method: 'POST',\n  url: 'https://api.notion.com/v1/pages',\n  headers: {\n    'Authorization': `Bearer ${NOTION_TOKEN}`,\n    'Content-Type': 'application/json',\n    'Notion-Version': '2022-06-28'\n  },\n  body: payload,\n  json: true\n});\n\nreturn [{ json: response }];\n"
      },
      "id": "notion-save",
      "name": "Save to Notion",
      "type": "n8n-nodes-base.code",
      "typeVersion": 2,
      "position": [
        672,
        528
      ],
      "continueOnFail": true
    }
  ],
  "connections": {
    "Beta Feedback Webhook": {
      "main": [
        [
          {
            "node": "Respond OK",
            "type": "main",
            "index": 0
          },
          {
            "node": "Extract Feedback Data",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Extract Feedback Data": {
      "main": [
        [
          {
            "node": "Auto-Categorize Feedback",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Save to Notion": {
      "main": [
        []
      ]
    },
    "Auto-Categorize Feedback": {
      "main": [
        [
          {
            "node": "Save to Notion",
            "type": "main",
            "index": 0
          },
          {
            "node": "Send Confirmation Email",
            "type": "main",
            "index": 0
          },
          {
            "node": "NPS Router",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "NPS Router": {
      "main": [
        [
          {
            "node": "URGENT: Notify Adrian",
            "type": "main",
            "index": 0
          }
        ],
        [
          {
            "node": "Notify Adrian",
            "type": "main",
            "index": 0
          }
        ],
        [
          {
            "node": "Notify Adrian",
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
