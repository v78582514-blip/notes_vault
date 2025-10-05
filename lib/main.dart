import 'package:flutter/material.dart';

void main() => runApp(const NotesVaultHello());

class NotesVaultHello extends StatelessWidget {
  const NotesVaultHello({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'notes_vault',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: const Scaffold(
        body: Center(
          child: Text('Hello, notes_vault! 👋', style: TextStyle(fontSize: 20)),
        ),
      ),
    );
  }
}
