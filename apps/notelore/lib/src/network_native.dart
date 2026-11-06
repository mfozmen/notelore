/// Whether this device's connection costs by the byte (#767): mobile data, a
/// hotspot. Android and macOS answer over a channel, Windows through
/// PowerShell. Native code `flutter test` cannot run; [Session] takes a fake.
library;

import 'dart:io';

import 'package:flutter/services.dart';

// coverage:ignore-start
/// Null when it is not known.
Future<bool?> connectionMetered() async {
  try {
    if (Platform.isWindows) return await _windowsMetered();
    return await const MethodChannel('io.github.mfozmen.notelore/network')
        .invokeMethod<bool>('metered');
  } on Object {
    return null;
  }
}

/// Windows' cost of the connection to the internet: a hotspot or a metered
/// Wi-Fi is Fixed or Variable.
Future<bool?> _windowsMetered() async {
  final result = await Process.run('powershell', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    '[Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, '
        'ContentType=WindowsRuntime]::GetInternetConnectionProfile().GetConnectionCost()'
        '.NetworkCostType',
  ]);
  return switch ('${result.stdout}'.trim()) {
    'Unrestricted' => false,
    'Fixed' || 'Variable' => true,
    _ => null,
  };
}
// coverage:ignore-end
