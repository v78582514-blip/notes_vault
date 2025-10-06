import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('isDark') ?? true;
  runApp(NotesVaultApp(isDark: isDark));
}

class NotesVaultApp extends StatefulWidget {
  final bool isDark;
  const NotesVaultApp({super.key, required this.isDark});

  @override
  State<NotesVaultApp> createState() => _NotesVaultAppState();
}

class _NotesVaultAppState extends State<NotesVaultApp> {
  late bool isDark;

  @override
  void initState() {
    super.initState();
    isDark = widget.isDark;
  }

  void toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => isDark = !isDark);
    await prefs.setBool('isDark', isDark);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notes Vault',
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      debugShowCheckedModeBanner: false,
      home: NotesHomePage(onToggleTheme: toggleTheme),
    );
  }
}

// === МОДЕЛИ ===

class Note {
  String id;
  String title;
  String text;
  int colorHex;
  String? groupId;
  int updatedAt;

  Note({
    required this.id,
    required this.title,
    required this.text,
    required this.colorHex,
    this.groupId,
    required this.updatedAt,
  });

  factory Note.newNote() => Note(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: '',
        text: '',
        colorHex: Colors.amber.value,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'text': text,
        'colorHex': colorHex,
        'groupId': groupId,
        'updatedAt': updatedAt,
      };

  static Note fromJson(Map<String, dynamic> j) => Note(
        id: j['id'],
        title: j['title'],
        text: j['text'],
        colorHex: j['colorHex'] ?? Colors.amber.value,
        groupId: j['groupId'],
        updatedAt: j['updatedAt'] ?? 0,
      );
}

class Group {
  String id;
  String title;
  int colorHex;
  bool private;
  String? password;
  Group({
    required this.id,
    required this.title,
    required this.colorHex,
    this.private = false,
    this.password,
  });

  factory Group.newGroup() => Group(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: '',
        colorHex: Colors.blueAccent.value,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'colorHex': colorHex,
        'private': private,
        'password': password,
      };

  static Group fromJson(Map<String, dynamic> j) => Group(
        id: j['id'],
        title: j['title'],
        colorHex: j['colorHex'] ?? Colors.blueAccent.value,
        private: j['private'] ?? false,
        password: j['password'],
      );
}

// === ХРАНИЛИЩЕ ===

class VaultStore extends ChangeNotifier {
  static const _kNotes = 'notes_data_v1';
  static const _kGroups = 'groups_data_v1';

  final List<Note> _notes = [];
  final List<Group> _groups = [];

  List<Note> get notes => List.unmodifiable(_notes);
  List<Group> get groups => List.unmodifiable(_groups);

  bool _loaded = false;
  bool get loaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final nRaw = prefs.getString(_kNotes);
    final gRaw = prefs.getString(_kGroups);

    if (gRaw != null) {
      final data = (jsonDecode(gRaw) as List).cast<Map<String, dynamic>>();
      _groups.addAll(data.map(Group.fromJson));
    }
    if (nRaw != null) {
      final data = (jsonDecode(nRaw) as List).cast<Map<String, dynamic>>();
      _notes.addAll(data.map(Note.fromJson));
    }

