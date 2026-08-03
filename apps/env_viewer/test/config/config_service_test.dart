import 'dart:convert';
import 'dart:io';

import 'package:env_viewer/config/config_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'legacy credentials are scrubbed while current settings migrate',
    () async {
      final dir = await Directory.systemTemp.createTemp('env-viewer-config-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/config.json');
      await file.writeAsString(
        jsonEncode({
          'oracle': {
            'host': 'legacy-db',
            'username': 'legacy-user',
            'password': 'legacy-db-secret',
          },
          'ssh': {
            'default_username': 'legacy-ssh-user',
            'default_password': 'legacy-ssh-secret',
          },
          'ssh_tools': {
            'default_terminal_tool_id': 'terminal',
            'executable_paths': {'terminal': '/opt/terminal'},
            'password_mode': 'clipboard',
          },
          'db_tools': {
            'default_tool_id': 'dbeaver',
            'executable_paths': {'dbeaver': '/opt/dbeaver'},
          },
          'backend': {'base_url': 'http://catalog.internal:8080'},
          'future_setting': {'keep': true},
        }),
      );

      final config = await ConfigService.loadFromFile(file);

      expect(config.backendBaseUrl, 'http://catalog.internal:8080');
      expect(config.sshTools.defaultTerminalToolId, 'terminal');
      expect(config.sshTools.executablePaths['terminal'], '/opt/terminal');
      expect(config.sshTools.passwordMode, 'clipboard');
      expect(config.dbTools.defaultToolId, 'dbeaver');
      expect(config.dbTools.executablePaths['dbeaver'], '/opt/dbeaver');

      final rewrittenText = await file.readAsString();
      final rewritten = jsonDecode(rewrittenText) as Map<String, dynamic>;
      expect(rewritten.containsKey('ssh'), isFalse);
      expect(rewritten.containsKey('oracle'), isFalse);
      expect(rewritten['future_setting'], {'keep': true});
      expect(rewrittenText, isNot(contains('legacy-ssh-secret')));
      expect(rewrittenText, isNot(contains('legacy-db-secret')));
    },
  );

  test('new configs never serialize legacy credential sections', () {
    final json = AppConfig.empty().toJson();

    expect(json.containsKey('ssh'), isFalse);
    expect(json.containsKey('oracle'), isFalse);
    expect(json, containsPair('ssh_tools', isA<Map<String, dynamic>>()));
    expect(json, containsPair('db_tools', isA<Map<String, dynamic>>()));
  });
}
