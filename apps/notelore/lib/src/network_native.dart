/// Whether this device's connection costs by the byte (#767): mobile data, a
/// hotspot. Android and macOS answer over a channel, Windows through
/// PowerShell. Native code `flutter test` cannot run; [Session] takes a fake.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

// coverage:ignore-start
/// Null when it is not known.
Future<bool?> connectionMetered() async {
  try {
    // Unanswered (a hung PowerShell, a silent monitor): asked, as when unknown.
    final answer = Platform.isWindows
        ? _windowsMetered()
        : const MethodChannel('io.github.mfozmen.notelore/network').invokeMethod<bool>('metered');
    return await answer.timeout(const Duration(seconds: 10));
  } on Object {
    return null;
  }
}

/// Windows' cost of the connection to the internet: a hotspot or a metered
/// Wi-Fi is Fixed or Variable.
Future<bool?> _windowsMetered() async {
  // By its full path: a bare name is looked up in the working folder first.
  final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
  final result = await Process.run(
    p.join(root, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe'),
    [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      '[Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, '
          'ContentType=WindowsRuntime]::GetInternetConnectionProfile().GetConnectionCost()'
          '.NetworkCostType',
    ],
  );
  return switch ('${result.stdout}'.trim()) {
    'Unrestricted' => false,
    'Fixed' || 'Variable' => true,
    _ => null,
  };
}
// coverage:ignore-end
