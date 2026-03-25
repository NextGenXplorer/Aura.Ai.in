import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aura_mobile/domain/entities/flashcard.dart';
import 'package:aura_mobile/domain/services/study_service.dart';
import 'package:aura_mobile/presentation/providers/study_provider.dart';
import 'package:aura_mobile/presentation/pages/flashcard_review_screen.dart';
import 'package:aura_mobile/presentation/pages/quiz_screen.dart';

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
      backgroundColor: const Color(0xFF0a0a0c),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0a0a0c),
        title: Text(widget.deck.name, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () => _confirmDelete(),
          ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFc69c3a)))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Stats Overview ──
                if (stats != null) ...[
                  _statsGrid(stats),
                  const SizedBox(height: 16),
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
                    const SizedBox(width: 8),
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
                const SizedBox(height: 24),

                // ── Mastery Progress ──
                if (stats != null && stats.totalCards > 0) ...[
                  Text('Mastery Progress', style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  _masteryBar(stats),
                  const SizedBox(height: 24),
                ],

                // ── Cards List ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Cards (${state.currentCards.length})',
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                    IconButton(
                      icon: const Icon(Icons.add, color: Color(0xFFc69c3a)),
                      onPressed: () => _showAddCardDialog(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
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
        _statTile('Total', '${stats.totalCards}', Colors.white),
        _statTile('Due', '${stats.dueCards}', Colors.orangeAccent),
        _statTile('Mastered', '${stats.masteredCards}', Colors.greenAccent),
        _statTile('Avg Score', '${stats.averageScore.toStringAsFixed(0)}%', const Color(0xFFc69c3a)),
      ],
    );
  }

  Widget _statTile(String label, String value, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1a1a20),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(value, style: GoogleFonts.outfit(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: GoogleFonts.outfit(color: Colors.white38, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({required IconData icon, required String label, VoidCallback? onTap}) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: enabled ? const Color(0xFFc69c3a).withValues(alpha: 0.15) : const Color(0xFF1a1a20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: enabled ? const Color(0xFFc69c3a).withValues(alpha: 0.3) : Colors.white10,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: enabled ? const Color(0xFFc69c3a) : Colors.white24, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: enabled ? const Color(0xFFc69c3a) : Colors.white24,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _masteryBar(DeckStats stats) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 12,
            child: Row(
              children: [
                if (stats.masteredCards > 0)
                  Flexible(
                    flex: stats.masteredCards,
                    child: Container(color: Colors.greenAccent),
                  ),
                if (stats.learningCards > 0)
                  Flexible(
                    flex: stats.learningCards,
                    child: Container(color: Colors.orangeAccent),
                  ),
                if (stats.newCards > 0)
                  Flexible(
                    flex: stats.newCards,
                    child: Container(color: Colors.white24),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _legendDot('Mastered', Colors.greenAccent, stats.masteredCards),
            _legendDot('Learning', Colors.orangeAccent, stats.learningCards),
            _legendDot('New', Colors.white24, stats.newCards),
          ],
        ),
      ],
    );
  }

  Widget _legendDot(String label, Color color, int count) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text('$label ($count)', style: GoogleFonts.outfit(color: Colors.white38, fontSize: 11)),
      ],
    );
  }

  Widget _cardItem(Flashcard card) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            card.front,
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            card.back,
            style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (card.topic != null) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFc69c3a).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(card.topic!, style: GoogleFonts.outfit(color: const Color(0xFFc69c3a), fontSize: 10)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyCards() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: const Color(0xFF1a1a20), borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          const Icon(Icons.style_outlined, color: Colors.white24, size: 40),
          const SizedBox(height: 12),
          Text('No cards yet', style: GoogleFonts.outfit(color: Colors.white54)),
          const SizedBox(height: 4),
          Text('Tap + to add cards manually', style: GoogleFonts.outfit(color: Colors.white30, fontSize: 12)),
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
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a20),
        title: Text('Add Flashcard', style: GoogleFonts.outfit(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogField(frontCtrl, 'Question (Front)'),
              const SizedBox(height: 12),
              _dialogField(backCtrl, 'Answer (Back)', maxLines: 3),
              const SizedBox(height: 12),
              _dialogField(topicCtrl, 'Topic (optional)'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              if (frontCtrl.text.trim().isNotEmpty && backCtrl.text.trim().isNotEmpty) {
                Navigator.pop(ctx);
                ref.read(studyProvider.notifier).addCard(
                      frontCtrl.text.trim(),
                      backCtrl.text.trim(),
                      topic: topicCtrl.text.trim().isNotEmpty ? topicCtrl.text.trim() : null,
                    );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFc69c3a)),
            child: Text('Add', style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _dialogField(TextEditingController ctrl, String hint, {int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: GoogleFonts.outfit(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.outfit(color: Colors.white30),
        enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
        focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFc69c3a))),
      ),
    );
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a20),
        title: Text('Delete Deck?', style: GoogleFonts.outfit(color: Colors.white)),
        content: Text(
          'This will delete all cards, quiz history, and stats for "${widget.deck.name}".',
          style: GoogleFonts.outfit(color: Colors.white54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
              ref.read(studyProvider.notifier).deleteDeck(widget.deck.id);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text('Delete', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
