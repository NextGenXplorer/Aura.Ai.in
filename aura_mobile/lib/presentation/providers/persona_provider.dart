import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aura_mobile/domain/entities/persona.dart';

final personaProvider = StateNotifierProvider<PersonaNotifier, PersonaState>((ref) {
  return PersonaNotifier();
});

class PersonaState {
  final Persona activePersona;
  final List<Persona> allPersonas;

  const PersonaState({
    required this.activePersona,
    required this.allPersonas,
  });

  PersonaState copyWith({
    Persona? activePersona,
    List<Persona>? allPersonas,
  }) {
    return PersonaState(
      activePersona: activePersona ?? this.activePersona,
      allPersonas: allPersonas ?? this.allPersonas,
    );
  }
}

class PersonaNotifier extends StateNotifier<PersonaState> {
  PersonaNotifier()
      : super(PersonaState(
          activePersona: Persona.builtIn.first,
          allPersonas: Persona.builtIn,
        )) {
    _loadSavedPersona();
  }

  Future<void> _loadSavedPersona() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString('active_persona_id') ?? 'default';
    final persona = Persona.getById(savedId);
    state = state.copyWith(activePersona: persona);
  }

  Future<void> setPersona(String personaId) async {
    final persona = Persona.getById(personaId);
    state = state.copyWith(activePersona: persona);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_persona_id', personaId);
  }
}
