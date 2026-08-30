// Issue #51 — a turtle run used to be completely silent: the output panel
// stayed empty for the whole run (turtle's Tk window blocks in
// `turtle.done()`, so there is nothing to print), and Stop cancelled the run
// without leaving a trace either. Both now push a faint meta line.

import 'package:ai_tutor_python/services/output/output_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:py_runner/py_runner.dart';

import '../../helpers/fake_py_runner.dart';
import '../../helpers/localization.dart';

const _turtleCode = 'import turtle\nturtle.forward(100)\nturtle.done()\n';

void main() {
  late FakePyRunner runner;
  late OutputService output;

  setUp(() {
    runner = FakePyRunner();
    output = OutputService(
      pyRunner: runner,
      localizations: testLocalizations(),
    );
  });

  tearDown(() async {
    await runner.dispose();
  });

  group('codeImportsTurtle', () {
    for (final code in [
      'import turtle',
      '   import turtle',
      'import turtle as t',
      'import math, turtle',
      'import turtle, math',
      'import turtle.shapes',
      'from turtle import *',
      'from turtle import Turtle, Screen',
      'from turtle.shapes import x',
      'x = 1\nimport turtle\n',
    ]) {
      test('true for ${code.replaceAll('\n', r'\n')}', () {
        expect(codeImportsTurtle(code), isTrue);
      });
    }

    for (final code in [
      '',
      'print("hello")',
      '# import turtle',
      'print("import turtle")',
      'import turtlegraphics',
      'from turtledemo import x',
      'turtle = 3',
    ]) {
      test('false for ${code.replaceAll('\n', r'\n')}', () {
        expect(codeImportsTurtle(code), isFalse);
      });
    }
  });

  test(
    'a turtle run announces the window before anything is printed',
    () async {
      await output.run(_turtleCode);

      expect(output.isRunning.value, isTrue);
      expect(output.lines.value, hasLength(1));
      final line = output.lines.value.single;
      expect(line.text, contains('turtle window is open'));
      expect(line.isMeta, isTrue);
      expect(line.isError, isFalse);
    },
  );

  test('a run without turtle stays silent until the program prints', () async {
    await output.run('print("hi")\n');

    expect(output.lines.value, isEmpty);
  });

  test('Stop leaves a meta line rather than a blank panel', () async {
    await output.run(_turtleCode);
    await output.stop();

    expect(runner.lastHandle.cancelled, isTrue);
    expect(output.lines.value, hasLength(2));
    expect(output.lines.value.first.text, contains('turtle window is open'));
    expect(output.lines.value.last.text, 'Stopped.');
    expect(output.lines.value.last.isMeta, isTrue);
  });

  test('Stop after a plain run still says so', () async {
    await output.run('while True: pass\n');
    expect(output.lines.value, isEmpty);

    await output.stop();

    expect(output.lines.value.single.text, 'Stopped.');
    expect(output.lines.value.single.isMeta, isTrue);
  });

  test('Stop with nothing running adds no line', () async {
    await output.stop();

    expect(output.lines.value, isEmpty);
  });

  test('Stop after the run already finished adds no line', () async {
    await output.run('print("hi")\n');
    runner.lastHandle.complete(
      const RunResult(status: RunStatus.ok, duration: Duration.zero),
    );
    // Let the `done` handler run.
    await Future<void>.delayed(Duration.zero);
    expect(output.isRunning.value, isFalse);

    await output.stop();

    expect(output.lines.value, isEmpty);
  });

  test('the turtle line survives program output arriving after it', () async {
    await output.run(_turtleCode);
    runner.lastHandle.emitStdout('drawing\n');
    await Future<void>.delayed(Duration.zero);

    expect(output.lines.value, hasLength(2));
    expect(output.lines.value.first.text, contains('turtle window is open'));
    expect(output.lines.value.first.isMeta, isTrue);
    expect(output.lines.value.last.text, 'drawing');
    expect(output.lines.value.last.isMeta, isFalse);
  });

  test('a second run clears the previous meta lines', () async {
    await output.run(_turtleCode);
    await output.stop();
    expect(output.lines.value, hasLength(2));

    await output.run('print("hi")\n');

    expect(output.lines.value, isEmpty);
  });
}
