class ContainerInfo {
  const ContainerInfo({
    required this.id,
    required this.name,
    required this.image,
    required this.status,
    required this.state,
  });

  final String id;
  final String name;
  final String image;
  final String status;
  final String state;

  bool get isRunning => state.toLowerCase() == 'running';

  factory ContainerInfo.fromDockerLine(String line) {
    final parts = line.split('|');
    if (parts.length != 5) {
      throw FormatException('Unexpected Docker output: $line');
    }
    return ContainerInfo(
      id: parts[0],
      name: parts[1],
      image: parts[2],
      status: parts[3],
      state: parts[4],
    );
  }
}

class SystemSnapshot {
  const SystemSnapshot({
    required this.loadAverage,
    required this.memoryUsedMb,
    required this.memoryTotalMb,
  });

  final String loadAverage;
  final int memoryUsedMb;
  final int memoryTotalMb;

  int get memoryPercent =>
      memoryTotalMb == 0 ? 0 : ((memoryUsedMb / memoryTotalMb) * 100).round();
}
