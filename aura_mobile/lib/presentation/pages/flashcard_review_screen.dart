import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aura_mobile/domain/entities/flashcard.dart';
import 'package:aura_mobile/presentation/providers/study_provider.dart';
import 'package:aura_mobile/presentation/widgets/clay_components.dart';

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
      backgroundColor: ClayColors.obsidianBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          isComplete ? 'Review Complete' : '${_currentIndex + 1} / ${queue.length}',
          style: GoogleFonts.outfit(color: ClayColors.textDark, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: ClayColors.textDark),
      ),
      body: isComplete ? _completionView(queue.length) : _reviewView(queue[_currentIndex]),
    );
  }

  Widget _reviewView(Flashcard card) {
    return Column(
      children: [
        // Progress bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
          child: ClayProgressBar(
            value: ref.read(studyProvider).reviewQueue.isNotEmpty
                ? _currentIndex / ref.read(studyProvider).reviewQueue.length
                : 0,
          ),
        ),
        const SizedBox(height: 12),

        // Topic tag
        if (card.topic != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: ClayColors.goldAccent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: ClayColors.goldAccent.withOpacity(0.3), width: 1.0),
            ),
            child: Text(
              card.topic!, 
              style: GoogleFonts.outfit(color: ClayColors.goldAccent, fontSize: 11, fontWeight: FontWeight.bold),
            ),
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
                      ? _cardFace(card.front, 'TAP TO FLIP', ClayColors.warmGrey, ClayColors.highlight, ClayColors.shadow)
                      : Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()..rotateY(pi),
                          child: _cardFace(card.back, 'ANSWER', ClayColors.warmGrey, ClayColors.highlight, ClayColors.shadow),
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
                _ratingButton('Again', ClayColors.redAccent, ClayColors.redHighlight, ClayColors.redShadow, '< 1min'),
                const SizedBox(width: 8),
                _ratingButton('Hard', ClayColors.orangeAccent, ClayColors.orangeHighlight, ClayColors.orangeShadow, '~1 day'),
                const SizedBox(width: 8),
                _ratingButton('Good', ClayColors.blueAccent, ClayColors.blueHighlight, ClayColors.blueShadow, '~3 days'),
                const SizedBox(width: 8),
                _ratingButton('Easy', ClayColors.greenAccent, ClayColors.greenHighlight, ClayColors.greenShadow, '~7 days'),
              ],
            ),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            child: Text(
              'Tap card to see answer',
              style: GoogleFonts.outfit(color: ClayColors.textHint, fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
      ],
    );
  }

  Widget _cardFace(String text, String label, Color baseColor, Color highlightColor, Color shadowColor) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: ClayContainer(
        borderRadius: 28,
        depth: 8.0,
        baseColor: baseColor,
        highlightColor: highlightColor,
        shadowColor: shadowColor,
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: GoogleFonts.outfit(color: ClayColors.textHint, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),
            Text(
              text,
              style: GoogleFonts.outfit(color: ClayColors.textDark, fontSize: 18, height: 1.5, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _ratingButton(String label, Color color, Color highlight, Color shadow, String interval) {
    return Expanded(
      child: ClayButton(
        onTap: () => _rateCard(label),
        borderRadius: 16,
        depth: 5.0,
        baseColor: color.withOpacity(0.12),
        highlightColor: highlight,
        shadowColor: shadow,
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Text(label, style: GoogleFonts.outfit(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Text(interval, style: GoogleFonts.outfit(color: color.withOpacity(0.6), fontSize: 10, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _completionView(int totalReviewed) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: ClayContainer(
          borderRadius: 28,
          depth: 8.0,
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClayContainer(
                width: 72,
                height: 72,
                borderRadius: 36,
                depth: 4.0,
                baseColor: ClayColors.greenAccent.withOpacity(0.15),
                highlightColor: ClayColors.highlight,
                shadowColor: ClayColors.shadow,
                child: const Icon(Icons.check_rounded, color: ClayColors.greenAccent, size: 36),
              ),
              const SizedBox(height: 28),
              Text('All Done!', style: GoogleFonts.outfit(color: ClayColors.textDark, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                'You reviewed $totalReviewed cards',
                style: GoogleFonts.outfit(color: ClayColors.textMuted, fontSize: 14),
              ),
              const SizedBox(height: 32),
              ClayButton(
                onTap: () => Navigator.pop(context),
                baseColor: ClayColors.goldAccent,
                highlightColor: ClayColors.goldHighlight,
                shadowColor: ClayColors.goldShadow,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 32),
                child: const Center(
                  child: Text('Back to Deck', style: TextStyle(color: ClayColors.goldHighlight, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
