import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../shared/providers/providers.dart';
import 'business_scope.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  String _range = '30 days';

  // Bar data per range
  static const _barData7 = [42, 55, 38, 61, 49, 67, 80];
  static const _barData30 = [120, 145, 132, 168, 155, 178, 210];
  static const _barData90 = [320, 410, 380, 450, 420, 510, 590];
  static const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _weekLabels = ['W1', 'W2', 'W3', 'W4', 'W5', 'W6', 'W7'];
  static const _monthLabels = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul'];

  List<String> get _barLabels {
    switch (_range) {
      case '7 days': return _dayLabels;
      case '90 days': return _monthLabels;
      default: return _weekLabels;
    }
  }

  List<int> get _yAxisSteps {
    final maxVal = _currentBars.reduce((a, b) => a > b ? a : b);
    if (maxVal <= 100) return [0, 25, 50, 75, 100];
    if (maxVal <= 250) return [0, 50, 100, 150, 200];
    return [0, 150, 300, 450, 600];
  }

  // Metrics per range
  Map<String, String> get _metrics {
    switch (_range) {
      case '7 days': return {'followers': '2,712', 'growth': '+4%', 'reach': '2,840', 'engagement': '1.8%'};
      case '90 days': return {'followers': '2,840', 'growth': '+38%', 'reach': '24,200', 'engagement': '5.6%'};
      default: return {'followers': '2,840', 'growth': '+12%', 'reach': '8,420', 'engagement': '4.2%'};
    }
  }

  List<int> get _currentBars {
    switch (_range) {
      case '7 days': return _barData7;
      case '90 days': return _barData90;
      default: return _barData30;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bars = _currentBars;
    final maxBar = bars.reduce((a, b) => a > b ? a : b).toDouble();
    final m = _metrics;
    // Use real follower count from provider; keep other metrics as trend indicators
    final me = context.watch<UserProvider>().currentUser;
    final realFollowers = me?.followerCount ?? 0;
    // H19: scope to THIS business. The provider streams every business's
    // promotions (the public Crew Deals feed needs them); aggregating that raw
    // list showed Business A the titles/views/saves/redemptions of Business B.
    final promotions = ownPromotions(
        context.watch<PromotionProvider>().promotions, me?.uid);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20, color: Colors.black),
          onPressed: () => GoRouter.of(context).pop(),
        ),
        title: const Text('Analytics', style: AppTextStyles.labelLarge),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: DropdownButton<String>(
              value: _range,
              underline: const SizedBox(),
              style: AppTextStyles.caption.copyWith(color: AppColors.textPrimary),
              items: const [
                DropdownMenuItem(value: '7 days', child: Text('7 days')),
                DropdownMenuItem(value: '30 days', child: Text('30 days')),
                DropdownMenuItem(value: '90 days', child: Text('90 days')),
              ],
              onChanged: (v) => setState(() => _range = v!),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Top metric cards
          Row(children: [
            Expanded(child: _MetricCard(value: realFollowers.toString(), label: 'Followers')),
            const SizedBox(width: 10),
            Expanded(child: _MetricCard(value: m['growth']!, label: 'Growth')),
            const SizedBox(width: 10),
            Expanded(child: _MetricCard(value: m['reach']!, label: 'Reach')),
            const SizedBox(width: 10),
            Expanded(child: _MetricCard(value: m['engagement']!, label: 'Engagement')),
          ]),

          const SizedBox(height: 24),

          Row(children: [
            const Text('Follower Growth', style: AppTextStyles.labelLarge),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.shade100, borderRadius: BorderRadius.circular(4)),
              child: const Text('Demo chart', style: TextStyle(fontSize: 10, color: Colors.orange)),
            ),
          ]),
          const SizedBox(height: 12),

          Container(
            height: 220,
            padding: const EdgeInsets.fromLTRB(8, 12, 12, 8),
            decoration: BoxDecoration(
              color: AppColors.dark,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // Y-axis labels
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: _yAxisSteps.reversed.map((v) =>
                    Text(v.toString(),
                      style: AppTextStyles.caption.copyWith(color: Colors.white38, fontSize: 9))).toList(),
                ),
              ),
              const SizedBox(width: 6),
              // Bars
              Expanded(child: Column(children: [
                Expanded(child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(bars.length, (i) {
                    final frac = bars[i] / maxBar;
                    return Expanded(child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(child: Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            heightFactor: frac,
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                              ),
                            ),
                          ),
                        )),
                      ],
                    ));
                  }),
                )),
                const SizedBox(height: 4),
                Row(
                  children: List.generate(bars.length, (i) => Expanded(
                    child: Text(_barLabels[i],
                      textAlign: TextAlign.center,
                      style: AppTextStyles.caption.copyWith(color: Colors.white70, fontSize: 9)),
                  )),
                ),
              ])),
            ]),
          ),

          const SizedBox(height: 24),

          const Text('Crew Deal Performance', style: AppTextStyles.labelLarge),
          const SizedBox(height: 12),

          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: promotions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final p = promotions[i];
              final progress = p.maxRedemptions > 0
                  ? (p.currentRedemptions / p.maxRedemptions).clamp(0.0, 1.0)
                  : 0.0;
              return GestureDetector(
                onTap: () => context.push('/promotions/${p.id}'),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.percent, color: AppColors.dark, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.title, style: AppTextStyles.labelMedium,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(p.isActive ? 'Active' : 'Expired',
                          style: TextStyle(
                            color: p.isActive ? Colors.green : Colors.red,
                            fontSize: 11, fontWeight: FontWeight.w600)),
                      ])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('${p.views} views',
                          style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600)),
                        Text('${p.saves} saves', style: AppTextStyles.caption),
                      ]),
                    ]),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                      borderRadius: BorderRadius.circular(4),
                      minHeight: 6,
                    ),
                    const SizedBox(height: 4),
                    Text('${p.currentRedemptions}/${p.maxRedemptions} redemptions',
                      style: AppTextStyles.caption),
                  ]),
                ),
              );
            },
          ),

          const SizedBox(height: 24),

          const Text('Event Attendance', style: AppTextStyles.labelLarge),
          const SizedBox(height: 12),

          Consumer<EventProvider>(builder: (_, eventProvider, __) {
            final uid = context.read<AuthProvider>().currentUser?.uid;
            // Scope to this business's own events — the unfiltered global
            // list previously meant "Event Attendance" showed events other
            // businesses created, and tapping one would open it for
            // management regardless of who created it.
            final events = eventProvider.events.where((e) => e.createdBy == uid).take(3).toList();
            if (events.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: const Center(
                  child: Text('No events yet',
                      style: TextStyle(color: AppColors.textSecondary)),
                ),
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: events.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final e = events[i];
              final progress = (e.rsvpCount / 50).clamp(0.0, 1.0);
              return GestureDetector(
                onTap: () => context.push('/business-event-management', extra: e),
                child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(e.title, style: AppTextStyles.labelMedium,
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('${e.rsvpCount}',
                        style: AppTextStyles.labelMedium.copyWith(color: AppColors.primary)),
                      const Text(' RSVPs', style: AppTextStyles.caption),
                    ]),
                  ]),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                    borderRadius: BorderRadius.circular(4),
                    minHeight: 6,
                  ),
                ]),
              ),
              );
            },
            );
          }),

          const SizedBox(height: 20),
        ]),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String value, label;
  const _MetricCard({required this.value, required this.label});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
    decoration: BoxDecoration(
      color: AppColors.dark, borderRadius: BorderRadius.circular(14)),
    child: Column(children: [
      Text(value, style: AppTextStyles.labelMedium.copyWith(color: AppColors.primary)),
      const SizedBox(height: 2),
      Text(label, style: AppTextStyles.caption.copyWith(color: Colors.white70),
        textAlign: TextAlign.center),
    ]),
  );
}
