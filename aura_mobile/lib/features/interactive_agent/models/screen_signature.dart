/// Cheap, comparable fingerprint of the current screen, plus the plain-data
/// node match returned across the platform channel.
///
/// Feature: interactive-agent-mode
library;

import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

/// A comparable fingerprint of the current screen used to decide whether the
/// screen changed or settled, computed from a bounded shallow walk rather than
/// a full text extract (Req 7.1, D2).
@immutable
class ScreenSignature {
  final String packageName;
  final String activityName;

  /// Hash over the ordered key node identifiers from the bounded walk.
  final int structureHash;
  final int nodeCount;

  /// True when the foreground window is marked secure; UI actions must be
  /// refused (Req 6.7).
  final bool isSecureWindow;

  const ScreenSignature({
    required this.packageName,
    required this.activityName,
    required this.structureHash,
    required this.nodeCount,
    required this.isSecureWindow,
  });

  static const empty = ScreenSignature(
    packageName: '',
    activityName: '',
    structureHash: 0,
    nodeCount: 0,
    isSecureWindow: false,
  );

  factory ScreenSignature.fromWire(Map<Object?, Object?> map) {
    return ScreenSignature(
      packageName: (map['packageName'] ?? '').toString(),
      activityName: (map['activityName'] ?? '').toString(),
      structureHash: (map['structureHash'] as num?)?.toInt() ?? 0,
      nodeCount: (map['nodeCount'] as num?)?.toInt() ?? 0,
      isSecureWindow: map['isSecureWindow'] == true,
    );
  }

  /// Signature equality for change detection. Two signatures are equal when
  /// package, activity, structure hash, and node count all match — i.e. a text
  /// change that leaves structure intact does not register (documented
  /// limitation, Req 7.1 / Property 10).
  @override
  bool operator ==(Object other) =>
      other is ScreenSignature &&
      other.packageName == packageName &&
      other.activityName == activityName &&
      other.structureHash == structureHash &&
      other.nodeCount == nodeCount;

  @override
  int get hashCode =>
      Object.hash(packageName, activityName, structureHash, nodeCount);

  @override
  String toString() =>
      'ScreenSignature($packageName/$activityName, '
      'hash: $structureHash, nodes: $nodeCount, secure: $isSecureWindow)';
}

/// A node returned by a targeted query. Plain data — no native handle crosses
/// the channel; [handleToken] is valid only for the current query round
/// (Req 7.7, D4).
@immutable
class NodeMatch {
  final int handleToken;
  final String? viewId;
  final String? text;
  final bool editable;
  final bool clickable;
  final Rect bounds;

  const NodeMatch({
    required this.handleToken,
    required this.viewId,
    required this.text,
    required this.editable,
    required this.clickable,
    required this.bounds,
  });

  factory NodeMatch.fromWire(Map<Object?, Object?> map) {
    return NodeMatch(
      handleToken: (map['handleToken'] as num?)?.toInt() ?? -1,
      viewId: map['viewId'] as String?,
      text: map['text'] as String?,
      editable: map['editable'] == true,
      clickable: map['clickable'] == true,
      bounds: Rect.fromLTRB(
        (map['left'] as num?)?.toDouble() ?? 0,
        (map['top'] as num?)?.toDouble() ?? 0,
        (map['right'] as num?)?.toDouble() ?? 0,
        (map['bottom'] as num?)?.toDouble() ?? 0,
      ),
    );
  }

  @override
  String toString() =>
      'NodeMatch(token: $handleToken, viewId: $viewId, '
      'editable: $editable, clickable: $clickable)';
}
