/**
 * Cloudflare Pages Function — /api/beta-feedback
 * Handles POST submissions from the beta feedback form.
 * Validates required fields, checks honeypot, enriches data with NPS category,
 * and forwards to an N8N webhook for processing.
 */
export async function onRequestPost(context) {
  const request = context.request;

  // CORS headers for same-origin POST
  const headers = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': 'https://quicksay.app',
  };

  try {
    const data = await request.json();

    // Honeypot check — bots fill the hidden "company" field
    if (data.company) {
      // Silently accept to not tip off the bot
      return new Response(JSON.stringify({ success: true }), { headers });
    }

    // Validate required fields
    const required = [
      'name',
      'email',
      'installEase',
      'groqSetupEase',
      'onboardingHelpfulness',
      'mode',
      'transcriptionAccuracy',
      'transcriptionSpeed',
      'textCleanup',
      'nps',
      'favoriteThing',
      'topImprovement',
      'testimonialConsent',
    ];

    for (const field of required) {
      if (!data[field] && data[field] !== 0 && data[field] !== '0') {
        return new Response(
          JSON.stringify({ success: false, error: `Missing required field: ${field}` }),
          { status: 400, headers }
        );
      }
    }

    // Basic email validation
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(data.email)) {
      return new Response(
        JSON.stringify({ success: false, error: 'Invalid email address' }),
        { status: 400, headers }
      );
    }

    // Calculate NPS category
    const nps = parseInt(data.nps);
    let npsCategory = 'detractor';
    if (nps >= 9) npsCategory = 'promoter';
    else if (nps >= 7) npsCategory = 'passive';

    const enrichedData = {
      ...data,
      npsCategory,
      submittedAt: new Date().toISOString(),
      userAgent: request.headers.get('User-Agent') || '',
    };

    // Remove honeypot field from stored data
    delete enrichedData.company;

    // Forward to N8N webhook (or any webhook endpoint)
    const webhookUrl =
      context.env?.N8N_FEEDBACK_WEBHOOK ||
      'https://n8n.beekz.uk/webhook/beta-feedback';

    try {
      await fetch(webhookUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(enrichedData),
      });
    } catch (e) {
      // Log webhook failure but don't fail the user's submission
      console.error('Webhook delivery failed:', e.message);
    }

    return new Response(JSON.stringify({ success: true }), { headers });
  } catch (error) {
    console.error('Beta feedback error:', error.message);
    return new Response(
      JSON.stringify({ success: false, error: 'Invalid request' }),
      { status: 400, headers }
    );
  }
}

/**
 * Handle OPTIONS preflight for CORS
 */
export async function onRequestOptions() {
  return new Response(null, {
    status: 204,
    headers: {
      'Access-Control-Allow-Origin': 'https://quicksay.app',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
      'Access-Control-Max-Age': '86400',
    },
  });
}
