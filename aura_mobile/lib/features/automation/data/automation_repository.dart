import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:aura_mobile/data/datasources/database_helper.dart';
import 'package:aura_mobile/features/automation/domain/automation_rule.dart';

final automationRepositoryProvider =
    Provider((ref) => AutomationRepository(DatabaseHelper()));

class AutomationRepository {
  final DatabaseHelper _dbHelper;
  static const _table = 'automation_rules';

  AutomationRepository(this._dbHelper);

  /// Inserts a new automation rule into the database.
  Future<void> insertRule(AutomationRule rule) async {
    final db = await _dbHelper.database;
    await db.insert(
      _table,
      _ruleToMap(rule),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Updates an existing automation rule.
  Future<void> updateRule(AutomationRule rule) async {
    final db = await _dbHelper.database;
    await db.update(
      _table,
      _ruleToMap(rule),
      where: 'id = ?',
      whereArgs: [rule.id],
    );
  }

  /// Deletes an automation rule by its ID.
  Future<void> deleteRule(String ruleId) async {
    final db = await _dbHelper.database;
    await db.delete(
      _table,
      where: 'id = ?',
      whereArgs: [ruleId],
    );
  }

  /// Retrieves a single automation rule by ID, or null if not found.
  Future<AutomationRule?> getRule(String ruleId) async {
    final db = await _dbHelper.database;
    final results = await db.query(
      _table,
      where: 'id = ?',
      whereArgs: [ruleId],
    );
    if (results.isEmpty) return null;
    return _mapToRule(results.first);
  }

  /// Retrieves all automation rules, ordered by creation date descending.
  Future<List<AutomationRule>> getAllRules() async {
    final db = await _dbHelper.database;
    final results = await db.query(
      _table,
      orderBy: 'createdAt DESC',
    );
    return results.map(_mapToRule).toList();
  }

  /// Returns the total number of automation rules in the database.
  Future<int> getRuleCount() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM $_table');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Updates only the lastExecutedAt timestamp for a given rule.
  Future<void> updateLastExecutedAt(String ruleId, DateTime time) async {
    final db = await _dbHelper.database;
    await db.update(
      _table,
      {
        'lastExecutedAt': time.millisecondsSinceEpoch,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [ruleId],
    );
  }

  // ---------------------------------------------------------------------------
  // Private mapping methods
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _ruleToMap(AutomationRule rule) {
    return {
      'id': rule.id,
      'name': rule.name,
      'triggerType': rule.triggerType.name,
      'scheduledTime': rule.scheduledTime?.millisecondsSinceEpoch,
      'repeatIntervalMinutes': rule.repeatInterval?.inMinutes,
      'condition': rule.condition,
      'checkIntervalMinutes': rule.checkInterval.inMinutes,
      'actionInstruction': rule.actionInstruction,
      'actionJson': rule.actionJson,
      'isEnabled': rule.isEnabled ? 1 : 0,
      'lastExecutedAt': rule.lastExecutedAt?.millisecondsSinceEpoch,
      'createdAt': rule.createdAt.millisecondsSinceEpoch,
      'updatedAt': rule.updatedAt.millisecondsSinceEpoch,
    };
  }

  AutomationRule _mapToRule(Map<String, dynamic> map) {
    return AutomationRule(
      id: map['id'] as String,
      name: map['name'] as String,
      triggerType: TriggerType.values.byName(map['triggerType'] as String),
      scheduledTime: map['scheduledTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['scheduledTime'] as int)
          : null,
      repeatInterval: map['repeatIntervalMinutes'] != null
          ? Duration(minutes: map['repeatIntervalMinutes'] as int)
          : null,
      condition: map['condition'] as String?,
      checkInterval:
          Duration(minutes: (map['checkIntervalMinutes'] as int?) ?? 60),
      actionInstruction: map['actionInstruction'] as String,
      actionJson: map['actionJson'] as String?,
      isEnabled: (map['isEnabled'] as int?) == 1,
      lastExecutedAt: map['lastExecutedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lastExecutedAt'] as int)
          : null,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
      updatedAt:
          DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int),
    );
  }
}
