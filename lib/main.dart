import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final themeMode = prefs.getString('theme') ?? 'system';
  runApp(NotesApp(themeMode: themeMode));
}

/* ================= APP ================= */

class NotesApp extends StatefulWidget {
  final String themeMode;
  const NotesApp({super.key, required this.themeMode});

  @override
  State<NotesApp> createState() => _NotesAppState();
}

class _NotesAppState extends State<NotesApp> {
  late ThemeMode mode;

  @override
  void initState() {
    super.initState();
    mode = _parse(widget.themeMode);
  }

  ThemeMode _parse(String s) {
    switch (s) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  void _toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      mode = mode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
      prefs.setString('theme', mode == ThemeMode.light ? 'light' : 'dark');
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Заметки',
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      darkTheme: ThemeData.dark(useMaterial3: true),
      home: NotesHomePage(onToggleTheme: _toggleTheme),
    );
  }
}

/* ================= MODEL ================= */

class Note {
  String id;
  String text;
  int color;
  String? groupId;
  bool numbered;

  Note({
    required this.id,
    required this.text,
    required this.color,
    this.groupId,
    this.numbered = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'color': color,
        'groupId': groupId,
        'numbered': numbered,
      };

  static Note fromJson(Map<String, dynamic> json) => Note(
        id: json['id'],
        text: json['text'],
        color: json['color'],
        groupId: json['groupId'],
        numbered: json['numbered'] ?? false,
      );
}

class Group {
  String id;
  String title;
  bool isPrivate;
  String? password;

  Group({
    required this.id,
    required this.title,
    this.isPrivate = false,
    this.password,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'isPrivate': isPrivate,
        'password': password,
      };

  static Group fromJson(Map<String, dynamic> json) => Group(
        id: json['id'],
        title: json['title'],
        isPrivate: json['isPrivate'] ?? false,
        password: json['password'],
      );
}

/* ================= STORE ================= */

class NotesStore extends ChangeNotifier {
  static const _key = 'notes_vault_store';
  final List<Note> _notes = [];
  final List<Group> _groups = [];
  bool loaded = false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      final map = jsonDecode(raw);
      final notes = (map['notes'] as List)
          .map((e) => Note.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final groups = (map['groups'] as List)
          .map((e) => Group.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      _notes.addAll(notes);
      _groups.addAll(groups);
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final map = {
      'notes': _notes.map((e) => e.toJson()).toList(),
      'groups': _groups.map((e) => e.toJson()).toList(),
    };
    await prefs.setString(_key, jsonEncode(map));
  }

  List<Note> get notes => List.unmodifiable(_notes);
  List<Group> get groups => List.unmodifiable(_groups);

  Future<void> add(Note note) async {
    _notes.add(note);
    await save();
    notifyListeners();
  }

  Future<void> update(Note note) async {
    final i = _notes.indexWhere((n) => n.id == note.id);
    if (i != -1) _notes[i] = note;
    await save();
    notifyListeners();
  }

  Future<void> remove(Note note) async {
    _notes.remove(note);
    await save();
    notifyListeners();
  }

  Future<void> addGroup(Group g) async {
    _groups.add(g);
    await save();
    notifyListeners();
  }

  Future<void> deleteGroup(String id) async {
    _groups.removeWhere((g) => g.id == id);
    _notes.removeWhere((n) => n.groupId == id);
    await save();
    notifyListeners();
  }

  List<Note> notesInGroup(String id) =>
      _notes.where((n) => n.groupId == id).toList();
}

/* ================= UI ================= */

class NotesHomePage extends StatefulWidget {
  final VoidCallback onToggleTheme;
  const NotesHomePage({super.key, required this.onToggleTheme});

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

  @override
  Widget build(BuildContext context) {
    if (!store.loaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Заметки'),
        actions: [
          IconButton(
            icon: const Icon(Icons.light_mode),
            onPressed: widget.onToggleTheme,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        child: const Icon(Icons.add),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate:
            const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2),
        itemCount: store.notes.length,
        itemBuilder: (context, i) {
          final n = store.notes[i];
          return GestureDetector(
            onTap: () => _openEditor(note: n),
            onLongPress: () async {
              final res = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Удалить заметку?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Отмена')),
                    TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Удалить')),
                  ],
                ),
              );
              if (res == true) store.remove(n);
            },
            child: Card(
              color: Color(n.color),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  n.text.isEmpty ? 'Без текста' : n.text,
                  overflow: TextOverflow.fade,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openEditor({Note? note}) async {
    final result = await showModalBottomSheet<Note>(
      context: context,
      isScrollControlled: true,
      builder: (_) => NoteEditor(note: note),
    );
    if (result != null) {
      if (note == null) {
        await store.add(result);
      } else {
        await store.update(result);
      }
    }
  }
}

/* ================= NOTE EDITOR ================= */

class NoteEditor extends StatefulWidget {
  final Note? note;
  const NoteEditor({super.key, this.note});

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late TextEditingController ctrl;
  bool numbered = false;

  @override
  void initState() {
    super.initState();
    ctrl = TextEditingController(text: widget.note?.text ?? '');
    numbered = widget.note?.numbered ?? false;
  }

  void _toggleNumbering() {
    setState(() => numbered = !numbered);
    if (numbered && ctrl.text.isEmpty) {
      ctrl.text = '1. ';
      ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
    }
  }

  void _onChanged(String value) {
    if (numbered && value.endsWith('\n')) {
      final lines = value.trim().split('\n');
      final next = '${lines.length + 1}. ';
      ctrl.text += next;
      ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        top: 16,
        left: 16,
        right: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(widget.note == null ? 'Новая заметка' : 'Редактировать'),
              const Spacer(),
              IconButton(
                onPressed: _toggleNumbering,
                icon: Icon(
                    numbered ? Icons.format_list_numbered : Icons.list_outlined),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: ctrl,
            minLines: 6,
            maxLines: 12,
            autofocus: true,
            onChanged: _onChanged,
            decoration: const InputDecoration(hintText: 'Текст заметки...'),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              FilledButton.icon(
                onPressed: () {
                  final n = (widget.note ??
                          Note(
                            id: DateTime.now()
                                .microsecondsSinceEpoch
                                .toString(),
                            text: '',
                            color: Colors.amber.value,
                          ))
                      .copyWith();
                  n.text = ctrl.text.trim();
                  n.numbered = numbered;
                  Navigator.pop(context, n);
                },
                icon: const Icon(Icons.check),
                label: const Text('Сохранить'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
                label: const Text('Отмена'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
