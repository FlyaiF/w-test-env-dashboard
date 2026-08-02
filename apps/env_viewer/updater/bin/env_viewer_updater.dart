import 'dart:io';

import 'package:env_viewer_updater/env_viewer_updater.dart';

Future<void> main(List<String> argv) async {
  final UpdaterArgs args;
  try {
    args = UpdaterArgs.parse(argv);
  } on FormatException catch (e) {
    stderr.writeln('env_viewer_updater: ${e.message}');
    stderr.writeln(
      'usage: env_viewer_updater --wait-pid <pid> --install-path <dir> '
      '--zip <file> --platform <macos|windows> --log <file>',
    );
    exit(64);
  }
  exit(await Updater(args, SystemProcessOps()).run());
}
