// Tests for ScreenSignature equality semantics.
//
// Feature: interactive-agent-mode, Property 10
//
// Property 10 states signature equality tracks STRUCTURE, not content: two
// signatures with the same package, activity, structure hash and node count are
// equal even if the underlying screen text differed, and differ when structure
// changes. The native walk produces the structureHash; this verifies the Dart
// model's equality contract the runner relies on for change detection.

import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile/features/interactive_agent/models/screen_signature.dart';

ScreenSignature _sig({
  String pkg = 'com.app',
  String act = 'MainActivity',
  int hash = 100,
  int nodes = 20,
  bool secure = false,
}) => ScreenSignature(
  packageName: pkg,
  activityName: act,
  structureHash: hash,
  nodeCount: nodes,
  isSecureWindow: secure,
);

void main() {
  group('Property 10: signatures track structure, not content', () {
    test('identical structure is equal regardless of secure flag', () {
      // The secure flag is a live property, not part of identity — two reads of
      // the same screen must compare equal for settle detection.
      expect(_sig(secure: false), equals(_sig(secure: true)));
    });

    test('a structure-hash change makes signatures differ', () {
      expect(_sig(hash: 100), isNot(equals(_sig(hash: 101))));
    });

    test('a node-count change makes signatures differ', () {
      expect(_sig(nodes: 20), isNot(equals(_sig(nodes: 21))));
    });

    test('a package or activity change makes signatures differ', () {
      expect(_sig(pkg: 'a'), isNot(equals(_sig(pkg: 'b'))));
      expect(_sig(act: 'X'), isNot(equals(_sig(act: 'Y'))));
    });

    test('equal signatures share a hashCode', () {
      expect(_sig().hashCode, _sig(secure: true).hashCode);
    });

    test('fromWire round-trips the fields', () {
      final s = ScreenSignature.fromWire(const {
        'packageName': 'com.x',
        'activityName': 'Home',
        'structureHash': 42,
        'nodeCount': 7,
        'isSecureWindow': true,
      });
      expect(s.packageName, 'com.x');
      expect(s.activityName, 'Home');
      expect(s.structureHash, 42);
      expect(s.nodeCount, 7);
      expect(s.isSecureWindow, isTrue);
    });

    test('empty signature is well-defined', () {
      expect(ScreenSignature.empty.packageName, '');
      expect(ScreenSignature.empty.nodeCount, 0);
    });
  });
}
