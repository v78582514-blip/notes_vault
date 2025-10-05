import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NotesApp());
}

class NotesApp extends StatefulWidget {
  const NotesApp({super.key});
  @override
  State<NotesApp> createState() => _NotesAppState();
}

class _NotesAppState extends State<NotesApp> {
  bool isDark = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Заметки',
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        cardTheme: const CardTheme(margin: EdgeInsets.all(8)),
      ),
      darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.dark),
      ),
      home: NotesHomePage(
        isDark: isDark,
        onThemeToggle: () => setState(() => isDark = !isDark),
      ),
    );
  }
}

class Note {
  String id;
  String text;
  int updatedAt;
  Note({required this.id, required this.text, required this.updatedAt});
  factory Note.newNote() => Note(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        text: '',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'updatedAt': updatedAt};
  static Note fromJson(Map<String, dynamic> j) =>
      Note(id: j['id'], text: j['text'], updatedAt: j['updatedAt']);
}

class NotesStore extends ChangeNotifier {
  static const _k = 'notes_v2';
  final List<Note> _items = [];
  bool _loaded = false;
  bool get isLoaded => _loaded;
  List<Note> get items => List.unmodifiable(_items);

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_k);
    if (raw != null) {
      final list = (jsonDecode(raw) as List)
          .cast<Map<String, dynamic>>()
          .map(Note.fromJson)
          .toList();
      _items..clear()..addAll(list);
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_k, jsonEncode(_items.map((e) => e.toJson()).toList()));
  }

  Future<void> add(Note n) async {
    _items.add(n);
    await _save();
    notifyListeners();
  }

  Future<void> update(Note n) async {
    final i = _items.indexWhere((x) => x.id == n.id);
    if (i != -1) {
      _items[i] = n..updatedAt = DateTime.now().millisecondsSinceEpoch;
      await _save();
      notifyListeners();
    }
  }

  Future<void> remove(String id) async {
    _items.removeWhere((n) => n.id == id);
    await _save();
    notifyListeners();
  }
}

class NotesHomePage extends StatefulWidget {
  final bool isDark;
  final VoidCallback onThemeToggle;
  const NotesHomePage({super.key, required this.isDark, required this.onThemeToggle});

  @override
  State<NotesHomePage> createState() => _NotesHomePageState();
}

class _NotesHomePageState extends State<NotesHomePage> {
  final store = NotesStore();

  @override
  void initState() {
    super.initState();
    store.addListener(() => setState(() {}));
    store.load();
  }

  Future<void> _edit({Note? src}) async {
    final res = await Navigator.of(context).push<Note>(
      MaterialPageRoute(builder: (_) => NoteEditor(note: src)),
    );
    if (res == null) return;
    if (src == null) {
      await store.add(res);
    } else {
      await store.update(res);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notes = store.items;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Заметки'),
        actions: [
          IconButton(
            icon: Icon(widget.isDark ? Icons.light_mode : Icons.dark_mode),
            onPressed: widget.onThemeToggle,
          ),
        ],
      ),
      body: !store.isLoaded
          ? const Center(child: CircularProgressIndicator())
          : notes.isEmpty
              ? const Center(child: Text('Нет заметок'))
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: notes.length,
                  itemBuilder: (context, i) {
                    final n = notes[i];
                    return GestureDetector(
                      onTap: () => _edit(src: n),
                      child: Card(
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  n.text,
                                  maxLines: 8,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                'Обновлено: ${DateTime.fromMillisecondsSinceEpoch(n.updatedAt).toLocal()}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: FloatingActionButton.extended(
          onPressed: () => _edit(),
          icon: const Icon(Icons.add),
          label: const Text('Новая'),
        ),
      ),
    );
  }
}

class NoteEditor extends StatefulWidget {
  final Note? note;
  const NoteEditor({super.key, this.note});
  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late final TextEditingController _ctrl;
  bool numbering = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.note?.text ?? '');
  }

  void _toggleNumbering() {
    setState(() => numbering = !numbering);
    if (numbering && !_ctrl.text.startsWith("1. ")) {
      _ctrl.text = "1. ${_ctrl.text}";
      _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.note == null ? 'Новая заметка' : 'Редактирование'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => Share.share(_ctrl.text),
          ),
          IconButton(
            icon: const Icon(Icons.format_list_numbered),
            onPressed: _toggleNumbering,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _ctrl,
          autofocus: true,
          maxLines: null,
          decoration: const InputDecoration(
            hintText: 'Текст заметки…',
            border: InputBorder.none,
          ),
          onChanged: (value) {
            if (numbering && value.endsWith('\n')) {
              final lines = value.trim().split('\n');
              _ctrl.text = '';
              for (int i = 0; i < lines.length; i++) {
                _ctrl.text += '${i + 1}. ${lines[i]}\n';
              }
              _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
            }
          },
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () {
                  final raw = _ctrl.text.trim();
                  final note = (widget.note ?? Note.newNote());
                  note.text = raw;
                  note.updatedAt = DateTime.now().millisecondsSinceEpoch;
                  Navigator.of(context).pop(note);
                },
                icon: const Icon(Icons.check),
                label: const Text('Сохранить'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close),
                label: const Text('Отмена'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
