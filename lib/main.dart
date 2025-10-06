import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart' as crypto;

/* ===================== ENTRY ===================== */

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NotesVaultApp());
}

/* ===================== APP (theme persistence) ===================== */

class NotesVaultApp extends StatefulWidget {
  const NotesVaultApp({super.key});
  @override
  State<NotesVaultApp> createState() => _NotesVaultAppState();
}

class _NotesVaultAppState extends State<NotesVaultApp> {
  static const _kThemeDark = 'notes_vault_theme_dark';
  ThemeMode _mode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final sp = await SharedPreferences.getInstance();
    final dark = sp.getBool(_kThemeDark) ?? false;
    setState(() => _mode = dark ? ThemeMode.dark : ThemeMode.light);
  }

  Future<void> _toggleTheme() async {
    final next = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    setState(() => _mode = next);
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kThemeDark, next == ThemeMode.dark);
  }

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
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
      ),
      home: NotesHome(
        isDark: _mode == ThemeMode.dark,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}

/* ===================== DATA ===================== */

class Note {
  String id;
  String title;
  String text;
  int updatedAt;
  String? groupId;
  int? colorHex;

  Note({
    required this.id,
    required this.title,
    required this.text,
    required this.updatedAt,
    this.groupId,
    this.colorHex,
  });

  factory Note.newNote({String? groupId}) => Note(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: '',
        text: '',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        groupId: groupId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'text': text,
        'updatedAt': updatedAt,
        'groupId': groupId,
        'colorHex': colorHex,
      };

  static Note fromJson(Map<String, dynamic> j) => Note(
        id: j['id'],
        title: (j['title'] ?? '').toString(),
        text: (j['text'] ?? '').toString(),
        updatedAt: (j['updatedAt'] ?? 0) as int,
        groupId: j['groupId'],
        colorHex: j['colorHex'],
      );
}

class Group {
  String id;
  String title;
  int updatedAt;
  bool isPrivate;
  String? passHash;
  String? passHint;
  int? colorHex;

  Group({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.isPrivate = false,
    this.passHash,
    this.passHint,
    this.colorHex,
  });

  factory Group.newGroup(String title,
          {bool isPrivate = false, String? passHash, String? passHint, int? colorHex}) =>
      Group(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: title,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        isPrivate: isPrivate,
        passHash: passHash,
        passHint: passHint,
        colorHex: colorHex,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'updatedAt': updatedAt,
        'isPrivate': isPrivate,
        'passHash': passHash,
        'passHint': passHint,
        'colorHex': colorHex,
      };

  static Group fromJson(Map<String, dynamic> j) => Group(
        id: j['id'],
        title: (j['title'] ?? '').toString(),
        updatedAt: (j['updatedAt'] ?? 0) as int,
        isPrivate: (j['isPrivate'] ?? false) as bool,
        passHash: j['passHash'],
        passHint: j['passHint'],
        colorHex: j['colorHex'],
      );
}

class NotesStore extends ChangeNotifier {
  static const _kV5 = 'notes_v5_titles_colors';
  static const _kV4 = 'notes_v4_priv_drag';

  final List<Note> _notes = [];
  final List<Group> _groups = [];
  bool _loaded = false;

  final Set<String> _unlocked = {};

  List<Note> get notes => List.unmodifiable(_notes);
  List<Group> get groups => List.unmodifiable(_groups);
  bool get loaded => _loaded;

