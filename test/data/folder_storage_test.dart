import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/data/folder_storage.dart';

import '../fakes/fake_folder_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChannelFolderStorage (el canal con Kotlin)', () {
    const channel = MethodChannel(ChannelFolderStorage.channelName);
    late ChannelFolderStorage storage;
    final calls = <MethodCall>[];
    Object? Function(MethodCall) answer = (_) => null;

    setUp(() {
      calls.clear();
      answer = (_) => null;
      storage = ChannelFolderStorage();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return answer(call);
          });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('pickFolder y pickFile devuelven lo que dice Android', () async {
      answer = (c) => c.method == 'pickFolder' ? 'content://x' : '/cache/a.db';
      expect(await storage.pickFolder(), 'content://x');
      expect(await storage.pickFile(), '/cache/a.db');
    });

    test('cancelar el selector da nulo', () async {
      expect(await storage.pickFolder(), isNull);
      expect(await storage.pickFile(), isNull);
    });

    test('isAccessible pasa la carpeta; sin respuesta es falso', () async {
      expect(await storage.isAccessible('content://x'), isFalse);
      answer = (_) => true;
      expect(await storage.isAccessible('content://x'), isTrue);
      expect(calls.last.arguments, {'folder': 'content://x'});
    });

    test('writeFile envía carpeta, nombre y contenido', () async {
      await storage.writeFile(
        'content://x',
        'a.db',
        Uint8List.fromList([1, 2]),
      );
      expect(calls.single.method, 'writeFile');
      expect(calls.single.arguments, {
        'folder': 'content://x',
        'name': 'a.db',
        'bytes': Uint8List.fromList([1, 2]),
      });
    });

    test('listFiles devuelve los nombres', () async {
      answer = (_) => ['a.db', 'b.txt'];
      expect(await storage.listFiles('content://x'), ['a.db', 'b.txt']);
    });

    test('readFile devuelve el contenido', () async {
      answer = (_) => Uint8List.fromList([9, 8, 7]);
      expect(await storage.readFile('f', 'a.db'), [9, 8, 7]);
    });

    test('deleteFile y shareFile envían lo necesario', () async {
      await storage.deleteFile('f', 'a.db');
      await storage.shareFile('h.csv', 'text/csv', Uint8List.fromList([1]));
      expect(calls[0].arguments, {'folder': 'f', 'name': 'a.db'});
      expect(calls[1].method, 'shareFile');
      expect(calls[1].arguments['mime'], 'text/csv');
    });

    test('los códigos de error de Kotlin se traducen', () async {
      for (final (code, problem) in [
        ('no_access', StorageProblem.noAccess),
        ('not_found', StorageProblem.notFound),
        ('exists', StorageProblem.exists),
        ('io', StorageProblem.other),
        ('busy', StorageProblem.other),
      ]) {
        answer = (_) => throw PlatformException(code: code);
        await expectLater(
          storage.listFiles('f'),
          throwsA(
            isA<StorageException>().having(
              (e) => e.problem,
              'problem',
              problem,
            ),
          ),
        );
      }
    });

    test(
      'sin puente nativo (p. ej. en el PC) falla con un error claro',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await expectLater(
          storage.pickFolder(),
          throwsA(isA<StorageException>()),
        );
      },
    );

    test('los mensajes explican qué hacer', () {
      for (final p in StorageProblem.values) {
        expect(StorageException(p).message, isNotEmpty);
      }
    });
  });

  group('FakeFolderStorage (la carpeta falsa de los tests)', () {
    test('escribe, lista, lee y borra; no pisa nombres', () async {
      final s = FakeFolderStorage();
      await s.writeFile('f', 'a.db', Uint8List.fromList([1]));
      expect(await s.listFiles('f'), ['a.db']);
      expect(await s.readFile('f', 'a.db'), [1]);
      await expectLater(
        s.writeFile('f', 'a.db', Uint8List(0)),
        throwsA(isA<StorageException>()),
      );
      await s.deleteFile('f', 'a.db');
      expect(await s.listFiles('f'), isEmpty);
    });

    test('una carpeta rota falla en todo', () async {
      final s = FakeFolderStorage()..broken.add('f');
      expect(await s.isAccessible('f'), isFalse);
      await expectLater(s.listFiles('f'), throwsA(isA<StorageException>()));
    });
  });
}
