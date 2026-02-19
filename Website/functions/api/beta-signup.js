/**
 * Cloudflare Pages Function — /api/beta-signup
 * Handles beta signup form submissions.
 * Honeypot spam protection, server-side validation,
 * N8N webhook integration with graceful fallback.
 */

export async function onRequestPost(context) {
  const corsHeaders = {
    'Access-Control-Allow-Origin': context.request.headers.get('Origin') || 'https://quicksay.app',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Content-Type': 'application/json',
  };

  try {
    const body = await context.request.json();
    const { name, email, useCase, windowsVersion, website } = body;

    // Honeypot check — if filled, silently accept (bot trap)
    if (website) {
      return new Response(JSON.stringify({ success: true }), {
        status: 200,
        headers: corsHeaders,
      });
    }

    // Validate required fields
    if (!name || !email || !useCase || !windowsVersion) {
      return new Response(
        JSON.stringify({ success: false, error: 'All fields are required.' }),
        { status: 400, headers: corsHeaders }
      );
    }

    // Validate name length
    if (name.length < 1 || name.length > 100) {
      return new Response(
        JSON.stringify({ success: false, error: 'Please enter a valid name.' }),
        { status: 400, headers: corsHeaders }
      );
    }

    // Validate email format (server-side)
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
      return new Response(
        JSON.stringify({ success: false, error: 'Please enter a valid email address.' }),
        { status: 400, headers: corsHeaders }
      );
    }

    // Validate use case
    const validUseCases = ['general', 'coding', 'writing', 'accessibility', 'other'];
    if (!validUseCases.includes(useCase)) {
      return new Response(
        JSON.stringify({ success: false, error: 'Please select a valid use case.' }),
        { status: 400, headers: corsHeaders }
      );
    }

    // Validate Windows version
    const validVersions = ['windows-11', 'windows-10', 'not-sure'];
    if (!validVersions.includes(windowsVersion)) {
      return new Response(
        JSON.stringify({ success: false, error: 'Please select a valid Windows version.' }),
        { status: 400, headers: corsHeaders }
      );
    }

    // Prepare signup data
    const signupData = {
      name: name.trim(),
      email: email.trim().toLowerCase(),
      useCase,
      windowsVersion,
      timestamp: new Date().toISOString(),
      source: 'beta-landing-page',
    };

    // Try N8N webhook first
    const n8nWebhookUrl = context.env.N8N_WEBHOOK_URL || 'https://n8n.beekz.uk/webhook/beta-signup';
    if (n8nWebhookUrl) {
      try {
        const webhookResponse = await fetch(n8nWebhookUrl, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(signupData),
        });

        if (webhookResponse.ok) {
          return new Response(JSON.stringify({ success: true }), {
            status: 200,
            headers: corsHeaders,
          });
        }
      } catch (webhookError) {
        // Webhook failed — fall through to fallback
        console.error('N8N webhook error:', webhookError.message);
      }
    }

    // Fallback: Google Sheets API
    const sheetsApiKey = context.env.GOOGLE_SHEETS_API_KEY;
    const sheetsId = context.env.GOOGLE_SHEETS_ID;
    if (sheetsApiKey && sheetsId) {
      try {
        const sheetsUrl = `https://sheets.googleapis.com/v4/spreadsheets/${sheetsId}/values/BetaSignups!A:F:append?valueInputOption=USER_ENTERED&key=${sheetsApiKey}`;
        const sheetsResponse = await fetch(sheetsUrl, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            values: [[
              signupData.timestamp,
              signupData.name,
              signupData.email,
              signupData.useCase,
              signupData.windowsVersion,
              signupData.source,
            ]],
          }),
        });

        if (sheetsResponse.ok) {
          return new Response(JSON.stringify({ success: true }), {
            status: 200,
            headers: corsHeaders,
          });
        }
      } catch (sheetsError) {
        console.error('Google Sheets error:', sheetsError.message);
      }
    }

    // Email notification fallback
    const notificationEmail = context.env.NOTIFICATION_EMAIL;
    if (notificationEmail) {
      // Log for Cloudflare dashboard / Logpush
      console.log('BETA_SIGNUP:', JSON.stringify(signupData));
    }

    // If no integrations are configured, still accept the signup
    // and log it (visible in Cloudflare dashboard)
    console.log('BETA_SIGNUP_RECEIVED:', JSON.stringify(signupData));

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: corsHeaders,
    });

  } catch (error) {
    console.error('Beta signup error:', error.message);
    return new Response(
      JSON.stringify({ success: false, error: 'Something went wrong. Please try again.' }),
      { status: 500, headers: corsHeaders }
    );
  }
}

// Handle CORS preflight
export async function onRequestOptions() {
  return new Response(null, {
    status: 204,
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
      'Access-Control-Max-Age': '86400',
    },
  });
}
