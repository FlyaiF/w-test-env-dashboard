import 'dart:io';

import 'package:env_viewer_updater/env_viewer_updater.dart';
import 'package:test/test.dart';

/// Drives [Updater] against real directories with scripted process behavior:
/// the "app" is already dead, extraction writes a canned build, and launching
/// either writes the startup marker (healthy build) or stays silent (broken).
class FakeOps implements ProcessOps {
  final String newBuildContent;
  final bool markerOnLaunch;
  final bool failExtract;
  final launched = <String>[];
  final killed = <int>[];

  FakeOps({
    this.newBuildContent = 'new',
    this.markerOnLaunch = true,
    this.failExtract = false,
  });

  @override
  Future<bool> isAlive(int pid) async => false;

  @override
  Future<void> extractZip(String zipPath, String destDir) async {
    if (failExtract) throw const UpdaterException('boom');
    Directory(destDir).createSync(recursive: true);
    File('$destDir${Platform.pathSeparator}env_viewer.exe')
        .writeAsStringSync(newBuildContent);
  }

  @override
  Future<int> launchApp(String executable, Map<String, String> env) async {
    launched.add(executable);
    final marker = env['ENV_VIEWER_UPDATE_MARKER'];
    if (markerOnLaunch && marker != null) {
      File(marker).writeAsStringSync('ok');
    }
    return 4242;
  }

  @override
  Future<void> killPid(int pid) async => killed.add(pid);
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('updater_test_');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  (UpdaterArgs, Directory) makeInstall() {
    final install = Directory('${tmp.path}/app')..createSync();
    File('${install.path}/env_viewer.exe').writeAsStringSync('old');
    File('${tmp.path}/update.zip').writeAsStringSync('zip-bytes');
    final args = UpdaterArgs(
      waitPid: 1,
      installPath: install.path,
      zipPath: '${tmp.path}/update.zip',
      platform: 'windows',
      logPath: '${tmp.path}/updater.log',
    );
    return (args, install);
  }

  Updater makeUpdater(UpdaterArgs args, FakeOps ops) => Updater(
        args,
        ops,
        exitTimeout: const Duration(seconds: 1),
        startupTimeout: const Duration(milliseconds: 400),
        pollInterval: const Duration(milliseconds: 20),
      );

  test('parses required options and rejects bad input', () {
    final args = UpdaterArgs.parse([
      '--wait-pid', '77',
      '--install-path', '/x/app',
      '--zip', '/x/u.zip',
      '--platform', 'macos',
      '--log', '/x/l.log',
    ]);
    expect(args.waitPid, 77);
    expect(args.platform, 'macos');

    expect(() => UpdaterArgs.parse(['--zip', 'a']), throwsFormatException);
    expect(
      () => UpdaterArgs.parse([
        '--wait-pid', '1',
        '--install-path', 'a',
        '--zip', 'b',
        '--platform', 'linux',
        '--log', 'c',
      ]),
      throwsFormatException,
    );
  });

  test('healthy update: swaps in new build, cleans backup and zip', () async {
    final (args, install) = makeInstall();
    final ops = FakeOps();

    expect(await makeUpdater(args, ops).run(), 0);

    expect(File('${install.path}/env_viewer.exe').readAsStringSync(), 'new');
    expect(Directory('${install.path}.backup').existsSync(), isFalse);
    expect(Directory('${install.path}.staging').existsSync(), isFalse);
    expect(File(args.zipPath).existsSync(), isFalse);
    expect(ops.launched.single, '${install.path}${Platform.pathSeparator}env_viewer.exe');
  });

  test('broken build: rolls back to old install and relaunches it', () async {
    final (args, install) = makeInstall();
    final ops = FakeOps(markerOnLaunch: false);

    expect(await makeUpdater(args, ops).run(), 1);

    expect(File('${install.path}/env_viewer.exe').readAsStringSync(), 'old');
    expect(Directory('${install.path}.backup').existsSync(), isFalse);
    expect(ops.killed, [4242]);
    // Launched twice: the broken new build, then the restored old one.
    expect(ops.launched, hasLength(2));
  });

  test('failed extraction: aborts leaving the install untouched', () async {
    final (args, install) = makeInstall();
    final ops = FakeOps(failExtract: true);

    expect(await makeUpdater(args, ops).run(), 2);

    expect(File('${install.path}/env_viewer.exe').readAsStringSync(), 'old');
    expect(ops.launched, isEmpty);
  });
}
