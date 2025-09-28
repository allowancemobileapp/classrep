// lib/features/x_analytics/presentation/x_analytics_screen.dart

import 'package:flutter/material.dart';
import 'package:class_rep/shared/services/auth_service.dart';
import 'package:class_rep/shared/services/supabase_service.dart';
import 'package:class_rep/shared/widgets/glass_container.dart';
import 'package:url_launcher/url_launcher.dart'; // 1. Add this import

// --- THEME COLORS ---
const Color darkSuedeNavy = Color(0xFF1A1B2C);
const Color lightSuedeNavy = Color(0xFF2A2C40);

class XAnalyticsScreen extends StatefulWidget {
  const XAnalyticsScreen({super.key});

  @override
  State<XAnalyticsScreen> createState() => _XAnalyticsScreenState();
}

class _XAnalyticsScreenState extends State<XAnalyticsScreen> {
  bool _isLoading = true;
  bool _isPremium = false;
  Map<String, dynamic> _creatorStats = {};
  Map<String, dynamic>? _userProfile;
  bool _isProcessingPayment = false;
  // final String _paystackPlanCode = 'PLN_eomdf3mz9sjg4m3';

  // --- NEW STATE VARIABLE FOR BETTER UX ---
  bool _cancellationIsPending = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      // We now also check for a pending cancellation request
      final profileFuture = SupabaseService.instance.fetchUserProfile(userId);
      final statsFuture = SupabaseService.instance.fetchCreatorStats();
      final pendingCancellationFuture =
          SupabaseService.instance.hasPendingCancellation();

      final results = await Future.wait(
          [profileFuture, statsFuture, pendingCancellationFuture]);

      final profile = results[0] as Map<String, dynamic>;
      final stats = results[1] as Map<String, dynamic>;
      final hasPendingCancellation = results[2] as bool;

