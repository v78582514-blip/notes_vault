import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NotesVaultApp());
}

class NotesVaultApp extends StatefulWidget {
  const NotesVaultApp({super.key});

  @override
  State<NotesVaultApp> createState() => _NotesVaultAppState();
}

class _NotesVaultAppState extends State<NotesVaultApp> {
  bool isDark = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: NotesHome(
        toggleTheme: () => setState(() => isDark = !isDark),
      ),
    );
  }
}

class Note {
  String id;
  String text;
  String? groupId;
  DateTime updatedAt;

  Note({
    required this.id,
    required this.text,
    this.groupId,
    required this.updatedAt,
  });

  factory Note.newNote() =>
      Note(id: UniqueKey().toString(), text: '', updatedAt: DateTime.now());

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'groupId': groupId,
        'updatedAt': updatedAt.toIso8601String(),
      };

  static Note fromJson(Map<String, dynamic> json) => Note(
        id: json['id'],
        text: json['text'],
        groupId: json['groupId'],
        updatedAt: DateTime.parse(json['updatedAt']),
      );
}

class Group {
  String id;
  String title;
  List<String> noteIds;

  Group({required this.id, required this.title, required this.noteIds});

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'noteIds': noteIds,
      };

  static Group fromJson(Map<String, dynamic> json) => Group(
        id: json['id'],
        title: json['title'],
        noteIds: (json['noteIds'] as List).cast<String>(),
      );
}

class NotesStorage {
  static const _notesKey = 'notes_vault_notes';
  static const _groupsKey = 'notes_vault_groups';

  static Future<List<Note>> loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_notesKey);
    if (data == null) return [];
    return (jsonDecode(data) as List)
        .map((e) => Note.fromJson(e))
        .toList(growable: true);
  }

  static Future<void> saveNotes(List<Note> notes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _notesKey, jsonEncode(notes.map((e) => e.toJson()).toList()));
  }

  static Future<List<Group>> loadGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_groupsKey);
    if (data == null) return [];
    return (jsonDecode(data) as List)
        .map((e) => Group.fromJson(e))
        .toList(growable: true);
  }

  static Future<void> saveGroups(List<Group> groups) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _groupsKey, jsonEncode(groups.map((e) => e.toJson()).toList()));
  }
}

class NotesHome extends StatefulWidget {
  final VoidCallback toggleTheme;

  const NotesHome({super.key, required this.toggleTheme});

  @override
  State<NotesHome> createState() => _NotesHomeState();
}

class _NotesHomeState extends State<NotesHome> {
  List<Note> notes = [];
  List<Group> groups = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    notes = await NotesStorage.loadNotes();
    groups = await NotesStorage.loadGroups();
    setState(() {});
  }

  Future<void> _saveAll() async {
    await NotesStorage.saveNotes(notes);
    await NotesStorage.saveGroups(groups);
  }

  void _createNote() async {
    final newNote = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NoteEditor()),
    );
    if (newNote != null && newNote is Note) {
      setState(() => notes.add(newNote));
      _saveAll();
    }
  }

  void _editGroup(Group group) async {
    final titleController = TextEditingController(text: group.title);
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Редактировать группу'),
        content: TextField(
          controller: titleController,
          decoration: const InputDecoration(labelText: 'Название'),
        ),
        actions: [
          TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Отмена')),
          TextButton(
              onPressed: () {
                setState(() => group.title = titleController.text.trim());
                _saveAll();
                Navigator.pop(context);
              },
              child: const Text('Сохранить')),
        ],
      ),
    );
  }

  void _deleteGroup(Group group) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить группу?'),
        content: const Text('Все заметки останутся без группы.'),
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
    if (confirm == true) {
      for (final n in notes) {
        if (n.groupId == group.id) n.groupId = null;
      }
      groups.remove(group);
      _saveAll();
      setState(() {});
    }
  }

  void _deleteNote(Note n) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить заметку?'),
        content: const Text('Вы уверены, что хотите удалить эту заметку?'),
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
    if (confirm == true) {
      setState(() => notes.removeWhere((x) => x.id == n.id));
      _saveAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes Vault'),
        actions: [
          IconButton(
            onPressed: widget.toggleTheme,
            icon: const Icon(Icons.brightness_4_outlined),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: groups.isEmpty && notes.isEmpty
            ? const Center(child: Text('Нет заметок'))
            : GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                children: [
                  ...groups.map(
                    (g) => GestureDetector(
                      onTap: () => _editGroup(g),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(g.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              ...notes
                                  .where((n) => n.groupId == g.id)
                                  .take(3)
                                  .map((n) => Text(
                                        n.text.split('\n').first,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      )),
                              const Spacer(),
                              Align(
                                alignment: Alignment.bottomRight,
                                child: IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _deleteGroup(g),
                                ),
                              )
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  ...notes
                      .where((n) => n.groupId == null)
                      .map(
                        (n) => GestureDetector(
                          onTap: () async {
                            final edited = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => NoteEditor(note: n)),
                            );
                            if (edited != null && edited is Note) {
                              setState(() {
                                final i =
                                    notes.indexWhere((x) => x.id == edited.id);
                                notes[i] = edited;
                              });
                              _saveAll();
                            }
                          },
                          onLongPress: () async {
                            final group = await showMenu<Group>(
                              context: context,
                              position:
                                  const RelativeRect.fromLTRB(100, 100, 0, 0),
                              items: groups
                                  .map(
                                    (g) => PopupMenuItem<Group>(
                                      value: g,
                                      child: Text('Добавить в "${g.title}"'),
                                    ),
                                  )
                                  .toList(),
                            );
                            if (group != null) {
                              setState(() => n.groupId = group.id);
                              _saveAll();
                            }
                          },
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      n.text.isEmpty
                                          ? '(Пустая заметка)'
                                          : n.text,
                                      maxLines: 6,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Обновлено: ${n.updatedAt.day.toString().padLeft(2, '0')}.${n.updatedAt.month.toString().padLeft(2, '0')}.${n.updatedAt.year} ${n.updatedAt.hour.toString().padLeft(2, '0')}:${n.updatedAt.minute.toString().padLeft(2, '0')}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                  Align(
                                    alignment: Alignment.bottomRight,
                                    child: IconButton(
                                      icon:
                                          const Icon(Icons.delete_outline, size: 20),
                                      onPressed: () => _deleteNote(n),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNote,
        child: const Icon(Icons.add),
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
  late TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.note?.text ?? '');
  }

  void _save() {
    final text = controller.text.trim();
    if (text.isEmpty) return;
    Navigator.pop(
      context,
      (widget.note ?? Note.newNote())
        ..text = text
        ..updatedAt = DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.note == null ? 'Новая заметка' : 'Редактировать'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Сохранить'),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: controller,
          decoration: const InputDecoration(border: InputBorder.none),
          keyboardType: TextInputType.multiline,
          maxLines: null,
        ),
      ),
    );
  }
}
