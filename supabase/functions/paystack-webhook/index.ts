import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import crypto from 'https://deno.land/std@0.177.0/node/crypto.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS preflight request
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const paystackSecret = Deno.env.get('PAYSTACK_SECRET_KEY')
    if (!paystackSecret) throw new Error('Paystack secret key is not set in environment variables.')

    // Read the request body as text FIRST for the signature check
    const bodyText = await req.text()
    const signature = req.headers.get('x-paystack-signature')

    // 1. Verify the webhook signature using the raw text body
    const hash = crypto.createHmac('sha512', paystackSecret).update(bodyText).digest('hex')
    if (hash !== signature) {
      return new Response(JSON.stringify({ error: 'Invalid signature' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Now that signature is verified, parse the text body into JSON
    const body = JSON.parse(bodyText)
    
    // 2. Check for the subscription creation event
    if (body.event === 'subscription.create') {
      const customerEmail = body.data.customer.email
      
      // Create a Supabase admin client to bypass RLS
      const supabaseAdmin = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
        // THIS IS THE CRUCIAL FIX to ensure RLS is bypassed
        { auth: { persistSession: false } }
      )

      // 3. Find the user by their email
      const { data: userData, error: userError } = await supabaseAdmin
        .from('users')
        .select('id')
        .eq('email', customerEmail)
        .single()

      if (userError) throw new Error(`User with email ${customerEmail} not found. Details: ${userError.message}`)
      
      // 4. Update the user's profile to is_plus = true
      const { error: updateError } = await supabaseAdmin
        .from('users')
        .update({ is_plus: true })
        .eq('id', userData.id)
        
      if (updateError) throw new Error(`Failed to update user status: ${updateError.message}`)
    }
    
    // Return a 200 OK response to Paystack to confirm receipt
    return new Response(JSON.stringify({ status: 'ok' }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  } catch (error) {
    console.error(error)
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    })
  }
})