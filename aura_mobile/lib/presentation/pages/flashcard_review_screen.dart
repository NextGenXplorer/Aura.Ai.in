import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aura_mobile/domain/entities/flashcard.dart';
import 'package:aura_mobile/presentation/providers/study_provider.dart';

class FlashcardReviewScreen extends ConsumerStatefulWidget {
  final FlashcardDeck deck;
  const FlashcardReviewScreen({super.key, required this.deck});

  @override
  ConsumerState<FlashcardReviewScreen> createState() => _FlashcardReviewScreenState();
}

class _FlashcardReviewScreenState extends ConsumerState<FlashcardReviewScreen>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  bool _isFlipped = false;
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  void _flipCard() {
    if (_isFlipped) {
      _flipController.reverse();
    } else {
      _flipController.forward();
    }
    setState(() => _isFlipped = !_isFlipped);
  }

  void _rateCard(String rating) {
    final queue = ref.read(studyProvider).reviewQueue;
    if (_currentIndex >= queue.length) return;

    final card = queue[_currentIndex];
    ref.read(studyProvider.notifier).reviewCard(card.id, rating);

    // Move to next card
    setState(() {
      _currentIndex++;
      _isFlipped = false;
      _flipController.reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(studyProvider);
    final queue = state.reviewQueue;
    final isComplete = _currentIndex >= queue.length;

    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0c),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0a0a0c),
        title: Text(
          isComplete ? 'Review Complete' : '${_currentIndex + 1} / ${queue.length}',
          style: GoogleFonts.outfit(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: isComplete ? _completionView(queue.length) : _reviewView(queue[_currentIndex]),
    );
  }

  Widget _reviewView(Flashcard card) {
    return Column(
      children: [
        // Progress bar
        LinearProgressIndicator(
          value: ref.read(studyProvider).reviewQueue.isNotEmpty
              ? _currentIndex / ref.read(studyProvider).reviewQueue.length
              : 0,
          backgroundColor: Colors.white10,
          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFc69c3a)),
          minHeight: 3,
        ),
        const SizedBox(height: 16),

        // Topic tag
        if (card.topic != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFc69c3a).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(card.topic!, style: GoogleFonts.outfit(color: const Color(0xFFc69c3a), fontSize: 12)),
          ),

        // Flashcard
        Expanded(
          child: GestureDetector(
            onTap: _flipCard,
            child: AnimatedBuilder(
              animation: _flipAnimation,
              builder: (context, child) {
                final angle = _flipAnimation.value * pi;
                final isFront = angle < pi / 2;
                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.001)
                    ..rotateY(angle),
                  child: isFront
                      ? _cardFace(card.front, 'TAP TO FLIP', const Color(0xFF1a1a20))
                      : Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()..rotateY(pi),
                          child: _cardFace(card.back, 'ANSWER', const Color(0xFF1e2a1e)),
                        ),
                );
              },
            ),
          ),
        ),

        // SM-2 Rating buttons (only visible after flip)
        if (_isFlipped) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            child: Row(
              children: [
                _ratingButton('Again', Colors.redAccent, '< 1min'),
                const SizedBox(width: 8),
                _ratingButton('Hard', Colors.orangeAccent, '~1 day'),
                const SizedBox(width: 8),
                _ratingButton('Good', Colors.blueAccent, '~3 days'),
                const SizedBox(width: 8),
                _ratingButton('Easy', Colors.greenAccent, '~7 days'),
              ],
            ),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            child: Text(
              'Tap card to see answer',
              style: GoogleFonts.outfit(color: Colors.white30, fontSize: 14),
            ),
          ),
      ],
    );
  }

  Widget _cardFace(String text, String label, Color bgColor) {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: GoogleFonts.outfit(color: Colors.white24, fontSize: 11, letterSpacing: 2),
          ),
          const SizedBox(height: 24),
          Text(
            text,
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _ratingButton(String label, Color color, String interval) {
    return Expanded(
      child: GestureDetector(
        onTap: () => _rateCard(label),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Text(label, style: GoogleFonts.outfit(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 2),
              Text(interval, style: GoogleFonts.outfit(color: color.withValues(alpha: 0.6), fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _completionView(int totalReviewed) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.greenAccent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, color: Colors.greenAccent, size: 40),
          ),
          const SizedBox(height: 24),
          Text('All Done!', style: GoogleFonts.outfit(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'You reviewed $totalReviewed cards',
            style: GoogleFonts.outfit(color: Colors.white54, fontSize: 14),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFc69c3a),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            child: Text('Back to Deck', style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
