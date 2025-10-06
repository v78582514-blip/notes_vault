import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

void main() => runApp(const NotesApp());

class NotesApp extends StatefulWidget {
  const NotesApp({super.key});
  @override
  State<NotesApp> createState() => _NotesAppState();
}

class _NotesAppState extends State<NotesApp> {
  bool _darkMode = false;
  final List<Map<String, dynamic>> _notes = [];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: _darkMode ? ThemeData.dark() : ThemeData.light(),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Notes Vault'),
          actions: [
            IconButton(
              icon: Icon(_darkMode ? Icons.light_mode : Icons.dark_mode),
              onPressed: () => setState(() => _darkMode = !_darkMode),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _createNote,
          child: const Icon(Icons.add),
        ),
        body: _notes.isEmpty
            ? const Center(child: Text('Нет заметок'))
            : GridView.count(
                crossAxisCount: 2,
                padding: const EdgeInsets.all(12),
                children: _notes.map(_buildNoteTile).toList(),
              ),
      ),
    );
  }

  Widget _buildNoteTile(Map<String, dynamic> note) {
    return GestureDetector(
      onTap: () => _editNote(note),
      onLongPress: () => _shareNote(note),
      child: Card(
        margin: const EdgeInsets.all(6),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(note['text'] ?? ''),
        ),
      ),
    );
  }

  void _createNote() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NoteEditor()),
    );
    if (result != null) setState(() => _notes.add({'text': result}));
  }

  void _editNote(Map<String, dynamic> note) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NoteEditor(initialText: note['text'])),
    );
    if (result != null) setState(() => note['text'] = result);
  }

  void _shareNote(Map<String, dynamic> note) {
    Share.share(note['text'] ?? '');
  }
}

class NoteEditor extends StatefulWidget {
  final String? initialText;
  const NoteEditor({super.key, this.initialText});

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late TextEditingController _controller;
  bool _smartNumbering = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Редактор'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () => Navigator.pop(context, _controller.text),
          ),
          IconButton(
            icon: const Icon(Icons.format_list_numbered),
            onPressed: () => setState(() => _smartNumbering = !_smartNumbering),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: _controller,
          maxLines: null,
          onChanged: (value) {
            if (_smartNumbering && value.endsWith('\n')) {
              final lines = value.split('\n');
              final numbered = List.generate(
                lines.length,
                (i) => lines[i].isEmpty ? '' : '${i + 1}. ${lines[i]}',
              );
              _controller.text = numbered.join('\n');
              _controller.selection = TextSelection.fromPosition(
                TextPosition(offset: _controller.text.length),
              );
            }
          },
          decoration: const InputDecoration(
            hintText: 'Введите текст заметки...',
            border: InputBorder.none,
          ),
        ),
      ),
    );
  }
}
