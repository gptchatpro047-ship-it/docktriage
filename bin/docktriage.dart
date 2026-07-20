import 'dart:async';

import 'package:nocterm/nocterm.dart';
import 'package:docktriage/src/docker_service.dart';
import 'package:docktriage/src/models.dart';
import 'package:docktriage/src/openai_diagnostics.dart';
import 'package:docktriage/src/system_metrics.dart';

void main() => runApp(const DockTriageApp());

class DockTriageApp extends StatefulComponent {
  const DockTriageApp({super.key});
  @override
  State<DockTriageApp> createState() => _DockTriageState();
}

class _DockTriageState extends State<DockTriageApp> {
  final docker = DockerService();
  final metrics = SystemMetrics();
  final ai = OpenAiDiagnostics();
  List<ContainerInfo> containers = const [];
  SystemSnapshot snapshot = const SystemSnapshot(
    loadAverage: 'loading', memoryUsedMb: 0, memoryTotalMb: 0);
  int selected = 0;
  String output = 'Loading Docker containers…';
  String? pendingAction;
  bool busy = false;
  Timer? timer;

  ContainerInfo? get current => containers.isEmpty ? null : containers[selected];

  @override
  void initState() {
    super.initState();
    _refresh();
    timer = Timer.periodic(const Duration(seconds: 4), (_) => _refresh(silent: true));
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (busy) return;
    try {
      final results = await Future.wait([metrics.read(), docker.listContainers()]);
      setState(() {
        snapshot = results[0] as SystemSnapshot;
        containers = results[1] as List<ContainerInfo>;
        if (selected >= containers.length) selected = containers.isEmpty ? 0 : containers.length - 1;
        if (!silent) output = 'Refreshed successfully.';
      });
    } catch (error) {
      setState(() => output = 'Unable to refresh: $error');
    }
  }

  void _request(String action) {
    if (current == null) return;
    setState(() {
      pendingAction = action;
      output = 'Confirm $action for ${current!.name}? Press Y to continue or N to cancel.';
    });
  }

  Future<void> _confirm() async {
    final item = current;
    final action = pendingAction;
    if (item == null || action == null || busy) return;
    setState(() { busy = true; pendingAction = null; output = 'Running $action…'; });
    try {
      final result = switch (action) {
        'start' => await docker.start(item.id),
        'stop' => await docker.stop(item.id),
        'kill' => await docker.kill(item.id),
        _ => 'Unknown action',
      };
      setState(() => output = '$action completed: $result');
      await _refresh(silent: true);
    } catch (error) {
      setState(() => output = '$action failed: $error');
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> _showLogs() async {
    if (current == null || busy) return;
    setState(() { busy = true; output = 'Loading logs…'; });
    try {
      final value = await docker.logs(current!.id, tail: 60);
      setState(() => output = value.isEmpty ? '(container has no logs)' : value);
    } catch (error) {
      setState(() => output = 'Unable to read logs: $error');
    } finally { setState(() => busy = false); }
  }

  Future<void> _analyze() async {
    if (current == null || busy) return;
    setState(() { busy = true; output = 'GPT-5.6 is analysing selected logs…'; });
    try {
      final logs = await docker.logs(current!.id, tail: 80);
      final diagnosis = await ai.diagnose(current!, logs);
      setState(() => output = diagnosis);
    } catch (error) {
      setState(() => output = 'Diagnosis failed: $error');
    } finally { setState(() => busy = false); }
  }

  bool _onKey(LogicalKey key) {
    if (key == LogicalKey.keyQ || key == LogicalKey.escape) { shutdownApp(); return true; }
    if (pendingAction != null) {
      if (key == LogicalKey.keyY) unawaited(_confirm());
      if (key == LogicalKey.keyN) setState(() { pendingAction = null; output = 'Action cancelled.'; });
      return true;
    }
    if (key == LogicalKey.arrowUp && selected > 0) setState(() => selected--);
    if (key == LogicalKey.arrowDown && selected + 1 < containers.length) setState(() => selected++);
    if (key == LogicalKey.keyR) unawaited(_refresh());
    if (key == LogicalKey.keyL) unawaited(_showLogs());
    if (key == LogicalKey.keyA) unawaited(_analyze());
    if (key == LogicalKey.keyS && current != null) _request(current!.isRunning ? 'stop' : 'start');
    if (key == LogicalKey.keyK) _request('kill');
    return true;
  }

  @override
  Component build(BuildContext context) {
    return KeyboardListener(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Container(
        padding: const EdgeInsets.all(1),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(border: BoxBorder.all(color: Colors.cyan)),
            child: Row(children: [
              Text(' DOCKTRIAGE ', style: TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('Load ${snapshot.loadAverage}  '),
              Text('Memory ${snapshot.memoryUsedMb}/${snapshot.memoryTotalMb} MB (${snapshot.memoryPercent}%)'),
            ]),
          ),
          const SizedBox(height: 1),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(1),
              decoration: BoxDecoration(border: BoxBorder.all(color: Colors.blue)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(' CONTAINERS (${containers.length})', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                const Text('   NAME                 STATE       IMAGE'),
                ...containers.take(12).toList().asMap().entries.map((entry) {
                  final marker = entry.key == selected ? '▶' : ' ';
                  final item = entry.value;
                  final name = item.name.padRight(20).substring(0, 20);
                  final state = item.state.padRight(11).substring(0, 11);
                  return Text('$marker  $name $state ${item.image}',
                    style: TextStyle(color: entry.key == selected ? Colors.green : null));
                }),
                if (containers.isEmpty) const Text('No containers found. Is Docker running?'),
              ]),
            ),
          ),
          const SizedBox(height: 1),
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.all(1),
              decoration: BoxDecoration(border: BoxBorder.all(color: Colors.yellow)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(' LOGS / GPT-5.6 DIAGNOSIS', style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold)),
                const SizedBox(height: 1),
                Expanded(child: Text(output)),
              ]),
            ),
          ),
          const SizedBox(height: 1),
          const Text('↑/↓ Select   S Start/Stop   K Kill   L Logs   A AI diagnose   R Refresh   Q Quit'),
        ]),
      ),
    );
  }
}
