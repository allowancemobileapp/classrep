import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import crypto from 'https://deno.land/std@0.177.0/node/crypto.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // FIX 1: Using the correct, consistent secret key name
    const paystackSecret = Deno.env.get('PAYSTACK_LIVE_SECRET_KEY')
    if (!paystackSecret) throw new Error('Paystack secret key is not set in environment variables.')

    const bodyText = await req.text()
    const signature = req.headers.get('x-paystack-signature')

    const hash = crypto.createHmac('sha512', paystackSecret).update(bodyText).digest('hex')
    if (hash !== signature) {
      return new Response(JSON.stringify({ error: 'Invalid signature' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const body = JSON.parse(bodyText)
    
    if (body.event === 'subscription.create') {
      const customerEmail = body.data.customer.email
      
      const supabaseAdmin = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
        { auth: { persistSession: false } }
      )

      // Find the user by their email in your public users table
      const { data: userData, error: userError } = await supabaseAdmin
        .from('users') // CORRECT: Using the 'users' table from your schema
        .select('id')
        .eq('email', customerEmail)
        .single()

      if (userError) throw new Error(`User with email ${customerEmail} not found. Details: ${userError.message}`)
      
      // Update the user's profile to is_plus = true in your public users table
      const { error: updateError } = await supabaseAdmin
        .from('users') // CORRECT: Using the 'users' table from your schema
        .update({ is_plus: true })
        .eq('id', userData.id)
        
      if (updateError) throw new Error(`Failed to update user status: ${updateError.message}`)
    }
    
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