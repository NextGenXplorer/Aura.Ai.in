import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aura_mobile/domain/entities/flashcard.dart';
import 'package:aura_mobile/presentation/providers/study_provider.dart';
import 'package:aura_mobile/presentation/pages/deck_view_screen.dart';
import 'package:aura_mobile/domain/services/revision_scheduler_service.dart';
import 'package:aura_mobile/presentation/widgets/clay_components.dart';

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
      backgroundColor: ClayColors.obsidianBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Study Buddy',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: ClayColors.goldAccent,
          ),
        ),
        iconTheme: const IconThemeData(color: ClayColors.textDark),
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator(color: ClayColors.goldAccent))
          : RefreshIndicator(
              onRefresh: () => ref.read(studyProvider.notifier).loadDashboard(),
              color: ClayColors.goldAccent,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── Upcoming Exams ──
                  if (state.upcomingExams.isNotEmpty) ...[
                    _sectionTitle('Upcoming Exams'),
                    const SizedBox(height: 12),
                    ...state.upcomingExams.take(3).map((exam) {
                      final intensity = RevisionSchedulerService.getStudyIntensity(exam.daysRemaining);
                      return _examCard(exam.name, exam.daysRemaining, intensity.label, exam.id);
                    }),
                    const SizedBox(height: 28),
                  ],

                  // ── Your Decks ──
                  _sectionTitle('Your Decks'),
                  const SizedBox(height: 12),
                  if (state.decks.isEmpty)
                    _emptyState(
                      'No study decks yet',
                      'Upload a PDF or create a deck manually to get started!',
                    )
                  else
                    ...state.decks.map((deck) => _deckCard(deck)),

                  const SizedBox(height: 100),
                ],
              ),
            ),
      floatingActionButton: ClayButton(
        onTap: () => _showCreateDeckDialog(),
        borderRadius: 28,
        depth: 6.0,
        baseColor: ClayColors.goldAccent,
        highlightColor: ClayColors.goldHighlight,
        shadowColor: ClayColors.goldShadow,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add, color: ClayColors.goldHighlight, size: 20),
            const SizedBox(width: 8),
            Text(
              'New Deck', 
              style: GoogleFonts.outfit(color: ClayColors.goldHighlight, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.outfit(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: ClayColors.textDark,
      ),
    );
  }

  Widget _examCard(String name, int daysRemaining, String intensity, String examId) {
    final Color urgencyColor;
    final Color urgencyHighlight;
    final Color urgencyShadow;
    if (daysRemaining <= 3) {
      urgencyColor = ClayColors.redAccent;
      urgencyHighlight = ClayColors.redHighlight;
      urgencyShadow = ClayColors.redShadow;
    } else if (daysRemaining <= 7) {
      urgencyColor = ClayColors.orangeAccent;
      urgencyHighlight = ClayColors.orangeHighlight;
      urgencyShadow = ClayColors.orangeShadow;
    } else {
      urgencyColor = ClayColors.goldAccent;
      urgencyHighlight = ClayColors.goldHighlight;
      urgencyShadow = ClayColors.goldShadow;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: ClayContainer(
        borderRadius: 22,
        depth: 6.0,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            ClayContainer(
              width: 56,
              height: 56,
              borderRadius: 16,
              depth: 3.0,
              baseColor: urgencyColor.withOpacity(0.15),
              highlightColor: urgencyHighlight,
              shadowColor: urgencyShadow,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$daysRemaining',
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: urgencyColor,
                    ),
                  ),
                  Text(
                    'days',
                    style: GoogleFonts.outfit(fontSize: 10, color: urgencyColor, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: GoogleFonts.outfit(color: ClayColors.textDark, fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(intensity, style: GoogleFonts.outfit(color: urgencyColor, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: ClayColors.textHint, size: 20),
              onPressed: () => ref.read(studyProvider.notifier).deleteExam(examId),
            ),
          ],
        ),
      ),
    );
  }

  Widget _deckCard(FlashcardDeck deck) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: ClayButton(
        onTap: () {
          ref.read(studyProvider.notifier).selectDeck(deck);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => DeckViewScreen(deck: deck)),
          );
        },
        borderRadius: 22,
        padding: const EdgeInsets.all(18),
        baseColor: ClayColors.warmGrey,
        highlightColor: ClayColors.highlight,
        shadowColor: ClayColors.shadow,
        depth: 6.0,
        child: Row(
          children: [
            ClayContainer(
              width: 48,
              height: 48,
              borderRadius: 14,
              depth: 3.0,
              baseColor: ClayColors.goldAccent.withOpacity(0.15),
              highlightColor: ClayColors.highlight,
              shadowColor: ClayColors.shadow,
              child: const Icon(Icons.style_outlined, color: ClayColors.goldAccent),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    deck.name,
                    style: GoogleFonts.outfit(color: ClayColors.textDark, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    deck.description ?? 'No description',
                    style: GoogleFonts.outfit(color: ClayColors.textMuted, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: ClayColors.textHint),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(String title, String subtitle) {
    return ClayContainer(
      borderRadius: 24,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        children: [
          const Icon(Icons.school_outlined, color: ClayColors.goldAccent, size: 48),
          const SizedBox(height: 20),
          Text(title, style: GoogleFonts.outfit(color: ClayColors.textDark, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(subtitle, style: GoogleFonts.outfit(color: ClayColors.textMuted, fontSize: 13), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  void _showCreateDeckDialog() {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => ClayDialog(
        title: 'Create Study Deck',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClayTextField(
              controller: nameController,
              hintText: 'Deck name (e.g., Biology Ch. 5)',
              prefixIcon: Icons.folder_open_rounded,
            ),
            const SizedBox(height: 16),
            Text(
              'You can also say "create flashcards from PDF" in chat to auto-generate cards.',
              style: GoogleFonts.outfit(color: ClayColors.textMuted, fontSize: 12, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.outfit(color: ClayColors.textMuted, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          ClayButton(
            onTap: () async {
              if (nameController.text.trim().isNotEmpty) {
                Navigator.pop(ctx);
                await ref.read(studyProvider.notifier).createEmptyDeck(nameController.text.trim());
              }
            },
            borderRadius: 14,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            baseColor: ClayColors.goldAccent,
            highlightColor: ClayColors.goldHighlight,
            shadowColor: ClayColors.goldShadow,
            child: Text('Create', style: GoogleFonts.outfit(color: ClayColors.goldHighlight, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
