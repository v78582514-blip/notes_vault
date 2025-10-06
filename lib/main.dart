import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const NotesVaultApp());

/* ---------------- APP ---------------- */

class NotesVaultApp extends StatefulWidget {
  const NotesVaultApp({super.key});
  @override
  State<NotesVaultApp> createState() => _NotesVaultAppState();
}

class _NotesVaultAppState extends State<NotesVaultApp> {
  ThemeMode _mode = ThemeMode.light;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Notes Vault',
      themeMode: _mode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        // Если вдруг будет ругаться — просто закомментируй строку ниже:
        // cardTheme: const CardThemeData(margin: EdgeInsets.all(8)),
      ),
      darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
      ),
      home: NotesHome(
        isDark: _mode == ThemeMode.dark,
        onToggleTheme: () =>
            setState(() => _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark),
      ),
    );
  }
}

/* ---------------- MODEL + STORE ---------------- */

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
      Note(id: j['id'], text: j['text'] ?? '', updatedAt: j['updatedAt'] ?? 0);
}

class NotesStore extends ChangeNotifier {
  static const _k = 'notes_v1_store';
  final List<Note> _list = [];
  bool _loaded = false;

  List<Note> get items => List.unmodifiable(_list);
  bool get loaded => _loaded;

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_k);
    if (raw != null && raw.isNotEmpty) {
      final List data = jsonDecode(raw);
      _list
        ..clear()
        ..addAll(data.map((e) => Note.fromJson(Map<String, dynamic>.from(e))));
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_k, jsonEncode(_list.map((e) => e.toJson()).toList()));
  }

  Future<void> add(Note n) async {
    _list.add(n);
    await _save();
    notifyListeners();
  }

  Future<void> update(Note n) async {
    final i = _list.indexWhere((e) => e.id == n.id);
    if (i != -1) {
      _list[i] = n..updatedAt = DateTime.now().millisecondsSinceEpoch;
      await _save();
      notifyListeners();
    }
  }

  Future<void> remove(String id) async {
    _list.removeWhere((e) => e.id == id);
    await _save();
    notifyListeners();
  }
}

/* ---------------- HOME ---------------- */

class NotesHome extends StatefulWidget {
  final bool isDark;
  final VoidCallback onToggleTheme;
  const NotesHome({super.key, required this.isDark, required this.onToggleTheme});

  @override
  State<NotesHome> createState() => _NotesHomeState();
}

class _NotesHomeState extends State<NotesHome> {
  final store = NotesStore();

  @override
  void initState() {
    super.initState();
    store.addListener(() => setState(() {}));
    store.load();
  }

  Future<void> _create() async {
    final res = await Navigator.of(context).push<Note>(
      MaterialPageRoute(builder: (_) => const NoteEditor()),
    );
    if (res != null) {
      await store.add(res);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Заметка создана')),
        );
      }
    }
  }

  Future<void> _edit(Note src) async {
    final res = await Navigator.of(context).push<Note>(
      MaterialPageRoute(builder: (_) => NoteEditor(note: src)),
    );
    if (res != null) {
      await store.update(res);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Изменения сохранены')),
        );
      }
    }
  }

  void _askDelete(Note n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить заметку?'),
        content: const Text('Действие нельзя отменить.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok == true) {
      await store.remove(n.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Удалено')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final notes = store.items;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes Vault'),
        actions: [
          IconButton(
            tooltip: 'Тема',
            icon: Icon(widget.isDark ? Icons.light_mode : Icons.dark_mode),
            onPressed: widget.onToggleTheme,
          ),
        ],
      ),
      body: !store.loaded
          ? const Center(child: CircularProgressIndicator())
          : notes.isEmpty
              ? const Center(child: Text('Нет заметок'))
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: notes.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemBuilder: (_, i) {
                    final n = notes[i];
                    return GestureDetector(
                      onTap: () => _edit(n),
                      onLongPress: () => _askDelete(n),
                      child: Card(
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  n.text.isEmpty ? 'Без текста' : n.text,
                                  maxLines: 8,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _fmt(n.updatedAt),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton(
        onPressed: _create,
        child: const Icon(Icons.add),
      ),
    );
  }
}

String _fmt(int ms) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int n) => n.toString().padLeft(2, '0');
  return 'Обновлено: ${two(dt.day)}.${two(dt.month)}.${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
}

/* ---------------- EDITOR ---------------- */

class NoteEditor extends StatefulWidget {
  final Note? note;
  const NoteEditor({super.key, this.note});

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late final TextEditingController _c;
  bool _numbered = false;
  TextEditingValue _last = const TextEditingValue();
  bool _internal = false;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.note?.text ?? '');
    _last = _c.value;
    _c.addListener(_onChanged);
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    _c.dispose();
    super.dispose();
  }

  void _toggleNumbering() {
    setState(() => _numbered = !_numbered);
    if (_numbered && _c.text.trim().isEmpty) {
      _internal = true;
      _c.text = '1. ';
      _c.selection = TextSelection.collapsed(offset: _c.text.length);
      _internal = false;
      _last = _c.value;
    }
  }

  void _onChanged() {
    if (_internal) return;
    final now = _c.value;
    final old = _last;
    final caret = now.selection.baseOffset;

    if (_numbered && caret >= 0) {
      final inserted =
          now.text.length == old.text.length + 1 &&
          now.selection.baseOffset == old.selection.baseOffset + 1;

      // Enter → следующий номер
      if (inserted && now.text.substring(0, caret).endsWith('\n')) {
        final before = now.text.substring(0, caret);
        final lines = before.split('\n');
        int count = 0;
        for (final l in lines) {
          final stripped = l.replaceFirst(RegExp(r'^\d+\. '), '');
          if (stripped.trim().isNotEmpty) count++;
        }
        final insert = '${count + 1}. ';
        _internal = true;
        _c.value = TextEditingValue(
          text: now.text.replaceRange(caret, caret, insert),
          selection: TextSelection.collapsed(offset: caret + insert.length),
        );
        _internal = false;
        _last = _c.value;
        return;
      }

      // Пустая строка → "1. "
      final start = now.text.lastIndexOf('\n', caret - 1) + 1;
      final end = now.text.indexOf('\n', caret);
      final e = end == -1 ? now.text.length : end;
      final line = now.text.substring(start, e);
      final hasPrefix = RegExp(r'^\d+\. ').hasMatch(line);
      final left = now.text.substring(start, caret);
      if (!hasPrefix && left.trim().isEmpty && line.trim().isEmpty) {
        const insert = '1. ';
        _internal = true;
        _c.value = TextEditingValue(
          text: now.text.replaceRange(start, start, insert),
          selection: TextSelection.collapsed(offset: caret + insert.length),
        );
        _internal = false;
        _last = _c.value;
        return;
      }
    }

    _last = now;
  }

  void _save() {
    final result = (widget.note ?? Note.newNote())
      ..text = _c.text.trimRight()
      ..updatedAt = DateTime.now().millisecondsSinceEpoch;
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.note == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'Новая заметка' : 'Редактирование'),
        actions: [
          IconButton(
            tooltip: 'Нумерация строк',
            icon: Icon(_numbered ? Icons.format_list_numbered : Icons.list),
            onPressed: _toggleNumbering,
          ),
          IconButton(
            tooltip: 'Сохранить',
            icon: const Icon(Icons.save),
            onPressed: _save,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _c,
            autofocus: true,
            minLines: 10,
            maxLines: null,
            decoration: const InputDecoration(
              hintText: 'Текст заметки…',
              border: InputBorder.none,
            ),
          ),
        ),
      ),
    );
  }
}
