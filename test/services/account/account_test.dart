import 'package:ai_tutor_python/services/account/account.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const base = Account(
    uid: 'uid-1',
    email: 'jan@example.com',
    firstName: 'Jan',
    lastName: 'Jansen',
    targetGoal: 'goal-1',
    mayUseGlobalKey: false,
  );

  group('Account getters', () {
    test('displayFirstName returns firstName', () {
      expect(base.displayFirstName, 'Jan');
    });

    test('fullName combines first and last name', () {
      expect(base.fullName, 'Jan Jansen');
    });

    test('requiresLocalKey is true when mayUseGlobalKey is false', () {
      expect(base.requiresLocalKey, isTrue);
    });

    test('requiresLocalKey is false when mayUseGlobalKey is true', () {
      const account = Account(
        uid: 'u',
        email: 'e',
        firstName: 'f',
        lastName: 'l',
        targetGoal: 'g',
        mayUseGlobalKey: true,
      );
      expect(account.requiresLocalKey, isFalse);
    });
  });

  group('Account.toMap', () {
    test('serializes all fields', () {
      final dt = DateTime.utc(2024, 1, 15);
      final account = Account(
        uid: 'uid-2',
        email: 'a@b.com',
        firstName: 'Anna',
        lastName: 'Bakker',
        targetGoal: 'goal-x',
        mayUseGlobalKey: true,
        createdAt: dt,
        updatedAt: dt,
        className: '5A',
      );
      final map = account.toMap();
      expect(map['id'], 'uid-2');
      expect(map['uid'], 'uid-2');
      expect(map['email'], 'a@b.com');
      expect(map['firstName'], 'Anna');
      expect(map['lastName'], 'Bakker');
      expect(map['targetGoal'], 'goal-x');
      expect(map['mayUseGlobalKey'], isTrue);
      expect(map['createdAt'], isA<String>());
      expect(map['updatedAt'], isA<String>());
      expect(map['className'], '5A');
    });

    test('omits timestamps when null', () {
      final map = base.toMap();
      expect(map.containsKey('createdAt'), isFalse);
      expect(map.containsKey('updatedAt'), isFalse);
    });

    test('serializes an unassigned class as an empty string', () {
      expect(base.toMap()['className'], '');
    });
  });

  group('Account.fromMap — className (#86)', () {
    Map<String, dynamic> doc({String? className}) => {
      'id': 'uid-3',
      'uid': 'uid-3',
      'email': 'c@d.com',
      'firstName': 'Cas',
      'lastName': 'Peeters',
      'targetGoal': '',
      if (className != null) 'className': className,
    };

    test('reads a stored class name', () {
      expect(Account.fromMap(doc(className: '5B')).className, '5B');
    });

    test('defaults to empty for docs that predate the field', () {
      expect(Account.fromMap(doc()).className, '');
    });
  });
}
