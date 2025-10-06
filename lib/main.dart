import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NotesVaultApp());
}

/* =================== APP =================== */

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
      title: 'Notes Vault',
      debugShowCheckedModeBanner: false,
      themeMode: _mode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          brightness: Brightness.dark,
          seedColor: Colors.indigo,
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

/* =================== MODEL & STORE =================== */

class Note {
  String id;
  String text;
  int updatedAt;
  String? groupId;

  Note({
    required this.id,
    required this.text,
    required this.updatedAt,
    this.groupId,
  });

  factory Note.newNote({String? groupId}) => Note(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        text: '',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        groupId: groupId,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'text': text, 'updatedAt': updatedAt, 'groupId': groupId};

  static Note fromJson(Map<String, dynamic> j) => Note(
        id: j['id'],
        text: (j['text'] ?? '') as String,
        updatedAt: (j['updatedAt'] ?? 0) as int,
        groupId: j['groupId'],
      );
}

class Group {
  String id;
  String title;
  int updatedAt;

  Group({required this.id, required this.title, required this.updatedAt});

  factory Group.newGroup(String title) => Group(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: title,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'updatedAt': updatedAt};

  static Group fromJson(Map<String, dynamic> j) => Group(
        id: j['id'],
        title: (j['title'] ?? '') as String,
        updatedAt: (j['updatedAt'] ?? 0) as int,
      );
}

class NotesStore extends ChangeNotifier {
  static const _k = 'notes_v2_with_groups_drag';
  final List<Note> _notes = [];
  final List<Group> _groups = [];
  bool _loaded = false;

  List<Note> get notes => List.unmodifiable(_notes);
  List<Group> get groups => List.unmodifiable(_groups);
  bool get loaded => _loaded;

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_k);
    if (raw != null && raw.isNotEmpty) {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final ns = (map['notes'] as List? ?? [])
          .map((e) => Note.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final gs = (map['groups'] as List? ?? [])
          .map((e) => Group.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      _notes..clear()..addAll(ns);
      _groups..clear()..addAll(gs);
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _k,
      jsonEncode({
        'notes': _notes.map((e) => e.toJson()).toList(),
        'groups': _groups.map((e) => e.toJson()).toList(),
      }),
    );
  }

  Future<void> addNote(Note n) async {
    _notes.add(n);
    await _save();
    notifyListeners();
  }

  Future<void> updateNote(Note n) async {
    final i = _notes.indexWhere((e) => e.id == n.id);
    if (i != -1) {
      _notes[i] = n..updatedAt = DateTime.now().millisecondsSinceEpoch;
      await _save();
      notifyListeners();
    }
  }

  Future<void> removeNote(String id) async {
    _notes.removeWhere((e) => e.id == id);
    await _save();
    notifyListeners();
  }

  Future<Group> createGroup(String title) async {
    final g = Group.newGroup(title);
    _groups.add(g);
    await _save();
    notifyListeners();
    return g;
  }

  Future<void> renameGroup(String id, String title) async {
    final i = _groups.indexWhere((g) => g.id == id);
    if (i != -1) {
      _groups[i].title = title;
      _groups[i].updatedAt = DateTime.now().millisecondsSinceEpoch;
      await _save();
      notifyListeners();
    }
  }

  Future<void> deleteGroup(String id) async {
    for (final n in _notes) {
      if (n.groupId == id) n.groupId = null;
    }
    _groups.removeWhere((g) => g.id == id);
    await _save();
    notifyListeners();
  }

  Future<void> moveNoteToGroup(String noteId, String? groupId) async {
    final idx = _notes.indexWhere((e) => e.id == noteId);
    if (idx == -1) return;
    final n = _notes[idx];
    n.groupId = groupId;
    n.updatedAt = DateTime.now().millisecondsSinceEpoch;
    await _save();
    notifyListeners();
  }
}

/* =================== HOME (GRID + DRAG&DROP) =================== */

class NotesHome extends StatefulWidget {
  final bool isDark;
  final VoidCallback onToggleTheme;
  const NotesHome({super.key, required this.isDark, required this.onToggleTheme});

  @override
  State<NotesHome> createState() => _NotesHomeState();
}

class _NotesHomeState extends State<NotesHome> {
  final store = NotesStore();
  String? _currentGroupId; // null = корень
  String? _hoverNoteId;    // подсветка цели
  String? _hoverGroupId;

  @override
  void initState() {
    super.initState();
    store.addListener(() => setState(() {}));
    store.load();
  }

  Future<void> _createNote() async {
    final res = await Navigator.of(context).push<Note>(
      MaterialPageRoute(builder: (_) => NoteEditor(groupId: _currentGroupId)),
    );
    if (res != null) await store.addNote(res);
  }

