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

/* ===================== HOME ===================== */

abstract class _DragData {}
class _DragNote extends _DragData { final String noteId; _DragNote(this.noteId); }
class _DragGroup extends _DragData { final String groupId; _DragGroup(this.groupId); }

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
      position: const RelativeRect.fromLTRB(0, 0, 0, 0),
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
                              feedback: _GroupFeedback(title: g.title, color: color),
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
                                 
