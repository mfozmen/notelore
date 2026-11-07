// The small Windows helper that applies a staged changed-files update after
// Notelore exits (#584). Built with `dart compile exe` and shipped beside the
// app; the app's update code writes it a job and starts it detached.
import 'dart:ffi';
import 'dart:io';

import 'package:notelore/src/update_apply.dart';
import 'package:path/path.dart' as p;

typedef _OpenProcessNative = IntPtr Function(Uint32, Int32, Uint32);
typedef _OpenProcessDart = int Function(int, int, int);
typedef _WaitNative = Uint32 Function(IntPtr, Uint32);
typedef _WaitDart = int Function(int, int);
typedef _CloseNative = Int32 Function(IntPtr);
typedef _CloseDart = int Function(int);
typedef _NotifyNative = Void Function(Int32, Uint32, Pointer<Void>, Pointer<Void>);
typedef _NotifyDart = void Function(int, int, Pointer<Void>, Pointer<Void>);

Future<void> main(List<String> args) async {
  if (args.length != 1) exit(64);
  UpdateJob job;
  try {
    job = UpdateJob.fromJson(File(args.single).readAsStringSync());
  } on Object {
    exit(78);
  }

  if (Platform.isWindows) _waitFor(job.parentPid);

  var ok = true;
  try {
    await applyUpdate(job, refreshIcons: Platform.isWindows ? _refreshIcons : null);
  } on Object catch (error) {
    ok = false;
    _log(job, '$error');
  }
  final app = File(p.join(job.install, job.executable));
  if (app.existsSync()) {
    await Process.start(
      app.path,
      const [],
      mode: ProcessStartMode.detached,
      workingDirectory: job.install,
    );
  }
  exit(ok ? 0 : 1);
}

/// Returns when process [pid] has ended, or at once if it is already gone.
void _waitFor(int pid) {
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final open = kernel32.lookupFunction<_OpenProcessNative, _OpenProcessDart>('OpenProcess');
  final wait = kernel32.lookupFunction<_WaitNative, _WaitDart>('WaitForSingleObject');
  final close = kernel32.lookupFunction<_CloseNative, _CloseDart>('CloseHandle');
  const synchronize = 0x00100000;
  const infinite = 0xFFFFFFFF;
  final handle = open(synchronize, 0, pid);
  if (handle == 0) return;
  wait(handle, infinite);
  close(handle);
}

/// SHChangeNotify(SHCNE_ASSOCCHANGED), as the setup's ChangesAssociations does:
/// without it the taskbar, Start and desktop shortcuts keep the old icon.
void _refreshIcons() {
  final shell32 = DynamicLibrary.open('shell32.dll');
  final notify = shell32.lookupFunction<_NotifyNative, _NotifyDart>('SHChangeNotify');
  const assocChanged = 0x08000000;
  const idList = 0x0000;
  notify(assocChanged, idList, nullptr, nullptr);
}

void _log(UpdateJob job, String message) {
  try {
    File(p.join(job.staging, 'update.log'))
        .writeAsStringSync('${DateTime.now().toIso8601String()} $message\n', mode: FileMode.append);
  } on FileSystemException {
    // The app is already gone; nothing else can report this.
  }
}
