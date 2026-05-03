import 'package:ai_tutor_python/services/instructions/instruction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Instruction.fromMap', () {
    test('parses sections and updatedAt', () {
      final instr = Instruction.fromMap('system_prompt', {
        'sections': {'intro': 'Hello', 'rules': 'Be nice'},
        'updatedAt': '2024-01-15T10:30:00.000Z',
      });
      expect(instr.id, 'system_prompt');
      expect(instr.sections['intro'], 'Hello');
      expect(instr.sections['rules'], 'Be nice');
      expect(instr.updatedAt, isNotNull);
    });

    test('tolerates missing sections and updatedAt', () {
      final instr = Instruction.fromMap('id', {});
      expect(instr.sections, isEmpty);
      expect(instr.updatedAt, isNull);
    });

    test('tolerates invalid updatedAt string', () {
      final instr = Instruction.fromMap('id', {
        'sections': {},
        'updatedAt': 'not-a-date',
      });
      expect(instr.updatedAt, isNull);
    });

    test('coerces non-string section values to string', () {
      final instr = Instruction.fromMap('id', {
        'sections': {'count': 42},
      });
      expect(instr.sections['count'], '42');
    });

    test('coerces null section values to empty string', () {
      final instr = Instruction.fromMap('id', {
        'sections': {'key': null},
      });
      expect(instr.sections['key'], '');
    });
  });

  group('Instruction.fromCosmos', () {
    test('reads id from document', () {
      final instr = Instruction.fromCosmos({
        'id': 'doc_id',
        'sections': {'text': 'hello'},
      });
      expect(instr.id, 'doc_id');
      expect(instr.sections['text'], 'hello');
    });
  });

  group('Instruction.copyWith', () {
    final base = Instruction(
      id: 'base',
      sections: {'a': '1'},
      updatedAt: DateTime(2024),
    );

    test('replaces id', () => expect(base.copyWith(id: 'new').id, 'new'));

    test('replaces sections', () {
      expect(base.copyWith(sections: {'b': '2'}).sections, {'b': '2'});
    });

    test('replaces updatedAt', () {
      final dt = DateTime(2025);
      expect(base.copyWith(updatedAt: dt).updatedAt, dt);
    });

    test('preserves all fields when nothing provided', () {
      final copy = base.copyWith();
      expect(copy.id, base.id);
      expect(copy.sections, base.sections);
      expect(copy.updatedAt, base.updatedAt);
    });
  });

  group('Instruction.toMap', () {
    test('includes required Cosmos fields', () {
      final map = Instruction(id: 'sys', sections: {'k': 'v'}).toMap();
      expect(map['id'], 'sys');
      expect(map['type'], 'instruction');
      expect(map['sections'], {'k': 'v'});
      expect(map['updatedAt'], isA<String>());
    });
  });
}