  bool isUnlocked(String groupId) => _unlocked.contains(groupId);
  void markUnlocked(String groupId) => _unlocked.add(groupId);

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    String? raw = sp.getString(_kV5) ?? sp.getString(_kV4);
    if (raw != null && raw.isNotEmpty) {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final ns = (map['notes'] as List? ?? [])
          .map((e) => Note.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final gs = (map['groups'] as List? ?? [])
          .map((e) => Group.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      for (final n in ns) {
        if (n.title.trim().isEmpty) n.title = _firstLine(n.text);
      }

      _notes..clear()..addAll(ns);
      _groups..clear()..addAll(gs);
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _kV5,
      jsonEncode({
        'notes': _notes.map((e) => e.toJson()).toList(),
        'groups': _groups.map((e) => e.toJson()).toList(),
      }),
    );
  }

  Future<void> addNote(Note n) async { _notes.add(n); await _save(); notifyListeners(); }
  Future<void> removeNote(String id) async { _notes.removeWhere((e) => e.id == id); await _save(); notifyListeners(); }

  Future<void> updateNote(Note n) async {
    final i = _notes.indexWhere((e) => e.id == n.id);
    if (i != -1) {
      _notes[i] = n..updatedAt = DateTime.now().millisecondsSinceEpoch;
      await _save(); notifyListeners();
    }
  }

  Future<Group> createGroup(String title,
      {bool isPrivate = false, String? passHash, String? passHint, int? colorHex}) async {
    final g = Group.newGroup(title,
        isPrivate: isPrivate, passHash: passHash, passHint: passHint, colorHex: colorHex);
    _groups.add(g); await _save(); notifyListeners(); return g;
  }

  Future<void> renameGroup(String id, String title) async {
    final i = _groups.indexWhere((g) => g.id == id);
    if (i != -1) {
      _groups[i].title = title;
      _groups[i].updatedAt = DateTime.now().millisecondsSinceEpoch;
      await _save(); notifyListeners();
    }
  }

  Future<void> setGroupColor(String id, int? colorHex) async {
    final i = _groups.indexWhere((g) => g.id == id);
    if (i != -1) {
      _groups[i].colorHex = colorHex;
      _groups[i].updatedAt = DateTime.now().millisecondsSinceEpoch;
      await _save(); notifyListeners();
    }
  }

  // deleteGroup с опцией удаления заметок
  Future<void> deleteGroup(String id, {bool deleteNotes = false}) async {
    if (deleteNotes) {
      _notes.removeWhere((n) => n.groupId == id);
    } else {
      for (final n in _notes) {
        if (n.groupId == id) n.groupId = null; // заметки в корень
      }
    }
    _groups.removeWhere((g) => g.id == id);
    _unlocked.remove(id);
    await _save(); notifyListeners();
  }

  Future<void> moveNoteToGroup(String noteId, String? groupId) async {
    final idx = _notes.indexWhere((e) => e.id == noteId);
    if (idx == -1) return;
    final n = _notes[idx];
    n.groupId = groupId;
    n.updatedAt = DateTime.now().millisecondsSinceEpoch;
    await _save(); notifyListeners();
  }

  Future<void> setGroupPassword(String id,
      {required String passHash, String? hint}) async {
    final i = _groups.indexWhere((g) => g.id == id);
    if (i != -1) {
      _groups[i].isPrivate = true;
      _groups[i].passHash = passHash;
      _groups[i].passHint = hint;
      _groups[i].updatedAt = DateTime.now().millisecondsSinceEpoch;
      await _save(); notifyListeners();
    }
  }

  Future<void> clearGroupPassword(String id) async {
    final i = _groups.indexWhere((g) => g.id == id);
    if (i != -1) {
      _groups[i].isPrivate = false;
      _groups[i].passHash = null;
      _groups[i].passHint = null;
      _groups[i].updatedAt = DateTime.now().millisecondsSinceEpoch;
      _unlocked.remove(id);
      await _save(); notifyListeners();
    }
  }
}

/* ===================== DRAG TYPES ===================== */

abstract class _DragData {}
class _DragNote extends _DragData { final String noteId; _DragNote(this.noteId); }
class _DragGroup extends _DragData { final String groupId; _DragGroup(this.groupId); }

/* ===================== HOME ===================== */

class NotesHome extends StatefulWidget {
  final bool isDark;
  final VoidCallback onToggleTheme;
  const NotesHome({super.key, required this.isDark, required this.onToggleTheme});

  @override
  State<NotesHome> createState() => _NotesHomeState();
}

class _NotesHomeState extends State<NotesHome> {
  final store = NotesStore();
  String? _currentGroupId;
  String? _hoverNoteId;
  String? _hoverGroupId;

  bool _dragging = false;
  bool _overTrash = false;

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

