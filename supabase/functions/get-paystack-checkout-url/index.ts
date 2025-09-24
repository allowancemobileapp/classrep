// In supabase/functions/get-paystack-checkout-url/index.ts

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'

// The corsHeaders are now correctly placed directly in this file
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { email } = await req.json()
    if (!email) {
      throw new Error('Email is required.')
    }
    
    const secretKey = Deno.env.get('PAYSTACK_LIVE_SECRET_KEY')
    const planCode = Deno.env.get('PAYSTACK_LIVE_PLAN_CODE')

    if (!secretKey || !planCode) {
      throw new Error('Paystack keys or plan code are not set on the server.')
    }

    const response = await fetch('https://api.paystack.co/transaction/initialize', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${secretKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ 
        email: email, 
        amount: "50000", // 500 Naira in kobo
        plan: planCode,
      }),
    })

    if (!response.ok) {
      const errorBody = await response.json();
      throw new Error(`Paystack API error: ${errorBody.message}`);
    }

    const data = await response.json()

    return new Response(JSON.stringify(data.data), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })
  } catch (error) {
    // This will now correctly print the error to your logs for debugging
    console.error('Function Error:', error.message) 
    
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    })
  }
})