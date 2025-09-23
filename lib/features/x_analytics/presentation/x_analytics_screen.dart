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
  Map<String, dynamic>? _userProfile; // To get the user's email

  // 2. Add a state variable for the payment process
  bool _isProcessingPayment = false;

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
      final profileFuture = SupabaseService.instance.fetchUserProfile(userId);
      final statsFuture = SupabaseService.instance.fetchCreatorStats();

      final results = await Future.wait([profileFuture, statsFuture]);

      final profile = results[0];
      final stats = results[1];

      if (mounted) {
        setState(() {
          _userProfile = profile; // Store the user profile
          _isPremium = profile['is_plus'] as bool? ?? false;
          _creatorStats = stats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error loading analytics: $e'),
              backgroundColor: Colors.red),
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
                onPressed: _isProcessingPayment
                    ? null
                    : () async {
                        setState(() => _isProcessingPayment = true);

                        try {
                          final email = _userProfile?['email'] as String?;
                          if (email == null)
                            throw Exception('User email not found.');

                          final paymentDetails = await SupabaseService.instance
                              .getPaystackCheckoutUrl(email);
                          final checkoutUrl =
                              paymentDetails['authorization_url'];
                          final reference = paymentDetails['reference'];

                          final url = Uri.parse(checkoutUrl);
                          if (await canLaunchUrl(url)) {
                            await launchUrl(url,
                                mode: LaunchMode.externalApplication);

                            // After launching, show a confirmation dialog
                            if (mounted) {
                              final bool? verified = await showDialog<bool>(
                                context: context,
                                barrierDismissible: false,
                                builder: (dialogContext) => AlertDialog(
                                  backgroundColor: darkSuedeNavy,
                                  title: const Text('Confirm Your Payment',
                                      style: TextStyle(color: Colors.white)),
                                  content: const Text(
                                      'After completing the payment in your browser, tap "Verify" to activate your subscription.',
                                      style: TextStyle(color: Colors.white70)),
                                  actions: [
                                    TextButton(
                                      child: const Text('Verify Payment'),
                                      onPressed: () async {
                                        try {
                                          final success = await SupabaseService
                                              .instance
                                              .verifyPayment(reference);
                                          if (mounted)
                                            Navigator.of(dialogContext)
                                                .pop(success);
                                        } catch (e) {
                                          if (mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(SnackBar(
                                                    content: Text(e.toString()),
                                                    backgroundColor:
                                                        Colors.red));
                                            Navigator.of(dialogContext)
                                                .pop(false);
                                          }
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              );

                              if (verified == true) {
                                await _loadData(); // Refresh the screen
                              }
                            }
                          } else {
                            throw 'Could not launch payment page.';
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(e.toString()),
                                backgroundColor: Colors.red));
                          }
                        } finally {
                          if (mounted) {
                            setState(() => _isProcessingPayment = false);
                          }
                        }
                      },
              )
            else
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white38),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Manage Subscription'),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Subscription management coming soon!')));
                },
              ),
          ],
        ),
      ),
    );
  }

  // --- No changes needed to the other methods ---
  // ... _buildEarningsTab() and all other helper widgets remain the same

  Widget _buildEarningsTab() {
    if (!_isPremium) {
      return _buildUpgradeToEarnPrompt();
    }

    final plusAddons = _creatorStats['plus_addons_count'] as int? ?? 0;
    final balance = _creatorStats['reward_balance'] as num? ?? 0;
    final totalEarned = _creatorStats['total_earned'] as num? ?? 0;
    final progress = (plusAddons % 100) / 100.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildMetricCard(
            icon: Icons.star,
            title: 'Plus Subscribers',
            value: '$plusAddons',
            color: Colors.amberAccent,
          ),
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
                  value: progress,
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
              backgroundColor: Colors.cyanAccent,
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: balance > 0
                ? () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Payout feature coming soon!')));
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildUpgradeToEarnPrompt() {
    return Builder(
      // This Builder provides the correct context
      builder: (BuildContext context) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline,
                    color: Colors.amberAccent, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Earnings are for Plus Subscribers',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Upgrade your account in the "Subscription" tab to start earning rewards from your timetable.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.black,
                    backgroundColor: Colors.cyanAccent,
                  ),
                  child: const Text('Go to Subscription'),
                  onPressed: () {
                    // Now this will work correctly
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