  Future<bool> _confirm(String title, String body) async {
    return (await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
            ],
          ),
        )) ??
        false;
  }

  // Новый диалог удаления группы с выбором сценария
  Future<void> _deleteGroupFlow(String groupId) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить группу?'),
        content: const Text('Выберите действие с её заметками.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'move'),
            child: const Text('Перенести в корень'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'delete'),
            child: const Text('Удалить заметки'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );

    if (choice == 'move') {
      await store.deleteGroup(groupId, deleteNotes: false);
      if (_currentGroupId == groupId) setState(() => _currentGroupId = null);
    } else if (choice == 'delete') {
      final ok = await _confirm('Подтверждение', 'Заметки будут удалены без возможности восстановления.');
      if (ok) {
        await store.deleteGroup(groupId, deleteNotes: true);
        if (_currentGroupId == groupId) setState(() => _currentGroupId = null);
      }
    }
  }

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
    String pick(Note n) {
      final t = n.title.trim().isNotEmpty ? n.title : _firstLine(n.text);
      return t.isEmpty ? 'Заметка' : t;
    }
    final t1 = pick(a);
    final t2 = pick(b);
    return t1 == t2 ? t1 : '$t1 • $t2';
  }

  Future<bool> _openGroup(Group g) async {
    if (g.isPrivate && !store.isUnlocked(g.id)) {
      final ok = await _askUnlock(context, g);
      if (ok != true) return false;
      store.markUnlocked(g.id);
    }
    setState(() => _currentGroupId = g.id);
    return true;
  }

  Future<void> _groupMenu(Group g) async {
    final value = await showMenu<String>(
      context: context,
      position: const RelativeRect.fromLTRB(0, 80, 0, 0),
      items: [
        const PopupMenuItem(value: 'open', child: Text('Открыть')),
        const PopupMenuItem(value: 'rename', child: Text('Переименовать')),
        const PopupMenuItem(value: 'color', child: Text('Цвет группы')),
        if (g.passHash == null)
          const PopupMenuItem(value: 'setpass', child: Text('Установить пароль'))
        else ...const [
          PopupMenuItem(value: 'setpass', child: Text('Сменить пароль')),
          PopupMenuItem(value: 'clearpas', child: Text('Снять пароль')),
        ],
        const PopupMenuItem(value: 'delete', child: Text('Удалить группу')),
      ],
    );

    if (value == null) return;
    if (value == 'open') {
      await _openGroup(g);
    } else if (value == 'rename') {
      final t = await _askText(context, 'Название группы', initial: g.title);
      if (t != null && t.trim().isNotEmpty) await store.renameGroup(g.id, t.trim());
    } else if (value == 'color') {
      final c = await _pickColor(context, initial: g.colorHex);
      await store.setGroupColor(g.id, c);
    } else if (value == 'setpass') {
      final p = await _askPassword(context, forCreate: g.passHash == null);
      if (p != null && p.password.isNotEmpty) {
        await store.setGroupPassword(g.id, passHash: _hash(p.password), hint: p.hint);
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Пароль установлен')));
        }
      }
    } else if (value == 'clearpas') {
      final ok = await _confirm('Снять пароль?', 'Группа станет публичной.');
      if (ok) {
        await store.clearGroupPassword(g.id);
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Пароль снят')));
        }
      }
    } else if (value == 'delete') {
      await _deleteGroupFlow(g.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allGroups = store.groups;
    final allNotes = store.notes;
    final groupsToShow = _currentGroupId == null ? allGroups : <Group>[];
    final notesToShow = allNotes.where((n) => n.groupId == _currentGroupId).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    Group? currentGroup;
    if (_currentGroupId != null) {
      currentGroup = allGroups.firstWhere((g) => g.id == _currentGroupId);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentGroupId == null ? 'Notes Vault' : currentGroup!.title),
        leading: _currentGroupId == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _currentGroupId = null),
              ),
        actions: [
          if (currentGroup != null)
            IconButton(
              tooltip: 'Меню группы',
              icon: const Icon(Icons.more_vert),
              onPressed: () => _groupMenu(currentGroup!),
            ),
          IconButton(
            tooltip: 'Тема',
            icon: Icon(widget.isDark ? Icons.light_mode : Icons.dark_mode),
            onPressed: widget.onToggleTheme,
          ),
        ],
      ),

      body: Stack(
        children: [
          if (!store.loaded)
            const Center(child: CircularProgressIndicator())
          else if (groupsToShow.isEmpty && notesToShow.isEmpty)
            const Center(child: Text('Нет заметок'))
          else
            CustomScrollView(
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
                          final locked = g.isPrivate && !store.isUnlocked(g.id);
                          final color = g.colorHex != null ? Color(g.colorHex!) : null;

                          return DragTarget<_DragNote>(
                            onWillAccept: (d) {
                              setState(() => _hoverGroupId = g.id);
                              return d != null;
                            },
                            onLeave: (_) => setState(() => _hoverGroupId = null),
                            onAccept: (d) async {
                              setState(() => _hoverGroupId = null);
                              await store.moveNoteToGroup(d.noteId, g.id);
                            },
                            builder: (context, candidate, rejected) => LongPressDraggable<_DragData>(
                              data: _DragGroup(g.id),
                              feedback: _GroupChipFeedback(title: g.title, color: color),
                              onDragStarted: () => setState(() { _dragging = true; _overTrash = false; }),
                              onDragEnd: (_) => setState(() { _dragging = false; _overTrash = false; }),
                              childWhenDragging: const _GhostCard(),
                              child: Card(
                                shape: RoundedRectangleBorder(
                                  side: BorderSide(
                                    color: _hoverGroupId == g.id
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.transparent,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: InkWell(
                                  onTap: () => _openGroup(g),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Stack(children: [
                                    if (color != null)
                                      Positioned.fill(
                                        left: 0,
                                        right: null,
                                        child: Container(
                                          width: 6,
                                          decoration: BoxDecoration(
                                            color: color,
                                            borderRadius: const BorderRadius.only(
                                              topLeft: Radius.circular(12),
                                              bottomLeft: Radius.circular(12),
                                            ),
                                          ),
                                        ),
                                      ),
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: IconButton(
                                        tooltip: 'Меню группы',
                                        icon: const Icon(Icons.more_vert),
                                        onPressed: () => _groupMenu(g),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(g.title,
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                        fontSize: 16, fontWeight: FontWeight.w600)),
                                              ),
                                              if (color != null)
                                                Container(
                                                  width: 14,
                                                  height: 14,
                                                  margin: const EdgeInsets.only(left: 6),
                                                  decoration: BoxDecoration(
                                                    color: color,
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: Theme.of(context).colorScheme.outlineVariant,
                                                    ),
                                                  ),
                                                ),
                                              if (g.isPrivate)
                                                Padding(
                                                  padding: const EdgeInsets.only(left: 6),
                                                  child: Icon(locked ? Icons.lock : Icons.lock_open, size: 18),
                                                ),
                                            ],
                                          ),
                                          const Spacer(),
                                          Text('Заметок: $count',
                                              style: Theme.of(context).textTheme.bodySmall),
                                        ],
                                      ),
                                    ),
                                  ]),
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
                        final color = n.colorHex != null ? Color(n.colorHex!) : null;
                        return LongPressDraggable<_DragNote>(
                          data: _DragNote(n.id),
                          feedback: _NoteChipFeedback(text: n.title.isNotEmpty ? n.title : _firstLine(n.text), color: color),
                          onDragStarted: () => setState(() { _dragging = true; _overTrash = false; }),
                          onDragEnd: (_) => setState(() { _dragging = false; _overTrash = false; }),
                          childWhenDragging: const _GhostCard(),
                          child: DragTarget<_DragNote>(
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
                              inGroupScreen: _currentGroupId != null,
                              highlighted: _hoverNoteId == n.id,
                              onTap: () => _edit(n),
                              onDeleteTap: () async => _confirmDeleteNote(n.id),
                              onUnGroupTap: _currentGroupId == null
                                  ? null
                                  : () async => store.moveNoteToGroup(n.id, null),
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

          if (_dragging)
            Positioned(
              top: 16,
              left: 16,
              child: DragTarget<_DragData>(
                onWillAccept: (d) { setState(() => _overTrash = true); return d != null; },
                onLeave: (_) => setState(() => _overTrash = false),
                onAccept: (d) async {
                  setState(() => _overTrash = false);
                  if (d is _DragNote) {
                    if (await _confirm('Удалить заметку?', 'Действие нельзя отменить.')) {
                      await store.removeNote(d.noteId);
                    }
                  } else if (d is _DragGroup) {
                    await _deleteGroupFlow(d.groupId);
                  }
                },
                builder: (context, candidate, rejected) {
                  final color = _overTrash
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.errorContainer;
                  final fg = _overTrash
                      ? Theme.of(context).colorScheme.onError
                      : Theme.of(context).colorScheme.onErrorContainer;
                  return Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      boxShadow: const [BoxShadow(blurRadius: 8, spreadRadius: 1, offset: Offset(0,2))],
                    ),
                    child: Icon(Icons.delete, color: fg),
                  );
                },
              ),
            ),
        ],
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: _createNote,
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _confirmDeleteNote(String id) async {
    final ok = await _confirm('Удалить заметку?', 'Действие нельзя отменить.');
    if (ok) await store.removeNote(id);
  }
}