      if (mounted) {
        setState(() {
          _userProfile = profile;
          _isPremium = profile['is_plus'] as bool? ?? false;
          _creatorStats = stats;
          _cancellationIsPending = hasPendingCancellation;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Could not load analytics. Please check your connection.'),
              backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: darkSuedeNavy,
        appBar: AppBar(
          backgroundColor: darkSuedeNavy,
          elevation: 0,
          centerTitle: true,
          title: const Text('Analytics & Subscription',
              style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: const TabBar(
            indicatorColor: Colors.cyanAccent,
            labelColor: Colors.cyanAccent,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'My Earnings'),
              Tab(text: 'Subscription'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.cyanAccent))
            : TabBarView(
                children: [
                  _buildEarningsTab(),
                  _buildSubscriptionTab(),
                ],
              ),
      ),
    );
  }

  Widget _buildSubscriptionTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: GlassContainer(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isPremium
                  ? 'You are a Plus Subscriber'
                  : 'You are on the Free Plan',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            const Divider(color: lightSuedeNavy),
            const SizedBox(height: 16),
            _buildBenefitRow(
                Icons.people_alt_outlined, 'Add unlimited timetables'),
            _buildBenefitRow(Icons.monetization_on_outlined,
                'Become eligible for creator rewards'),
            _buildBenefitRow(
                Icons.favorite_border, 'Support your favorite creators'),
            const SizedBox(height: 32),
            if (!_isPremium)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.black,
                  backgroundColor: Colors.cyanAccent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                child: _isProcessingPayment
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 3, color: Colors.black),
                      )
                    : const Text('Upgrade to Plus - ₦500/month'),
                onPressed: _isProcessingPayment ? null : _handleUpgrade,
              )
            else
              // --- NEW UI LOGIC FOR CANCELLATION ---
              _cancellationIsPending
                  ? const Chip(
                      backgroundColor: Colors.amber,
                      label: Text(
                        'CANCELLATION PENDING',
                        style: TextStyle(
                            color: Colors.black87, fontWeight: FontWeight.bold),
                      ),
                    )
                  : OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orangeAccent,
                        side: const BorderSide(color: Colors.orangeAccent),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Request Subscription Cancellation'),
                      onPressed: _handleCancellationRequest,
                    ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleUpgrade() async {
    setState(() => _isProcessingPayment = true);
    try {
      final email = _userProfile?['email'] as String?;
      if (email == null) throw Exception('User email not found.');

      // This now makes the simple, secure call.
      final paymentDetails =
          await SupabaseService.instance.getPaystackCheckoutUrl(email: email);

      final checkoutUrl = paymentDetails['authorization_url'];
      final reference = paymentDetails['reference'];
      final url = Uri.parse(checkoutUrl);

      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        if (mounted) {
          final bool? verified = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              backgroundColor: darkSuedeNavy,
              title: const Text('Confirm Your Payment',
                  style: TextStyle(color: Colors.white)),
              content: const Text(
                  'After completing the payment, tap "Verify" to activate your subscription.',
                  style: TextStyle(color: Colors.white70)),
              actions: [
                TextButton(
                  child: const Text('Verify Payment'),
                  onPressed: () async {
                    try {
                      final success = await SupabaseService.instance
                          .verifyPayment(reference);
                      if (mounted) Navigator.of(dialogContext).pop(success);
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text(
                                "Payment verification failed. Please try again."),
                            backgroundColor: Colors.redAccent));
                        Navigator.of(dialogContext).pop(false);
                      }
                    }
                  },
                ),
              ],
            ),
          );

          if (verified == true) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Success! Your Plus subscription is now active.'),
              backgroundColor: Colors.green,
            ));
            await _loadData();
          }
        }
      } else {
        throw 'Could not launch payment page.';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Could not start the upgrade process. Please try again later.'),
              backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingPayment = false);
      }
    }
  }

  Future<void> _handleCancellationRequest() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: darkSuedeNavy,
        title: const Text('Request Cancellation?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
            'This will submit a request to our team to cancel your subscription. This may take up to 24 hours. Are you sure?',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Yes, Submit Request',
                  style: TextStyle(color: Colors.orangeAccent))),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await SupabaseService.instance.requestCancellation();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Your cancellation request has been submitted and is pending.'),
            backgroundColor: Colors.green,
          ));
          // Refresh the UI to show the "Pending" state
          await _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Could not submit cancellation request. Please try again.'),
              backgroundColor: Colors.redAccent));
        }
      }
    }
  }

  // --- All other helper methods (_buildEarningsTab, etc.) remain unchanged ---
  Widget _buildEarningsTab() {
    if (!_isPremium) {
      return _buildUpgradeToEarnPrompt();
    }
    final plusAddons = _creatorStats['plus_addons_count'] as int? ?? 0;
    final totalSubscribers =
        _creatorStats['total_subscriber_count'] as int? ?? 0;
    final freeSubscribers = totalSubscribers - plusAddons;
    final balance = _creatorStats['reward_balance'] as num? ?? 0;
    final totalEarned = _creatorStats['total_earned'] as num? ?? 0;
    final progressToNextPayout = (plusAddons % 100) / 100.0;
    final isEligibleForPayout = balance >= 1000;

    // --- NEW: Calculate the percentage of Plus subscribers ---
    final double plusPercentage =
        totalSubscribers > 0 ? plusAddons / totalSubscribers : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // --- UPDATED SUBSCRIBER BREAKDOWN WIDGET ---
          GlassContainer(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Subscribers: $totalSubscribers',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (totalSubscribers > 0)
                  LinearProgressIndicator(
                    value: plusPercentage,
                    backgroundColor: Colors.grey[700],
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          color: Colors.cyanAccent,
                        ),
                        const SizedBox(width: 8),
                        Text('Plus ($plusAddons)',
                            style: const TextStyle(color: Colors.white)),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                            width: 12, height: 12, color: Colors.grey[700]),
                        const SizedBox(width: 8),
                        Text('Free ($freeSubscribers)',
                            style: const TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          // --- END OF UPDATED WIDGET ---

          const SizedBox(height: 16),
          GlassContainer(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Progress to Next Payout',
                    style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progressToNextPayout,
                  backgroundColor: lightSuedeNavy,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 8),
                Text('${plusAddons % 100} / 100 to next ₦1,000 reward',
                    style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildMetricCard(
            icon: Icons.account_balance_wallet,
            title: 'Current Balance',
            value: '₦${balance.toStringAsFixed(2)}',
            color: Colors.greenAccent,
          ),
          const SizedBox(height: 16),
          _buildMetricCard(
            icon: Icons.history,
            title: 'Lifetime Earnings',
            value: '₦${totalEarned.toStringAsFixed(2)}',
            color: Colors.white70,
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            icon: const Icon(Icons.payment),
            label: const Text('Withdraw Balance'),
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.black,
              backgroundColor:
                  isEligibleForPayout ? Colors.cyanAccent : Colors.grey[700],
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: isEligibleForPayout
                ? () async {
                    // Payout logic remains the same
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildUpgradeToEarnPrompt() {
    return Builder(
      builder: (BuildContext context) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: GlassContainer(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.workspace_premium_outlined,
                  color: Colors.amberAccent,
                  size: 64,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Unlock Your Creator Earnings',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Join Class-Rep Plus to access exclusive creator features:',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 24),
                const Divider(color: lightSuedeNavy),
                const SizedBox(height: 16),

                // Re-using your existing _buildBenefitRow to list perks
                _buildBenefitRow(
                  Icons.monetization_on_outlined,
                  'Become eligible for creator rewards',
                ),
                _buildBenefitRow(
                  Icons.group_add_outlined,
                  'Let unlimited users add your timetable',
                ),
                _buildBenefitRow(
                  Icons.bar_chart_rounded,
                  'Track your subscriber growth',
                ),
                const SizedBox(height: 32),

                // Call to action button
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.black,
                    backgroundColor: Colors.cyanAccent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  child: const Text('Go to Subscription'),
                  onPressed: () {
                    // This function switches to the 'Subscription' tab
                    DefaultTabController.of(context).animateTo(1);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMetricCard(
      {required IconData icon,
      required String title,
      required String value,
      required Color color}) {
    return GlassContainer(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 4),
              Text(value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBenefitRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.cyanAccent),
          const SizedBox(width: 16),
          Expanded(
              child: Text(text,
                  style: const TextStyle(color: Colors.white, fontSize: 16))),
        ],
      ),
    );
  }
}
