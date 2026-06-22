import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aura_mobile/domain/entities/flashcard.dart';
import 'package:aura_mobile/domain/entities/quiz.dart';
import 'package:aura_mobile/presentation/providers/study_provider.dart';
import 'package:aura_mobile/presentation/widgets/clay_components.dart';

class QuizScreen extends ConsumerStatefulWidget {
  final FlashcardDeck deck;
  const QuizScreen({super.key, required this.deck});

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen> {
  int? _selectedIndex; // Track by INDEX, not by text value
  bool _answered = false;
  bool _wasCorrect = false; // Store the result from provider
  final TextEditingController _fillBlankCtrl = TextEditingController();
  DateTime? _questionStartTime;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(studyProvider.notifier).startQuiz();
    });
    _questionStartTime = DateTime.now();
  }

  @override
  void dispose() {
    _fillBlankCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(studyProvider);

    if (state.isLoading) {
      return _scaffold(const Center(child: CircularProgressIndicator(color: Color(0xFFc69c3a))));
    }

    if (state.quizQuestions.isEmpty) {
      return _scaffold(Center(
        child: Text('Not enough cards for a quiz', style: GoogleFonts.outfit(color: ClayColors.textMuted)),
      ));
    }

    // Quiz complete
    if (state.currentQuizIndex >= state.quizQuestions.length) {
      return _scaffold(_resultsView(state));
    }

    final question = state.quizQuestions[state.currentQuizIndex];
    return _scaffold(_questionView(question, state));
  }

  Widget _scaffold(Widget body) {
    return Scaffold(
      backgroundColor: ClayColors.obsidianBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Quiz', style: GoogleFonts.outfit(color: ClayColors.textDark, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: ClayColors.textDark),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () {
            ref.read(studyProvider.notifier).clearQuiz();
            Navigator.pop(context);
          },
        ),
      ),
      body: body,
    );
  }

  Widget _questionView(QuizQuestion question, StudyState state) {
    final total = state.quizQuestions.length;
    final current = state.currentQuizIndex + 1;

    return Column(
      children: [
        // Progress
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
          child: ClayProgressBar(
            value: total > 0 ? current / total : 0,
          ),
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Question counter
              Text(
                'Question $current of $total',
                style: GoogleFonts.outfit(color: ClayColors.textMuted, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),

              // Score so far
              Row(
                children: [
                  _scoreChip('${state.quizCorrect}', ClayColors.greenAccent),
                  const SizedBox(width: 8),
                  _scoreChip('${state.quizWrong}', ClayColors.redAccent),
                ],
              ),
              const SizedBox(height: 24),

              // Question
              ClayContainer(
                borderRadius: 24,
                depth: 6.0,
                padding: const EdgeInsets.all(20),
                child: Text(
                  question.question,
                  style: GoogleFonts.outfit(color: ClayColors.textDark, fontSize: 17, height: 1.5, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 28),

              // Answer area
              if (question.type == 'multiple_choice' && question.options != null)
                ..._buildOptions(question)
              else
                _fillBlankInput(question),

              const SizedBox(height: 20),

              // Feedback after answering
              if (_answered) _feedbackSection(question),
            ],
          ),
        ),

        // Next button
        if (_answered)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ClayButton(
              onTap: _nextQuestion,
              baseColor: ClayColors.goldAccent,
              highlightColor: ClayColors.goldHighlight,
              shadowColor: ClayColors.goldShadow,
              borderRadius: 18,
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Text(
                  state.currentQuizIndex + 1 >= state.quizQuestions.length ? 'See Results' : 'Next Question',
                  style: GoogleFonts.outfit(color: ClayColors.goldHighlight, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Build option tiles, tracking by index to avoid duplicate-text bugs
  List<Widget> _buildOptions(QuizQuestion question) {
    final options = question.options!;
    // Find the correct answer's index (first match only)
    final correctIndex = options.indexWhere(
      (o) => o.trim().toLowerCase() == question.correctAnswer.trim().toLowerCase(),
    );

    return List.generate(options.length, (index) {
      return _optionTile(
        option: options[index],
        index: index,
        isCorrectOption: index == correctIndex,
        question: question,
      );
    });
  }

  Widget _optionTile({
    required String option,
    required int index,
    required bool isCorrectOption,
    required QuizQuestion question,
  }) {
    final isSelected = _selectedIndex == index;

    Color baseColor = ClayColors.warmGrey;
    Color highlightColor = ClayColors.highlight;
    Color shadowColor = ClayColors.shadow;
    IconData? trailingIcon;
    Color? iconColor;

    if (_answered) {
      if (isCorrectOption) {
        // Correct answer highlighted in green
        baseColor = ClayColors.greenAccent.withOpacity(0.12);
        highlightColor = ClayColors.greenHighlight;
        shadowColor = ClayColors.greenShadow;
        trailingIcon = Icons.check_circle_rounded;
        iconColor = ClayColors.greenAccent;
      } else if (isSelected) {
        // Selected wrong highlighted in red
        baseColor = ClayColors.redAccent.withOpacity(0.12);
        highlightColor = ClayColors.redHighlight;
        shadowColor = ClayColors.redShadow;
        trailingIcon = Icons.cancel_rounded;
        iconColor = ClayColors.redAccent;
      }
    } else if (isSelected) {
      baseColor = ClayColors.goldAccent.withOpacity(0.12);
      highlightColor = ClayColors.goldHighlight;
      shadowColor = ClayColors.goldShadow;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: ClayButton(
        onTap: _answered
            ? null
            : () {
                _submitMCAnswer(option, index, question);
              },
        borderRadius: 18,
        depth: isSelected ? 3.0 : 6.0,
        baseColor: baseColor,
        highlightColor: highlightColor,
        shadowColor: shadowColor,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                option,
                style: GoogleFonts.outfit(color: ClayColors.textDark, fontSize: 14, fontWeight: FontWeight.w600),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailingIcon != null) ...[
              const SizedBox(width: 8),
              Icon(trailingIcon, color: iconColor, size: 20),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fillBlankInput(QuizQuestion question) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClayTextField(
          controller: _fillBlankCtrl,
          enabled: !_answered,
          hintText: 'Type your answer...',
          prefixIcon: Icons.edit_note_rounded,
        ),
        if (!_answered) ...[
          const SizedBox(height: 16),
          ClayButton(
            onTap: _fillBlankCtrl.text.trim().isEmpty
                ? null
                : () => _submitFillBlank(_fillBlankCtrl.text.trim(), question),
            baseColor: ClayColors.goldAccent,
            highlightColor: ClayColors.goldHighlight,
            shadowColor: ClayColors.goldShadow,
            borderRadius: 16,
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: const Center(
              child: Text('Submit', style: TextStyle(color: ClayColors.goldHighlight, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _feedbackSection(QuizQuestion question) {
    final themeColor = _wasCorrect ? ClayColors.greenAccent : ClayColors.redAccent;

    return ClayContainer(
      borderRadius: 20,
      depth: 4.0,
      baseColor: themeColor.withOpacity(0.08),
      highlightColor: ClayColors.highlight,
      shadowColor: ClayColors.shadow,
      border: Border.all(color: themeColor.withOpacity(0.3), width: 1.0),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _wasCorrect ? Icons.check_circle_rounded : Icons.cancel_rounded,
                color: themeColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                _wasCorrect ? 'Correct!' : 'Incorrect',
                style: GoogleFonts.outfit(
                  color: themeColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          if (!_wasCorrect) ...[
            const SizedBox(height: 12),
            Text('Correct answer:', style: GoogleFonts.outfit(color: ClayColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              question.correctAnswer,
              style: GoogleFonts.outfit(color: ClayColors.textDark, fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ],
        ],
      ),
    );
  }

  Widget _scoreChip(String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3), width: 1.0),
      ),
      child: Text(
        value, 
        style: GoogleFonts.outfit(color: color, fontSize: 13, fontWeight: FontWeight.bold),
      ),
    );
  }

  /// Submit a multiple choice answer — uses index tracking
  void _submitMCAnswer(String answer, int index, QuizQuestion question) {
    final timeTaken = DateTime.now().difference(_questionStartTime!).inMilliseconds;
    final isCorrect = answer.trim().toLowerCase() == question.correctAnswer.trim().toLowerCase();

    setState(() {
      _selectedIndex = index;
      _answered = true;
      _wasCorrect = isCorrect;
    });

    ref.read(studyProvider.notifier).answerQuizQuestion(answer, timeTakenMs: timeTaken);
  }

  /// Submit a fill-in-the-blank answer
  void _submitFillBlank(String answer, QuizQuestion question) {
    final timeTaken = DateTime.now().difference(_questionStartTime!).inMilliseconds;

    setState(() {
      _selectedIndex = null;
      _answered = true;
    });

    // Let the provider determine correctness (it uses fuzzy matching)
    ref.read(studyProvider.notifier).answerQuizQuestion(answer, timeTakenMs: timeTaken);

    // Read back the result to update UI
    // The provider has already incremented quizCorrect or quizWrong
    final state = ref.read(studyProvider);
    final prevCorrect = state.quizCorrect;
    // If quizCorrect increased, the answer was correct
    // We check by comparing: before this answer, correct was (quizCorrect - was it correct?)
    // Simpler: re-check with same fuzzy logic
    setState(() {
      _wasCorrect = _fuzzyMatch(answer, question.correctAnswer);
    });
  }

  /// Same fuzzy matching logic as the provider, for UI consistency
  bool _fuzzyMatch(String userAnswer, String correctAnswer) {
    final userLower = userAnswer.trim().toLowerCase();
    final correctLower = correctAnswer.trim().toLowerCase();

    if (userLower == correctLower) return true;
    if (correctLower.contains(userLower) && userLower.length >= 3) return true;
    if (userLower.contains(correctLower)) return true;

    final stopWords = {'the', 'a', 'an', 'is', 'are', 'was', 'were', 'of', 'in', 'to', 'for',
      'and', 'or', 'but', 'that', 'this', 'with', 'from', 'by', 'on', 'at', 'it', 'its', 'as'};

    List<String> extractKeywords(String text) {
      return text
          .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
          .split(RegExp(r'\s+'))
          .where((w) => w.length >= 3 && !stopWords.contains(w))
          .toList();
    }

    final correctKeywords = extractKeywords(correctLower);
    final userKeywords = extractKeywords(userLower);
    if (correctKeywords.isEmpty) return false;

    int matched = 0;
    for (final keyword in correctKeywords) {
      if (userKeywords.any((uk) => uk == keyword || keyword.contains(uk) || uk.contains(keyword))) {
        matched++;
      }
    }

    return matched / correctKeywords.length >= 0.6;
  }

  void _nextQuestion() {
    setState(() {
      _selectedIndex = null;
      _answered = false;
      _wasCorrect = false;
      _fillBlankCtrl.clear();
      _questionStartTime = DateTime.now();
    });
  }

  Widget _resultsView(StudyState state) {
    final total = state.quizQuestions.length;
    final correct = state.quizCorrect;
    final percentage = total > 0 ? (correct / total * 100).round() : 0;

    Color scoreColor;
    String message;
    IconData icon;

    if (percentage >= 80) {
      scoreColor = ClayColors.greenAccent;
      message = 'Excellent work!';
      icon = Icons.star_rounded;
    } else if (percentage >= 60) {
      scoreColor = ClayColors.orangeAccent;
      message = 'Good effort! Keep studying.';
      icon = Icons.thumb_up_rounded;
    } else {
      scoreColor = ClayColors.redAccent;
      message = 'Keep practicing! You\'ll get there.';
      icon = Icons.refresh_rounded;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ClayContainer(
          borderRadius: 28,
          depth: 8.0,
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClayContainer(
                width: 80,
                height: 80,
                borderRadius: 40,
                depth: 4.0,
                baseColor: scoreColor.withOpacity(0.15),
                highlightColor: ClayColors.highlight,
                shadowColor: ClayColors.shadow,
                child: Icon(icon, color: scoreColor, size: 40),
              ),
              const SizedBox(height: 24),
              Text(
                '$percentage%', 
                style: GoogleFonts.outfit(color: scoreColor, fontSize: 44, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                message, 
                style: GoogleFonts.outfit(color: ClayColors.textMuted, fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _resultStat('Correct', '$correct', ClayColors.greenAccent),
                  const SizedBox(width: 28),
                  _resultStat('Wrong', '${state.quizWrong}', ClayColors.redAccent),
                  const SizedBox(width: 28),
                  _resultStat('Total', '$total', ClayColors.textDark),
                ],
              ),
              const SizedBox(height: 36),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ClayButton(
                    onTap: () {
                      ref.read(studyProvider.notifier).clearQuiz();
                      ref.read(studyProvider.notifier).startQuiz();
                      setState(() {
                        _selectedIndex = null;
                        _answered = false;
                        _wasCorrect = false;
                        _questionStartTime = DateTime.now();
                      });
                    },
                    borderRadius: 16,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    baseColor: ClayColors.warmGrey,
                    highlightColor: ClayColors.highlight,
                    shadowColor: ClayColors.shadow,
                    child: Text('Try Again', style: GoogleFonts.outfit(color: ClayColors.goldAccent, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 16),
                  ClayButton(
                    onTap: () {
                      ref.read(studyProvider.notifier).clearQuiz();
                      Navigator.pop(context);
                    },
                    borderRadius: 16,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    baseColor: ClayColors.goldAccent,
                    highlightColor: ClayColors.goldHighlight,
                    shadowColor: ClayColors.goldShadow,
                    child: Text('Done', style: GoogleFonts.outfit(color: ClayColors.goldHighlight, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: GoogleFonts.outfit(color: color, fontSize: 24, fontWeight: FontWeight.bold)),
        Text(label, style: GoogleFonts.outfit(color: ClayColors.textMuted, fontSize: 12)),
      ],
    );
  }
}
