import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aura_mobile/features/daily_briefing/daily_briefing_service.dart';
import 'package:aura_mobile/features/daily_briefing/home_widget_service.dart';

/// Provider for the Daily Briefing data
final dailyBriefingProvider = FutureProvider<List<BriefingCard>>((ref) async {
  final service = DailyBriefingService();
  return service.generateBriefing();
});

/// Daily Briefing Screen — the user's personalized morning dashboard.
/// Shows weather (if online), memories, study streak, quote, and tips.
class DailyBriefingScreen extends ConsumerWidget {
  const DailyBriefingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final briefingAsync = ref.watch(dailyBriefingProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F4EF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF191816)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Daily Briefing',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w600,
            fontSize: 20,
            color: const Color(0xFF191816),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.widgets_outlined, color: Color(0xFF191816)),
            onPressed: () => _handleWidgetAction(context),
            tooltip: 'Home screen widget',
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF191816)),
            onPressed: () => ref.invalidate(dailyBriefingProvider),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: briefingAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFFB3862B)),
        ),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                Text(
                  'Failed to load briefing: $error',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => ref.invalidate(dailyBriefingProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (cards) => _BriefingBody(cards: cards),
      ),
    );
  }

  /// Adds the briefing widget to the home screen, or refreshes it when it is
  /// already placed. Without this, the only way to get the widget was the
  /// launcher's widget picker, and there was no way to force a data refresh.
  Future<void> _handleWidgetAction(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final alreadyPlaced = await HomeWidgetService.isWidgetPlaced();

    if (alreadyPlaced) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Refreshing home screen widget…')),
      );
      await HomeWidgetService.refreshNow();
      messenger.showSnackBar(
        const SnackBar(content: Text('Widget updated with the latest data.')),
      );
      return;
    }

    final requested = await HomeWidgetService.requestPinToHomeScreen();
    if (requested) {
      // Push data immediately so the freshly placed widget is not empty.
      await HomeWidgetService.refreshNow();
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Your launcher cannot add widgets from apps. Long-press the home '
            'screen → Widgets → AURA Briefing.',
          ),
          duration: Duration(seconds: 5),
        ),
      );
    }
  }
}

class _BriefingBody extends StatelessWidget {
  final List<BriefingCard> cards;
  const _BriefingBody({required this.cards});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: cards.length,
      itemBuilder: (context, index) {
        final card = cards[index];
        return _BriefingCardWidget(card: card, index: index);
      },
    );
  }
}

class _BriefingCardWidget extends StatelessWidget {
  final BriefingCard card;
  final int index;
  const _BriefingCardWidget({required this.card, required this.index});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: Duration(milliseconds: 300 + (index * 100)),
      curve: Curves.easeOut,
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: _cardColor(card.type),
        borderRadius: BorderRadius.circular(16),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: card.actionRoute != null
              ? () => _handleAction(context, card.actionRoute!)
              : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(card.icon, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.title,
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: const Color(0xFF191816),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        card.content,
                        style: GoogleFonts.outfit(
                          fontSize: 13.5,
                          color: const Color(0xFF4A4A4A),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                if (card.actionRoute != null)
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF9E9E9E),
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _cardColor(BriefingCardType type) {
    switch (type) {
      case BriefingCardType.greeting:
        return const Color(0xFFFFF8E1);
      case BriefingCardType.weather:
        return const Color(0xFFE3F2FD);
      case BriefingCardType.memories:
        return const Color(0xFFF3E5F5);
      case BriefingCardType.studyReminder:
        return const Color(0xFFE8F5E9);
      case BriefingCardType.quote:
        return const Color(0xFFFCE4EC);
      case BriefingCardType.tip:
        return const Color(0xFFE0F7FA);
      case BriefingCardType.notifications:
        return const Color(0xFFFFF3E0);
    }
  }

  void _handleAction(BuildContext context, String route) {
    Navigator.pop(context); // Go back to chat
    // The route will be handled by the chat screen's navigation system
  }
}
