import 'package:docktriage/src/models.dart';
import 'package:test/test.dart';

void main() {
  test('parses Docker formatted output', () {
    final item = ContainerInfo.fromDockerLine(
      'abc123|web|nginx:latest|Up 2 minutes|running',
    );
    expect(item.name, 'web');
    expect(item.image, 'nginx:latest');
    expect(item.isRunning, isTrue);
  });

  test('calculates memory percentage', () {
    const snapshot = SystemSnapshot(
      loadAverage: '0.10 0.20 0.30',
      memoryUsedMb: 2048,
      memoryTotalMb: 8192,
    );
    expect(snapshot.memoryPercent, 25);
  });
}
