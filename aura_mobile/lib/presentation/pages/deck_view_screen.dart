import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aura_mobile/domain/entities/flashcard.dart';
import 'package:aura_mobile/domain/services/study_service.dart';
import 'package:aura_mobile/presentation/providers/study_provider.dart';
import 'package:aura_mobile/presentation/pages/flashcard_review_screen.dart';
import 'package:aura_mobile/presentation/pages/quiz_screen.dart';
import 'package:aura_mobile/presentation/widgets/clay_components.dart';

class DeckViewScreen extends ConsumerStatefulWidget {
  final FlashcardDeck deck;
  const DeckViewScreen({super.key, required this.deck});

  @override
  ConsumerState<DeckViewScreen> createState() => _DeckViewScreenState();
}

class _DeckViewScreenState extends ConsumerState<DeckViewScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(studyProvider.notifier).selectDeck(widget.deck));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(studyProvider);
    final stats = state.activeStats;

    return Scaffold(
      backgroundColor: ClayColors.obsidianBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.deck.name, style: GoogleFonts.outfit(color: ClayColors.textDark, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: ClayColors.textDark),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: ClayColors.redAccent),
            onPressed: () => _confirmDelete(),
          ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator(color: ClayColors.goldAccent))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Stats Overview ──
                if (stats != null) ...[
                  _statsGrid(stats),
                  const SizedBox(height: 20),
                ],

                // ── Action Buttons ──
                Row(
                  children: [
                    Expanded(
                      child: _actionButton(
                        icon: Icons.play_arrow_rounded,
                        label: 'Review (${state.reviewQueue.length})',
                        onTap: state.reviewQueue.isEmpty
                            ? null
                            : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => FlashcardReviewScreen(deck: widget.deck),
                                  ),
                                ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _actionButton(
                        icon: Icons.quiz_rounded,
                        label: 'Quiz Me',
                        onTap: state.currentCards.length < 4
                            ? null
                            : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => QuizScreen(deck: widget.deck),
                                  ),
                                ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // ── Mastery Progress ──
                if (stats != null && stats.totalCards > 0) ...[
                  Text('Mastery Progress', style: GoogleFonts.outfit(color: ClayColors.textDark, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  _masteryBar(stats),
                  const SizedBox(height: 28),
                ],

                // ── Cards List ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Cards (${state.currentCards.length})',
                        style: GoogleFonts.outfit(color: ClayColors.textDark, fontSize: 16, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline_rounded, color: ClayColors.goldAccent),
                      onPressed: () => _showAddCardDialog(),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (state.currentCards.isEmpty)
                  _emptyCards()
                else
                  ...state.currentCards.map((card) => _cardItem(card)),
              ],
            ),
    );
  }

  Widget _statsGrid(DeckStats stats) {
    return Row(
      children: [
        _statTile('Total', '${stats.totalCards}', ClayColors.textDark),
        _statTile('Due', '${stats.dueCards}', ClayColors.orangeAccent),
        _statTile('Mastered', '${stats.masteredCards}', ClayColors.greenAccent),
        _statTile('Avg Score', '${stats.averageScore.toStringAsFixed(0)}%', ClayColors.goldAccent),
      ],
    );
  }

  Widget _statTile(String label, String value, Color color) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: ClayContainer(
          borderRadius: 18,
          depth: 4.0,
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Text(value, style: GoogleFonts.outfit(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(label, style: GoogleFonts.outfit(color: ClayColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionButton({required IconData icon, required String label, VoidCallback? onTap}) {
    final enabled = onTap != null;
    return ClayButton(
      onTap: onTap,
      borderRadius: 18,
      depth: enabled ? 6.0 : 2.0,
      baseColor: enabled ? ClayColors.warmGrey : const Color(0xFFE5E2DA),
      highlightColor: enabled ? ClayColors.highlight : const Color(0xFFF7F4EF),
      shadowColor: enabled ? ClayColors.shadow : const Color(0xFFCBC7BE),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: enabled ? ClayColors.goldAccent : ClayColors.textHint.withOpacity(0.5), size: 20),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: enabled ? ClayColors.textDark : ClayColors.textHint.withOpacity(0.5),
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _masteryBar(DeckStats stats) {
    return Column(
      children: [
        ClayContainer(
          borderRadius: 12,
          isInset: true,
          depth: 4.0,
          baseColor: const Color(0xFFE5E2DA),
          highlightColor: const Color(0xFFF7F4EF),
          shadowColor: const Color(0xFFCBC7BE),
          height: 16,
          child: Row(
            children: [
              if (stats.masteredCards > 0)
                Flexible(
                  flex: stats.masteredCards,
                  child: Container(color: ClayColors.greenAccent),
                ),
              if (stats.learningCards > 0)
                Flexible(
                  flex: stats.learningCards,
                  child: Container(color: ClayColors.orangeAccent),
                ),
              if (stats.newCards > 0)
                Flexible(
                  flex: stats.newCards,
                  child: Container(color: ClayColors.textHint.withOpacity(0.3)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _legendDot('Mastered', ClayColors.greenAccent, stats.masteredCards),
            _legendDot('Learning', ClayColors.orangeAccent, stats.learningCards),
            _legendDot('New', ClayColors.textHint, stats.newCards),
          ],
        ),
      ],
    );
  }

  Widget _legendDot(String label, Color color, int count) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text('$label ($count)', style: GoogleFonts.outfit(color: ClayColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _cardItem(Flashcard card) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: ClayContainer(
        borderRadius: 18,
        depth: 4.0,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              card.front,
              style: GoogleFonts.outfit(color: ClayColors.textDark, fontSize: 14, fontWeight: FontWeight.bold),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              card.back,
              style: GoogleFonts.outfit(color: ClayColors.textMuted, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (card.topic != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: ClayColors.goldAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  card.topic!, 
                  style: GoogleFonts.outfit(color: ClayColors.goldAccent, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _emptyCards() {
    return ClayContainer(
      borderRadius: 22,
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Icon(Icons.style_outlined, color: ClayColors.textHint, size: 40),
          const SizedBox(height: 16),
          Text('No cards yet', style: GoogleFonts.outfit(color: ClayColors.textDark, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('Tap + to add cards manually', style: GoogleFonts.outfit(color: ClayColors.textMuted, fontSize: 12)),
        ],
      ),
    );
  }

  void _showAddCardDialog() {
    final frontCtrl = TextEditingController();
    final backCtrl = TextEditingController();
    final topicCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => ClayDialog(
        title: 'Add Flashcard',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClayTextField(controller: frontCtrl, hintText: 'Question (Front)', prefixIcon: Icons.help_outline_rounded),
            const SizedBox(height: 12),
            ClayTextField(controller: backCtrl, hintText: 'Answer (Back)', maxLines: 3, prefixIcon: Icons.text_snippet_outlined),
            const SizedBox(height: 12),
            ClayTextField(controller: topicCtrl, hintText: 'Topic (optional)', prefixIcon: Icons.tag_rounded),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.outfit(color: ClayColors.textMuted, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          ClayButton(
            onTap: () {
              if (frontCtrl.text.trim().isNotEmpty && backCtrl.text.trim().isNotEmpty) {
                Navigator.pop(ctx);
                ref.read(studyProvider.notifier).addCard(
                      frontCtrl.text.trim(),
                      backCtrl.text.trim(),
                      topic: topicCtrl.text.trim().isNotEmpty ? topicCtrl.text.trim() : null,
                    );
              }
            },
            borderRadius: 14,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            baseColor: ClayColors.goldAccent,
            highlightColor: ClayColors.goldHighlight,
            shadowColor: ClayColors.goldShadow,
            child: Text('Add', style: GoogleFonts.outfit(color: ClayColors.goldHighlight, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => ClayDialog(
        title: 'Delete Deck?',
        content: Text(
          'This will delete all cards, quiz history, and stats for "${widget.deck.name}".',
          style: GoogleFonts.outfit(color: ClayColors.textMuted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.outfit(color: ClayColors.textMuted, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          ClayButton(
            onTap: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
              ref.read(studyProvider.notifier).deleteDeck(widget.deck.id);
            },
            borderRadius: 14,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            baseColor: ClayColors.redAccent,
            highlightColor: ClayColors.redHighlight,
            shadowColor: ClayColors.redShadow,
            child: Text('Delete', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
