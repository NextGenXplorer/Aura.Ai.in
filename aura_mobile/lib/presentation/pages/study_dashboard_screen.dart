import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aura_mobile/domain/entities/flashcard.dart';
import 'package:aura_mobile/presentation/providers/study_provider.dart';
import 'package:aura_mobile/presentation/pages/deck_view_screen.dart';
import 'package:aura_mobile/domain/services/revision_scheduler_service.dart';

class StudyDashboardScreen extends ConsumerStatefulWidget {
  const StudyDashboardScreen({super.key});

  @override
  ConsumerState<StudyDashboardScreen> createState() => _StudyDashboardScreenState();
}

class _StudyDashboardScreenState extends ConsumerState<StudyDashboardScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(studyProvider.notifier).loadDashboard());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(studyProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0c),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0a0a0c),
        title: Text(
          'Study Buddy',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: const Color(0xFFc69c3a),
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFc69c3a)))
          : RefreshIndicator(
              onRefresh: () => ref.read(studyProvider.notifier).loadDashboard(),
              color: const Color(0xFFc69c3a),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── Upcoming Exams ──
                  if (state.upcomingExams.isNotEmpty) ...[
                    _sectionTitle('Upcoming Exams'),
                    const SizedBox(height: 8),
                    ...state.upcomingExams.take(3).map((exam) {
                      final intensity = RevisionSchedulerService.getStudyIntensity(exam.daysRemaining);
                      return _examCard(exam.name, exam.daysRemaining, intensity.label, exam.id);
                    }),
                    const SizedBox(height: 24),
                  ],

                  // ── Your Decks ──
                  _sectionTitle('Your Decks'),
                  const SizedBox(height: 8),
                  if (state.decks.isEmpty)
                    _emptyState(
                      'No study decks yet',
                      'Upload a PDF or create a deck manually to get started!',
                    )
                  else
                    ...state.decks.map((deck) => _deckCard(deck)),

                  const SizedBox(height: 80),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDeckDialog(),
        backgroundColor: const Color(0xFFc69c3a),
        icon: const Icon(Icons.add, color: Colors.black),
        label: Text('New Deck', style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.outfit(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
  }

  Widget _examCard(String name, int daysRemaining, String intensity, String examId) {
    final Color urgencyColor;
    if (daysRemaining <= 3) {
      urgencyColor = Colors.redAccent;
    } else if (daysRemaining <= 7) {
      urgencyColor = Colors.orangeAccent;
    } else {
      urgencyColor = const Color(0xFFc69c3a);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: urgencyColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: urgencyColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$daysRemaining',
                  style: GoogleFonts.outfit(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: urgencyColor,
                  ),
                ),
                Text(
                  'days',
                  style: GoogleFonts.outfit(fontSize: 10, color: urgencyColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(intensity, style: GoogleFonts.outfit(color: urgencyColor, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white30, size: 20),
            onPressed: () => ref.read(studyProvider.notifier).deleteExam(examId),
          ),
        ],
      ),
    );
  }

  Widget _deckCard(FlashcardDeck deck) {
    return GestureDetector(
      onTap: () {
        ref.read(studyProvider.notifier).selectDeck(deck);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DeckViewScreen(deck: deck)),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1a1a20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFc69c3a).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.style, color: Color(0xFFc69c3a)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    deck.name,
                    style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    deck.description ?? 'No description',
                    style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white30),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          const Icon(Icons.school_outlined, color: Color(0xFFc69c3a), size: 48),
          const SizedBox(height: 16),
          Text(title, style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(subtitle, style: GoogleFonts.outfit(color: Colors.white38, fontSize: 13), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  void _showCreateDeckDialog() {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a20),
        title: Text('Create Study Deck', style: GoogleFonts.outfit(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: GoogleFonts.outfit(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Deck name (e.g., Biology Ch. 5)',
                hintStyle: GoogleFonts.outfit(color: Colors.white30),
                enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFc69c3a))),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'You can also say "create flashcards from PDF" in chat to auto-generate cards.',
              style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isNotEmpty) {
                Navigator.pop(ctx);
                await ref.read(studyProvider.notifier).createEmptyDeck(nameController.text.trim());
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFc69c3a)),
            child: Text('Create', style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
