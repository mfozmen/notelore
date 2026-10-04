import 'package:flutter/material.dart';

void main() => runApp(const NoteloreApp());

/// The app shell; the chat and notes screens arrive with #66.
class NoteloreApp extends StatelessWidget {
  const NoteloreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notelore',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const Scaffold(body: Center(child: Text('Notelore'))),
    );
  }
}
