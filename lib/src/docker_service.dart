import 'dart:io';

import 'models.dart';

class DockerService {
  Future<List<ContainerInfo>> listContainers() async {
    final result = await _run([
      'ps',
      '-a',
      '--format',
      '{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}|{{.State}}',
    ]);
    return result
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .map(ContainerInfo.fromDockerLine)
        .toList();
  }

  Future<String> logs(String id, {int tail = 80}) =>
      _run(['logs', '--tail', '$tail', id]);

  Future<String> start(String id) => _run(['start', id]);
  Future<String> stop(String id) => _run(['stop', id]);
  Future<String> kill(String id) => _run(['kill', id]);

  Future<String> _run(List<String> arguments) async {
    final result = await Process.run('docker', arguments);
    final stdoutText = '${result.stdout}'.trim();
    final stderrText = '${result.stderr}'.trim();
    if (result.exitCode != 0) {
      throw DockerException(stderrText.isEmpty ? stdoutText : stderrText);
    }
    return stdoutText.isEmpty ? stderrText : stdoutText;
  }
}

class DockerException implements Exception {
  const DockerException(this.message);
  final String message;
  @override
  String toString() => message;
}