  Future<void> _edit(Note n) async {
    final res = await Navigator.of(context).push<Note>(
      MaterialPageRoute(builder: (_) => NoteEditor(note: n)),
    );
    if (res != null) await store.updateNote(res);
  }

  Future<void> _deleteNote(Note n) async {
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
    if (ok == true) await store.removeNote(n.id);
  }

  // Создать группу из двух заметок и поместить обе в неё
  Future<String> _ensureGroupForTwo(Note a, Note b) async {
    if (a.groupId != null) return a.groupId!;
    if (b.groupId != null) return b.groupId!;
    final title = _autoGroupTitle(a, b);
    final g = await store.createGroup(title);
    await store.moveNoteToGroup(a.id, g.id);
    await store.moveNoteToGroup(b.id, g.id);
    return g.id;
  }

  String _autoGroupTitle(Note a, Note b) {
    String pick(String t) {
      final first = t.trim().split('\n').first.trim();
      return first.isEmpty ? 'Заметка' : first;
    }
    final t1 = pick(a.text);
    final t2 = pick(b.text);
    return t1 == t2 ? t1 : '$t1 • $t2';
  }

  @override
  Widget build(BuildContext context) {
    final allGroups = store.groups;
    final allNotes = store.notes;
    final groupsToShow = _currentGroupId == null ? allGroups : <Group>[];
    final notesToShow = allNotes.where((n) => n.groupId == _currentGroupId).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentGroupId == null
            ? 'Notes Vault'
            : allGroups.firstWhere((g) => g.id == _currentGroupId).title),
        leading: _currentGroupId == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _currentGroupId = null),
              ),
        actions: [
          if (_currentGroupId != null)
            PopupMenuButton<String>(
              onSelected: (v) async {
                final gid = _currentGroupId!;
                if (v == 'rename') {
                  final t = await _askText(context, 'Название группы',
                      initial: allGroups.firstWhere((g) => g.id == gid).title);
                  if (t != null && t.trim().isNotEmpty) await store.renameGroup(gid, t.trim());
                } else if (v == 'delete') {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Удалить группу?'),
                      content: const Text('Заметки останутся в корне.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
                        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await store.deleteGroup(gid);
                    setState(() => _currentGroupId = null);
                  }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Переименовать группу')),
                PopupMenuItem(value: 'delete', child: Text('Удалить группу')),
              ],
            ),
          IconButton(
            tooltip: 'Тема',
            icon: Icon(widget.isDark ? Icons.light_mode : Icons.dark_mode),
            onPressed: widget.onToggleTheme,
          ),
        ],
      ),

      body: !store.loaded
          ? const Center(child: CircularProgressIndicator())
          : (groupsToShow.isEmpty && notesToShow.isEmpty)
              ? const Center(child: Text('Нет заметок'))
              : CustomScrollView(
                  slivers: [
                    if (groupsToShow.isNotEmpty) ...[
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
                          child: Text('Группы', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        sliver: SliverGrid(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.2),
                          delegate: SliverChildBuilderDelegate(
                            (context, i) {
                              final g = groupsToShow[i];
                              final count = allNotes.where((n) => n.groupId == g.id).length;
                              return DragTarget<_DragData>(
                                onWillAccept: (d) {
                                  setState(() => _hoverGroupId = g.id);
                                  return d != null;
                                },
                                onLeave: (_) => setState(() => _hoverGroupId = null),
                                onAccept: (d) async {
                                  setState(() => _hoverGroupId = null);
                                  await store.moveNoteToGroup(d.noteId, g.id);
                                },
                                builder: (context, candidate, rejected) => InkWell(
                                  onTap: () => setState(() => _currentGroupId = g.id),
                                  child: Card(
                                    shape: RoundedRectangleBorder(
                                      side: BorderSide(
                                        color: _hoverGroupId == g.id
                                            ? Theme.of(context).colorScheme.primary
                                            : Colors.transparent,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(g.title,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                          const Spacer(),
                                          Text('Заметок: $count',
                                              style: Theme.of(context).textTheme.bodySmall),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                            childCount: groupsToShow.length,
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 8)),
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
                          child: Text('Заметки', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],

                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final n = notesToShow[i];
                            return LongPressDraggable<_DragData>(
                              data: _DragData(noteId: n.id),
                              feedback: _NoteFeedback(text: _firstLine(n.text)),
                              childWhenDragging: _GhostCard(),
                              child: DragTarget<_DragData>(
                                onWillAccept: (d) {
                                  setState(() => _hoverNoteId = n.id);
                                  return d != null && d.noteId != n.id;
                                },
                                onLeave: (_) => setState(() => _hoverNoteId = null),
                                onAccept: (d) async {
                                  setState(() => _hoverNoteId = null);
                                  final src = store.notes.firstWhere((x) => x.id == d.noteId);
                                  final dst = n;
                                  if (dst.groupId != null) {
                                    await store.moveNoteToGroup(src.id, dst.groupId);
                                  } else {
                                    final gid = await _ensureGroupForTwo(src, dst);
                                    await store.moveNoteToGroup(src.id, gid);
                                  }
                                },
                                builder: (context, candidate, rejected) => _NoteCard(
                                  note: n,
                                  highlighted: _hoverNoteId == n.id,
                                  onTap: () => _edit(n),
                                  onDelete: () => _deleteNote(n),
                                ),
                              ),
                            );
                          },
                          childCount: notesToShow.length,
                        ),
                      ),
                    ),

                    const SliverToBoxAdapter(child: SizedBox(height: 80)),
                  ],
                ),

      floatingActionButton: FloatingActionButton(
        onPressed: _createNote,
        child: const Icon(Icons.add),
      ),
    );
  }
}

/* ---------- Drag helpers & Note card widgets ---------- */

class _DragData {
  final String noteId;
  _DragData({required this.noteId});
}

class _NoteFeedback extends StatelessWidget {
  final String text;
  const _NoteFeedback({required this.text});
  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 200),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.primary),
        ),
        child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _GhostCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
      child: const SizedBox.expand(),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final Note note;
  final bool highlighted;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _NoteCard({
    required this.note,
    required this.highlighted,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        side: BorderSide(
            color: highlighted ? Theme.of(context).colorScheme.primary : Colors.transparent),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Text(
                note.text.isEmpty ? 'Без текста' : note.text,
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _fmt(note.updatedAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Удалить',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onDelete,
                ),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

/* =================== EDITOR (нумерация ОК) =================== */

class NoteEditor extends StatefulWidget {
  final Note? note;
  final String? groupId;
  const NoteEditor({super.key, this.note, this.groupId});

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

  int _safeCaret(String t, int caret) =>
      math.max(0, math.min(caret, t.length));

  void _setValue(String t, int caret) {
    _internal = true;
    _c.value = TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: _safeCaret(t, caret)),
    );
    _internal = false;
    _last = _c.value;
  }

  void _toggleNumbering() {
    setState(() => _numbered = !_numbered);
    if (_numbered && _c.text.trim().isEmpty) {
      _setValue('1. ', 3);
    }
  }

  void _onChanged() {
    if (_internal) return;

    final now = _c.value;
    final old = _last;
    final caret = now.selection.baseOffset;

    final wasInsert = now.text.length == old.text.length + 1 &&
        now.selection.baseOffset == old.selection.baseOffset + 1;

    final wasDelete = now.text.length + 1 == old.text.length &&
        now.selection.baseOffset + 1 == old.selection.baseOffset;

    if (!_numbered) {
      _last = now;
      return;
    }

    // Enter → следующий номер
    if (wasInsert && caret > 0 && now.text[caret - 1] == '\n') {
      final before = now.text.substring(0, caret);
      final lines = before.split('\n');
      int count = 0;
      for (final l in lines) {
        final stripped = l.replaceFirst(RegExp(r'^\d+\. '), '');
        if (stripped.trim().isNotEmpty) count++;
      }
      final insert = '${count + 1}. ';
      _setValue(now.text.replaceRange(caret, caret, insert), caret + insert.length);
      return;
    }

    // Backspace у начала нумерованной строки → удалить весь префикс "N. "
    if (wasDelete && caret >= 0) {
      final lineStart = now.text.lastIndexOf('\n', caret - 1) + 1;
      final line = now.text.substring(lineStart);
      final m = RegExp(r'^(\d+\. )').firstMatch(line);
      if (m != null && caret <= lineStart + m.group(1)!.length) {
        final start = lineStart;
        final end = lineStart + m.group(1)!.length;
        final t = now.text.replaceRange(start, end, '');
        _setValue(t, start);
        return;
      }
    }

    _last = now;
  }

  void _save() {
    final result = (widget.note ?? Note.newNote(groupId: widget.groupId))
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

/* =================== HELPERS =================== */

Future<String?> _askText(BuildContext context, String title, {String? initial}) async {
  final c = TextEditingController(text: initial ?? '');
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Введите текст...'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('OK')),
      ],
    ),
  );
}

String _firstLine(String t) {
  final f = t.trim().split('\n').first.trim();
  return f.isEmpty ? 'Заметка' : f;
}

String _fmt(int ms) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int n) => n.toString().padLeft(2, '0');
  return 'Обновлено: ${two(dt.day)}.${two(dt.month)}.${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
}
