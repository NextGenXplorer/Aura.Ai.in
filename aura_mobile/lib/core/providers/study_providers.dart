import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aura_mobile/data/repositories/study_repository_impl.dart';
import 'package:aura_mobile/domain/repositories/study_repository.dart';
import 'package:aura_mobile/core/providers/repository_providers.dart';

final studyRepositoryImplProvider = Provider<StudyRepository>((ref) {
  final dbHelper = ref.watch(databaseHelperProvider);
  return StudyRepositoryImpl(dbHelper);
});