    // Создание тестовых данных при первом запуске
    if (_notes.isEmpty && _groups.isEmpty) {
      _createDemoData();
    }

    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kNotes, jsonEncode(_notes.map((e) => e.toJson()).toList()));
    await prefs.setString(_kGroups, jsonEncode(_groups.map((e) => e.toJson()).toList()));
  }

  Future<void> addNote(Note note) async {
    _notes.add(note);
    await _save();
    notifyListeners();
  }

  Future<void> updateNote(Note note) async {
    final i = _notes.indexWhere((n) => n.id == note.id);
    if (i != -1) _notes[i] = note;
    await _save();
    notifyListeners();
  }

  Future<void> removeNote(Note note) async {
    _notes.removeWhere((n) => n.id == note.id);
    await _save();
    notifyListeners();
  }

  Future<void> addGroup(Group g) async {
    _groups.add(g);
    await _save();
    notifyListeners();
  }

  Future<void> updateGroup(Group g) async {
    final i = _groups.indexWhere((x) => x.id == g.id);
    if (i != -1) _groups[i] = g;
    await _save();
    notifyListeners();
  }

  Future<void> removeGroup(Group g) async {
    _groups.removeWhere((x) => x.id == g.id);
    _notes.removeWhere((n) => n.groupId == g.id);
    await _save();
    notifyListeners();
  }

  void _createDemoData() {
    final demoGroups = [
      Group(id: 'g1', title: 'Работа', colorHex: Colors.blue.value),
      Group(id: 'g2', title: 'Личное', colorHex: Colors.green.value),
      Group(id: 'g3', title: 'Идеи', colorHex: Colors.purple.value),
    ];
    final demoNotes = List.generate(
      6,
      (i) => Note(
        id: 'n$i',
        title: 'Заметка №${i + 1}',
        text: 'Это тестовая заметка номер ${i + 1}.\nМожно её отредактировать.',
        colorHex: [Colors.orange, Colors.teal, Colors.pink, Colors.cyan, Colors.indigo, Colors.lime][i].value,
        groupId: i < 3 ? 'g1' : null,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    _groups.addAll(demoGroups);
    _notes.addAll(demoNotes);
  }
}
class NotesHomePage extends StatefulWidget {
  final VoidCallback onToggleTheme;
  const NotesHomePage({super.key, required this.onToggleTheme});

  @override
  State<NotesHomePage> createState() => _NotesHomeState();
}

class _NotesHomeState extends State<NotesHomePage> {
  final store = VaultStore();
  String? openedGroupId;

  @override
  void initState() {
    super.initState();
    store.addListener(() => setState(() {}));
    store.load();
  }

  @override
  void dispose() {
    store.dispose();
    super.dispose();
  }

  Group? get openedGroup => store.groups.firstWhere(
        (g) => g.id == openedGroupId,
        orElse: () => Group(id: '', title: '', colorHex: Colors.transparent.value),
      );

  List<Note> get currentNotes => store.notes
      .where((n) => openedGroupId == null ? n.groupId == null : n.groupId == openedGroupId)
      .toList();

  void _editGroup([Group? g]) async {
    final newGroup = await showDialog<Group>(
      context: context,
      builder: (_) => _EditGroupDialog(group: g),
    );
    if (newGroup == null) return;
    g == null ? await store.addGroup(newGroup) : await store.updateGroup(newGroup);
  }

  void _editNote([Note? n]) async {
    final newNote = await showDialog<Note>(
      context: context,
      builder: (_) => _EditNoteDialog(note: n),
    );
    if (newNote == null) return;
    n == null ? await store.addNote(newNote) : await store.updateNote(newNote);
  }

  Future<void> _deleteGroup(Group g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить группу?'),
        content: const Text('Это действие удалит все заметки внутри группы.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok ?? false) await store.removeGroup(g);
  }

  Future<void> _deleteNote(Note n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить заметку?'),
        content: const Text('Это действие нельзя отменить.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok ?? false) await store.removeNote(n);
  }

  @override
  Widget build(BuildContext context) {
    if (!store.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(openedGroupId == null
            ? 'Notes Vault'
            : (openedGroup?.title.isNotEmpty ?? false)
                ? openedGroup!.title
                : 'Без названия'),
        actions: [
          IconButton(
            icon: const Icon(Icons.color_lens_outlined),
            onPressed: widget.onToggleTheme,
          ),
        ],
      ),
      body: Column(
        children: [
          // === ГРУППЫ ===
          Container(
            height: 140,
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: store.groups.length,
              itemBuilder: (_, i) {
                final g = store.groups[i];
                final color = Color(g.colorHex);
                final blurred = g.private;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: DragTarget<Note>(
                    onAccept: (note) async {
                      note.groupId = g.id;
                      await store.updateNote(note);
                    },
                    builder: (context, _, __) => GestureDetector(
                      onTap: () => setState(() => openedGroupId = g.id),
                      onLongPress: () => _editGroup(g),
                      child: Stack(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: 120,
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: color, width: 2),
                            ),
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  g.title.isEmpty ? 'Без названия' : g.title,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: Center(
                                    child: Icon(
                                      g.private ? Icons.lock : Icons.folder_open,
                                      color: g.private ? Colors.redAccent : color,
                                      size: 40,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (blurred)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                child: Container(
                                  width: 120,
                                  height: 120,
                                  color: Colors.black.withOpacity(0.2),
                                  child: const Center(
                                    child: Icon(Icons.lock_outline, size: 32, color: Colors.white70),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(),
          // === ЗАМЕТКИ ===
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.9,
              ),
              itemCount: currentNotes.length,
              itemBuilder: (_, i) {
                final n = currentNotes[i];
                final color = Color(n.colorHex);
                return LongPressDraggable<Note>(
                  data: n,
                  feedback: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: 140,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        n.title.isEmpty ? 'Без названия' : n.title,
                        style: const TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ),
                  ),
                  childWhenDragging: Opacity(opacity: 0.5, child: _NoteTile(note: n, onEdit: () => _editNote(n), onDelete: () => _deleteNote(n))),
                  child: _NoteTile(note: n, onEdit: () => _editNote(n), onDelete: () => _deleteNote(n)),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'addGroup',
            onPressed: () => _editGroup(),
            child: const Icon(Icons.folder_open),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'addNote',
            onPressed: () => _editNote(),
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
/* ============================ NOTE TILE ============================ */
class _NoteTile extends StatelessWidget {
  final Note note;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _NoteTile({super.key, required this.note, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final color = Color(note.colorHex);
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onEdit,
        onLongPress: onDelete,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // цветовая полоса
            Container(height: 6, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      note.title.isEmpty ? 'Без названия' : note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Text(
                        note.text,
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 14, color: Theme.of(context).textTheme.bodySmall?.color),
                        const SizedBox(width: 4),
                        Text(_fmtDate(note.updatedAt), style: Theme.of(context).textTheme.bodySmall),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Удалить',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: onDelete,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ============================ EDIT NOTE DIALOG ============================ */
class _EditNoteDialog extends StatefulWidget {
  final Note? note;
  const _EditNoteDialog({super.key, this.note});

  @override
  State<_EditNoteDialog> createState() => _EditNoteDialogState();
}

class _EditNoteDialogState extends State<_EditNoteDialog> {
  late TextEditingController _title;
  late TextEditingController _text;
  late int _colorHex;
  bool _numbering = false;

  @override
  void initState() {
    super.initState();
    final n = widget.note;
    _title = TextEditingController(text: n?.title ?? '');
    _text  = TextEditingController(text: n?.text ?? '');
    _colorHex = n?.colorHex ?? Colors.amber.value;
    _numbering = false; // локальная нумерация по желанию пользователя
  }

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickColor() async {
    final color = await _selectColorDialog(context, initial: Color(_colorHex));
    if (color != null) setState(() => _colorHex = color.value);
  }

  void _toggleNumbering() {
    setState(() => _numbering = !_numbering);
    if (_numbering) {
      // гарантируем "1. " в начале первой строки
      final t = _text.text;
      if (t.isEmpty || !RegExp(r'^\s*\d+\.\s').hasMatch(t.split('\n').first)) {
        final newT = (t.isEmpty) ? '1. ' : '1. $t';
        _text.value = TextEditingValue(
          text: newT,
          selection: TextSelection.collapsed(offset: newT.length),
        );
      }
    }
  }

  void _save() {
    final n = widget.note ??
        Note.newNote()
          ..updatedAt = DateTime.now().millisecondsSinceEpoch;
    n.title = _title.text.trim();
    n.text  = _text.text;
    n.colorHex = _colorHex;
    n.updatedAt = DateTime.now().millisecondsSinceEpoch;
    Navigator.pop(context, n);
  }

  @override
  Widget build(BuildContext context) {
    final color = Color(_colorHex);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // верхняя панель
            Container(
              height: 4,
              decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.note == null ? 'Новая заметка' : 'Редактирование',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: _numbering ? 'Отключить нумерацию' : 'Включить нумерацию',
                    onPressed: _toggleNumbering,
                    icon: Icon(_numbering ? Icons.format_list_numbered : Icons.format_list_bulleted),
                  ),
                  IconButton(
                    tooltip: 'Цвет',
                    onPressed: _pickColor,
                    icon: const Icon(Icons.palette_outlined),
                  ),
                  IconButton(
                    tooltip: 'Сохранить',
                    onPressed: _save,
                    icon: const Icon(Icons.check),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // поля
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    TextField(
                      controller: _title,
                      decoration: const InputDecoration(labelText: 'Заголовок', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: TextField(
                        controller: _text,
                        inputFormatters: [_NumberingFormatter(() => _numbering)],
                        expands: true,
                        minLines: null,
                        maxLines: null,
                        decoration: const InputDecoration(
                          hintText: 'Текст…',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.cancel),
                            label: const Text('Отмена'),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.check),
                            label: const Text('Сохранить'),
                            onPressed: _save,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ============================ EDIT GROUP DIALOG ============================ */
class _EditGroupDialog extends StatefulWidget {
  final Group? group;
  const _EditGroupDialog({super.key, this.group});

  @override
  State<_EditGroupDialog> createState() => _EditGroupDialogState();
}

class _EditGroupDialogState extends State<_EditGroupDialog> {
  late TextEditingController _title;
  late int _colorHex;
  bool _private = false;
  String? _password;

  @override
  void initState() {
    super.initState();
    final g = widget.group;
    _title = TextEditingController(text: g?.title ?? '');
    _colorHex = g?.colorHex ?? Colors.blueAccent.value;
    _private = g?.private ?? false;
    _password = g?.password;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickColor() async {
    final color = await _selectColorDialog(context, initial: Color(_colorHex));
    if (color != null) setState(() => _colorHex = color.value);
  }

  Future<void> _changePrivacy() async {
    if (!_private) {
      // включаем приватность -> спросить новый пароль
      final pass = await _askNewPassword(context);
      if (pass != null && pass.isNotEmpty) {
        setState(() {
          _private = true;
          _password = pass;
        });
      }
    } else {
      // выключаем приватность -> проверить старый пароль
      final ok = await _verifyOldPassword(context, _password ?? '');
      if (ok) {
        setState(() {
          _private = false;
          _password = null;
        });
      }
    }
  }

  void _save() {
    final g = widget.group ?? Group.newGroup();
    g.title = _title.text.trim();
    g.colorHex = _colorHex;
    g.private = _private;
    g.password = _password;
    Navigator.pop(context, g);
  }

  @override
  Widget build(BuildContext context) {
    final color = Color(_colorHex);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(height: 4, color: color),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(child: Text(widget.group == null ? 'Новая группа' : 'Редактирование группы',
                      style: Theme.of(context).textTheme.titleMedium)),
                  IconButton(tooltip: 'Цвет', onPressed: _pickColor, icon: const Icon(Icons.palette_outlined)),
                  IconButton(
                    tooltip: _private ? 'Снять приватность' : 'Сделать приватной',
                    onPressed: _changePrivacy,
                    icon: Icon(_private ? Icons.lock : Icons.lock_open),
                  ),
                  IconButton(tooltip: 'Сохранить', onPressed: _save, icon: const Icon(Icons.check)),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(
                    controller: _title,
                    decoration: const InputDecoration(labelText: 'Название группы', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(width: 18, height: 18, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Text('Цвет: #${_colorHex.toRadixString(16).padLeft(8, '0').toUpperCase()}',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(_private ? Icons.lock : Icons.lock_open, size: 18),
                      const SizedBox(width: 8),
                      Text(_private ? 'Приватная (пароль установлен)' : 'Обычная (без пароля)',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.cancel),
                      label: const Text('Отмена'),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.check),
                      label: const Text('Сохранить'),
                      onPressed: _save,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ============================ PASSWORD HELPERS ============================ */
Future<String?> _askNewPassword(BuildContext context) async {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Установить пароль'),
      content: TextField(
        controller: ctrl,
        obscureText: true,
        decoration: const InputDecoration(hintText: 'Новый пароль'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Готово')),
      ],
    ),
  );
}

Future<bool> _verifyOldPassword(BuildContext context, String current) async {
  final ctrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Подтвердите старый пароль'),
      content: TextField(
        controller: ctrl,
        obscureText: true,
        decoration: const InputDecoration(hintText: 'Старый пароль'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ОК')),
      ],
    ),
  );
  return ok == true && ctrl.text == current;
}

/* ============================ COLOR PICKER ============================ */
Future<Color?> _selectColorDialog(BuildContext context, {Color? initial}) async {
  final colors = _palette;
  Color? selected = initial;
  return showDialog<Color>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Выберите цвет'),
      content: SizedBox(
        width: 320,
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _ColorChip(
              color: Colors.transparent,
              label: 'Без цвета',
              selected: selected == null || selected == Colors.transparent,
              onTap: () => selected = Colors.transparent,
            ),
            for (final c in colors)
              StatefulBuilder(
                builder: (context, setInner) => _ColorChip(
                  color: c,
                  selected: selected?.value == c.value,
                  onTap: () => setInner(() => selected = c),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(context, selected), child: const Text('Готово')),
      ],
    ),
  );
}

class _ColorChip extends StatelessWidget {
  final Color color;
  final bool selected;
  final String? label;
  final VoidCallback onTap;
  const _ColorChip({required this.color, required this.selected, required this.onTap, this.label});

  @override
  Widget build(BuildContext context) {
    final bg = color == Colors.transparent ? Theme.of(context).colorScheme.surfaceVariant : color;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor,
                width: selected ? 3 : 1,
              ),
            ),
          ),
          if (label != null) ...[
            const SizedBox(width: 8),
            Text(label!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

const List<Color> _palette = [
  Color(0xFF64B5F6), Color(0xFF4DD0E1), Color(0xFF81C784), Color(0xFFFFF176),
  Color(0xFFFFD54F), Color(0xFFFF8A65), Color(0xFF9575CD), Color(0xFF90A4AE),
];

/* ============================ NUMBERING FORMATTER ============================ */
class _NumberingFormatter extends TextInputFormatter {
  final bool Function() isOn;
  _NumberingFormatter(this.isOn);

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (!isOn()) return newValue;

    final caret = newValue.selection.baseOffset;
    if (caret <= 0 || caret > newValue.text.length) return newValue;

    // если только что ввели перенос строки — продолжаем нумерацию
    if (newValue.text[caret - 1] == '\n') {
      final prevStart = newValue.text.lastIndexOf('\n', caret - 2) + 1;
      final prevLine = newValue.text.substring(prevStart, caret - 1);

      final numberLine = RegExp(r'^\s*(\d+)\.\s(.*)$');     // "N. something"
      final onlyNumber = RegExp(r'^\s*(\d+)\.\s*$');        // "N. " пустая

      final m1 = numberLine.firstMatch(prevLine);
      final m2 = onlyNumber.firstMatch(prevLine);

      if (m2 != null) {
        // предыдущая строка была "N. " без текста — не продолжаем список
        return newValue;
      }
      if (m1 != null) {
        final n = int.tryParse(m1.group(1) ?? '0') ?? 0;
        final insert = '${n + 1}. ';
        final text = newValue.text.substring(0, caret) + insert + newValue.text.substring(caret);
        return TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: caret + insert.length),
        );
      }
    }

    // обработка Backspace (удаление "N. " целиком, если курсор сразу после него)
    final isBackspace = oldValue.text.length == newValue.text.length + 1 &&
        oldValue.selection.baseOffset == oldValue.selection.extentOffset &&
        newValue.selection.baseOffset == oldValue.selection.baseOffset - 1;

    if (isBackspace) {
      final pos = newValue.selection.baseOffset;
      final lineStart = newValue.text.lastIndexOf('\n', pos - 1) + 1;
      final line = newValue.text.substring(lineStart, pos);
      final numberedPrefix = RegExp(r'^\s*\d+\.\s$'); // курсор стоял сразу после "N. "
      if (numberedPrefix.hasMatch(line)) {
        final prefixLen = line.length;
        final text = newValue.text.replaceRange(lineStart, pos, '');
        return TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: lineStart),
        );
      }
    }

    return newValue;
  }
}

/* ============================ UTILS ============================ */
String _fmtDate(int ms) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int n) => n.toString().padLeft(2, '0');
  final sameDay = DateTime.now().difference(dt).inDays == 0;
  return sameDay
      ? '${two(dt.hour)}:${two(dt.minute)}'
      : '${two(dt.day)}.${two(dt.month)}.${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
}