/* ===================== WIDGETS ===================== */

class _NoteChipFeedback extends StatelessWidget {
  final String text;
  final Color? color;
  const _NoteChipFeedback({required this.text, this.color});
  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 240),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.primary),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (color != null)
              Container(width: 8, height: 24, margin: const EdgeInsets.only(right: 8), color: color),
            Flexible(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}

class _GroupChipFeedback extends StatelessWidget {
  final String title;
  final Color? color;
  const _GroupChipFeedback({required this.title, this.color});
  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.primary),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (color != null)
            Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          if (color != null) const SizedBox(width: 6),
          const Icon(Icons.folder, size: 18),
          const SizedBox(width: 8),
          Text(title, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}

class _GhostCard extends StatelessWidget {
  const _GhostCard();
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
  final bool inGroupScreen;
  final VoidCallback onTap;
  final VoidCallback onDeleteTap;
  final VoidCallback? onUnGroupTap;

  const _NoteCard({
    required this.note,
    required this.highlighted,
    required this.inGroupScreen,
    required this.onTap,
    required this.onDeleteTap,
    this.onUnGroupTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = note.colorHex != null ? Color(note.colorHex!) : null;
    return Card(
      shape: RoundedRectangleBorder(
        side: BorderSide(
            color: highlighted ? Theme.of(context).colorScheme.primary : Colors.transparent),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Stack(children: [
          if (color != null)
            Positioned.fill(
              left: 0,
              right: null,
              child: Container(
                width: 6,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(
                children: [
                  if (inGroupScreen && onUnGroupTap != null)
                    IconButton(
                      tooltip: 'Убрать из группы',
                      icon: const Icon(Icons.call_made, size: 20),
                      onPressed: onUnGroupTap,
                    ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Удалить',
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: onDeleteTap,
                  ),
                ],
              ),
              Text(
                note.title.isEmpty ? 'Без названия' : note.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Text(
                  note.text.isEmpty ? 'Без текста' : note.text,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (color != null)
                    Container(
                      width: 14,
                      height: 14,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                    ),
                  Expanded(child: Text(_fmt(note.updatedAt), style: Theme.of(context).textTheme.bodySmall)),
                ],
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/* ===================== EDITOR ===================== */

class NoteEditor extends StatefulWidget {
  final Note? note;
  final String? groupId;
  const NoteEditor({super.key, this.note, this.groupId});

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late final TextEditingController _title;
  late final TextEditingController _text;
  bool _numbered = false;
  TextEditingValue _last = const TextEditingValue();
  bool _internal = false;
  Color? _color;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.note?.title ?? '');
    _text = TextEditingController(text: widget.note?.text ?? '');
    _last = _text.value;
    _text.addListener(_onChanged);
    if (widget.note?.colorHex != null) _color = Color(widget.note!.colorHex!);
  }

  @override
  void dispose() {
    _text.removeListener(_onChanged);
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  int _safeCaret(String t, int caret) => math.max(0, math.min(caret, t.length));

  void _setValue(String t, int caret) {
    _internal = true;
    _text.value = TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: _safeCaret(t, caret)),
    );
    _internal = false;
    _last = _text.value;
  }

  void _ensurePrefixAtCaret({int? forcedIndex}) {
    if (!_numbered) return;
    final now = _text.value;
    final caret = forcedIndex ?? (now.selection.baseOffset < 0 ? now.text.length : now.selection.baseOffset);
    final lineStart = now.text.lastIndexOf('\n', caret - 1) + 1;
    final line = now.text.substring(lineStart);
    if (RegExp(r'^\d+\. ').hasMatch(line)) return;

    final before = now.text.substring(0, lineStart);
    int count = 0;
    for (final l in before.split('\n')) {
      final stripped = l.replaceFirst(RegExp(r'^\d+\. '), '');
      if (stripped.trim().isNotEmpty) count++;
    }
    final insert = '${count + 1}. ';
    final t = now.text.replaceRange(lineStart, lineStart, insert);
    _setValue(t, caret + insert.length);
  }

  void _toggleNumbering() {
    setState(() => _numbered = !_numbered);
    if (_numbered) _ensurePrefixAtCaret();
  }

  void _onChanged() {
    if (_internal) return;

    final now = _text.value;
    final old = _last;
    final caret = now.selection.baseOffset;

    final wasInsert = now.text.length == old.text.length + 1 &&
        now.selection.baseOffset == old.selection.baseOffset + 1;

    final wasDelete = now.text.length + 1 == old.text.length &&
        now.selection.baseOffset + 1 == old.selection.baseOffset;

    if (_numbered) {
      if (wasInsert && caret > 0 && now.text[caret - 1] != '\n') {
        _ensurePrefixAtCaret(forcedIndex: caret);
      }
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
    }

    _last = now;
  }

  void _save() {
    final result = (widget.note ?? Note.newNote(groupId: widget.groupId))
      ..title = _title.text.trim()
      ..text = _text.text.trimRight()
      ..colorHex = _color?.value
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
            tooltip: 'Цвет заметки',
            icon: const Icon(Icons.color_lens),
            onPressed: () async {
              final picked = await _pickColor(context, initial: _color?.value);
              setState(() => _color = picked != null ? Color(picked) : null);
            },
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
          child: Column(
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(
                  hintText: 'Название…',
                  border: InputBorder.none,
                ),
              ),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Expanded(
                child: TextField(
                  controller: _text,
                  autofocus: true,
                  minLines: 10,
                  maxLines: null,
                  decoration: const InputDecoration(
                    hintText: 'Текст заметки…',
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ===================== HELPERS ===================== */

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

Future<int?> _pickColor(BuildContext context, {int? initial}) async {
  final palette = _palette();
  int? current = initial;
  return showDialog<int>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Выберите цвет'),
      content: SizedBox(
        width: 320,
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _ColorDot(
              color: null,
              selected: current == null,
              label: 'Без цвета',
              onTap: () { current = null; },
            ),
            for (final c in palette)
              _ColorDot(
                color: c,
                selected: current == c.value,
                onTap: () { current = c.value; },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(context, current), child: const Text('Готово')),
      ],
    ),
  );
}

class _ColorDot extends StatelessWidget {
  final Color? color;
  final bool selected;
  final VoidCallback onTap;
  final String? label;
  const _ColorDot({required this.color, required this.selected, required this.onTap, this.label});
  @override
  Widget build(BuildContext context) {
    final border = Theme.of(context).colorScheme.outlineVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color ?? Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: selected ? Theme.of(context).colorScheme.primary : border, width: selected ? 2 : 1),
          ),
          child: color == null ? const Center(child: Icon(Icons.close, size: 16)) : null,
        ),
        if (label != null) ...[
          const SizedBox(width: 6),
          Text(label!, style: Theme.of(context).textTheme.bodySmall),
        ]
      ]),
    );
  }
}

List<Color> _palette() => const [
  Color(0xFFE57373), Color(0xFFF06292), Color(0xFFBA68C8), Color(0xFF9575CD),
  Color(0xFF7986CB), Color(0xFF64B5F6), Color(0xFF4FC3F7), Color(0xFF4DD0E1),
  Color(0xFF4DB6AC), Color(0xFF81C784), Color(0xFFAED581), Color(0xFFDCE775),
  Color(0xFFFFF176), Color(0xFFFFD54F), Color(0xFFFFB74D), Color(0xFFFF8A65),
  Color(0xFFA1887F), Color(0xFF90A4AE),
];

String _firstLine(String t) {
  final f = t.trim().split('\n').first.trim();
  return f.isEmpty ? 'Заметка' : f;
}

String _fmt(int ms) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int n) => n.toString().padLeft(2, '0');
  return 'Обновлено: ${two(dt.day)}.${two(dt.month)}.${two(dt.year)} ${two(dt.hour)}:${two(dt.minute)}';
}

String _hash(String password) {
  final bytes = utf8.encode(password);
  final digest = crypto.sha256.convert(bytes);
  return digest.toString();
}

class _PasswordResult {
  final String password;
  final String? hint;
  _PasswordResult(this.password, this.hint);
}

Future<_PasswordResult?> _askPassword(BuildContext context, {required bool forCreate}) {
  final pass = TextEditingController();
  final hint = TextEditingController();
  return showDialog<_PasswordResult>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(forCreate ? 'Задать пароль' : 'Сменить пароль'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: pass,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Пароль'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: hint,
            decoration: const InputDecoration(labelText: 'Подсказка (необязательно)'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, _PasswordResult(pass.text.trim(), hint.text.trim().isEmpty ? null : hint.text.trim())),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

Future<bool?> _askUnlock(BuildContext context, Group g) {
  final pass = TextEditingController();
  return showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Приватная группа'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Введите пароль, чтобы открыть «${g.title}».'),
          const SizedBox(height: 8),
          if (g.passHint != null)
            Text('Подсказка: ${g.passHint!}', style: const TextStyle(fontStyle: FontStyle.italic)),
          const SizedBox(height: 8),
          TextField(
            controller: pass,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Пароль'),
            onSubmitted: (_) => Navigator.pop(context, _hash(pass.text.trim()) == g.passHash),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _hash(pass.text.trim()) == g.passHash),
          child: const Text('Открыть'),
        ),
      ],
    ),
  );
}
