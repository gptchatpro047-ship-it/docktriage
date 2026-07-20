import 'dart:io';

import 'models.dart';

class SystemMetrics {
  Future<SystemSnapshot> read() async {
    if (!Platform.isLinux) {
      return const SystemSnapshot(
        loadAverage: 'Linux only',
        memoryUsedMb: 0,
        memoryTotalMb: 0,
      );
    }

    final load = (await File('/proc/loadavg').readAsString()).split(' ').take(3).join(' ');
    final values = <String, int>{};
    for (final line in await File('/proc/meminfo').readAsLines()) {
      final match = RegExp(r'^(MemTotal|MemAvailable):\s+(\d+)').firstMatch(line);
      if (match != null) values[match.group(1)!] = int.parse(match.group(2)!);
    }
    final totalKb = values['MemTotal'] ?? 0;
    final availableKb = values['MemAvailable'] ?? 0;
    return SystemSnapshot(
      loadAverage: load,
      memoryUsedMb: (totalKb - availableKb) ~/ 1024,
      memoryTotalMb: totalKb ~/ 1024,
    );
  }
}
