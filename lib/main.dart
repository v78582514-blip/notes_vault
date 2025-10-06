import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sp = await SharedPreferences.getInstance();
  final dark = sp.getBool('notes_vault_theme_dark') ?? true; // тёмная по умолчанию
  runApp(NotesVaultApp(initialDark: dark));
}

/* ===================== APP WITH THEME ===================== */

class NotesVaultApp extends StatefulWidget {
  final bool initialDark;
  const NotesVaultApp({super.key, required this.initialDark});

  @override
  State<NotesVaultApp> createState() => _NotesVaultAppState();
}

class _NotesVaultAppState extends State<NotesVaultApp> {
  late bool _dark = widget.initialDark;

  Future<void> _toggleTheme() async {
    setState(() => _dark = !_dark);
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('notes_vault_theme_dark', _dark);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notes Vault',
      debugShowCheckedModeBanner: false,
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
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
        isDark: _dark,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}

/* ===================== MODELS ===================== */

class NoteItem {
  String id;
  String title;
  String text;
  bool numbered;
  int updatedAt;
  int? colorHex;
  String? groupId;

  NoteItem({
    required this.id,
    required this.title,
    required this.text,
    required this.numbered,
    required this.updatedAt,
    this.colorHex,
    this.groupId,
  });

  factory NoteItem.newNote({String? groupId}) => NoteItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: '',
        text: '',
        numbered: false,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        colorHex: null,
        groupId: groupId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'text': text,
        'numbered': numbered,
        'updatedAt': updatedAt,
        'colorHex': colorHex,
        'groupId': groupId,
      };

  static NoteItem fromJson(Map<String, dynamic> j) => NoteItem(
        id: j['id'],
        title: (j['title'] ?? '').toString(),
        text: (j['text'] ?? '').toString(),
        numbered: (j['numbered'] ?? false) as bool,
        updatedAt: (j['updatedAt'] ?? 0) as int,
        colorHex: j['colorHex'],
        groupId: j['groupId'],
      );
}

class GroupItem {
  String id;
  String title;
  int updatedAt;
  bool locked;
  String? passHash;
  int? colorHex;

  GroupItem({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.locked = false,
    this.passHash,
    this.colorHex,
  });

  factory GroupItem.newGroup(String title,
          {bool locked = false, String? passHash, int? colorHex}) =>
      GroupItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: title,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        locked: locked,
        passHash: passHash,
        colorHex: colorHex,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'updatedAt': updatedAt,
        'locked': locked,
        'passHash': passHash,
        'colorHex': colorHex,
      };

  static GroupItem fromJson(Map<String, dynamic> j) => GroupItem(
        id: j['id'],
        title: (j['title'] ?? '').toString(),
        updatedAt: (j['updatedAt'] ?? 0) as int,
        locked: (j['locked'] ?? false) as bool,
        passHash: j['passHash'],
        colorHex: j['colorHex'],
      );
}

/* ===================== STORE ===================== */

class VaultStore extends ChangeNotifier {
  static const _k = 'notes_vault_v7_full';
  final List<NoteItem> _notes = [];
  final List<GroupItem> _groups = [];
  final Set<String> _unlocked = {};
  bool _loaded = false;

  List<NoteItem> get notes => List.unmodifiable(_notes);
  List<GroupItem> get groups => List.unmodifiable(_groups);
  bool get loaded => _loaded;
  bool isUnlocked(String groupId) => _unlocked.contains(groupId);
  void markUnlocked(String groupId) => _unlocked.add(groupId);

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_k);
    if (raw != null) {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final ns = (map['notes'] as List? ?? [])
          .map((e) => NoteItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final gs = (map['groups'] as List? ?? [])
          .map((e) => GroupItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      _notes..clear()..addAll(ns);
      _groups..clear()..addAll(gs);
    } else {
      _seed();
      await _save();
    }
    _loaded = true;
    notifyListeners();
  }

  void _seed() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final demo = GroupItem.newGroup('Примеры', colorHex: Colors.teal.value);
    _groups.add(demo);
    final texts = [
      'Список покупок\nмолоко\nхлеб\nсыр',
      'Идеи проекта\n— Сетка\n— Перетаскивание\n— Цвета',
      'Заметка с цветом',
      'Планы на день\n1. Почта\n2. Макеты',
      'Книги к прочтению',
      'Важно!',
    ];
    for (int i = 0; i < 6; i++) {
      _notes.add(NoteItem(
        id: DateTime.now().microsecondsSinceEpoch.toString() + i.toString(),
        title: 'Заметка ${i + 1}',
        text: texts[i],
        numbered: i == 3,
        updatedAt: now - i * 60000,
        colorHex: i == 2 ? Colors.amber.value : null,
        groupId: i < 2 ? demo.id : null,
      ));
    }
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

  Future<void> addNote(NoteItem n) async { _notes.add(n); await _save(); notifyListeners(); }
  Future<void> updateNote(NoteItem n) async {
    final i = _notes.indexWhere((x) => x.id == n.id);
    if (i != -1) { _notes[i] = n..updatedAt = DateTime.now().millisecondsSinceEpoch; await _save(); notifyListeners(); }
  }
  Future<void> removeNote(String id) async { _notes.removeWhere((e) => e.id == id); await _save(); notifyListeners(); }

  Future<GroupItem> createGroup(String title, {bool locked=false, String? passHash, int? colorHex}) async {
    final g = GroupItem.newGroup(title, locked: locked, passHash: passHash, colorHex: colorHex);
    _groups.add(g); await _save(); notifyListeners(); return g;
  }
  Future<void> renameGroup(String id, String title) async {
    final i = _groups.indexWhere((g) => g.id == id);
    if (i != -1) { _groups[i].title = title; _groups[i].updatedAt = DateTime.now().millisecondsSinceEpoch; await _save(); notifyListeners(); }
  }
  Future<void> setGroupColor(String id, int? colorHex) async {
    final i = _groups.indexWhere((g) => g.id == id);
    if (i != -1) { _groups[i].colorHex = colorHex; _groups[i].updatedAt = DateTime.now().millisecondsSinceEpoch; await _save(); notifyListeners(); }
  }
  Future<void> deleteGroup(String id, {bool deleteNotes=false}) async {
    if (deleteNotes) {
      _notes.removeWhere((n) => n.groupId == id);
    } else {
      for (final n in _notes) { if (n.groupId == id) n.groupId = null; }
    }
    _groups.removeWhere((g) => g.id == id);
    _unlocked.remove(id);
    await _save(); notifyListeners();
  }
  Future<void> moveNoteToGroup(String noteId, String? groupId) async {
    final i = _notes.indexWhere((e) => e.id == noteId);
    if (i == -1) return;
    _notes[i].groupId = groupId;
    _notes[i].updatedAt = DateTime.now().millisecondsSinceEpoch;
    await _save(); notifyListeners();
  }

  Future<void> setGroupPassword(String id, {required String passHash}) async {
    final i = _groups.indexWhere((g) => g.id == id);
    if (i != -1) {
      _groups[i].locked = true;
      _groups[i].passHash = passHash;
      _groups[i].updatedAt = DateTime.now().millisecondsSinceEpoch;
      await _save(); notifyListeners();
    }
  }
  Future<bool> changeGroupPassword(String id, {required String oldHash, required String newHash}) async {
    final i = _groups.indexWhere((g) => g.id == id);
    if (i != -1 && _groups[i].passHash == oldHash) {
      _groups[i].passHash = newHash;
      _groups[i].updatedAt = DateTime.now().millisecondsSinceEpoch;
      await _save(); notifyListeners(); return true;
    }
    return false;
  }
  Future<bool> clearGroupPassword(String id, {required String oldHash}) async {
    final i = _groups.indexWhere((g) => g.id == id);
    if (i != -1 && _groups[i].passHash == oldHash) {
      _groups[i].locked = false; _groups[i].passHash = null;
      _groups[i].updatedAt = DateTime.now().millisecondsSinceEpoch;
      _unlocked.remove(id);
      await _save(); notifyListeners(); return true;
    }
    return false;
  }
}

/* ===================== HELPERS ===================== */

String _hash(String s) => crypto.sha256.convert(utf8.encode(s)).toString();

String _fmt(int ms) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(dt.day)}.${two(dt.month)}.${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
}

List<Color> _palette() => const [
  Color(0xFFE57373), Color(0xFFF06292), Color(0xFFBA68C8), Color(0xFF9575CD),
  Color(0xFF7986CB), Color(0xFF64B5F6), Color(0xFF4FC3F7), Color(0xFF4DD0E1),
  Color(0xFF4DB6AC), Color(0xFF81C784), Color(0xFFAED581), Color(0xFFDCE775),
  Color(0xFFFFF176), Color(0xFFFFD54F), Color(0xFFFFB74D), Color(0xFFFF8A65),
  Color(0xFFA1887F), Color(0xFF90A4AE),
];

/* ===================== DRAG TYPES ===================== */
abstract class _DragData {}
class _DragNote extends _DragData { final String id; _DragNote(this.id); }
class _DragGroup extends _DragData { final String id; _DragGroup(this.id); }
/* ===================== UI: HOME (GRID ONLY) ===================== */

class NotesHome extends StatefulWidget {
  final bool isDark;
  final VoidCallback onToggleTheme;
  const NotesHome({super.key, required this.isDark, required this.onToggleTheme});

  @override
  State<NotesHome> createState() => _NotesHomeState();
}

class _NotesHomeState extends State<NotesHome> {
  final store = VaultStore();
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

  @override
  void dispose() {
    store.dispose();
    super.dispose();
  }

  Future<void> _createNote() async {
    final res = await Navigator.of(context).push<NoteItem>(
      MaterialPageRoute(builder: (_) => NoteEditor(groupId: _currentGroupId)),
    );
    if (res != null) await store.addNote(res);
  }

  Future<void> _edit(NoteItem n) async {
    final res = await Navigator.of(context).push<NoteItem>(
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

  Future<void> _deleteGroupFlow(String groupId) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить группу?'),
        content: const Text('Выберите действие с её заметками.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'move'), child: const Text('Перенести в корень')),
          TextButton(onPressed: () => Navigator.pop(context, 'delete'), child: const Text('Удалить заметки')),
          FilledButton(onPressed: () => Navigator.pop(context, 'cancel'), child: const Text('Отмена')),
        ],
      ),
    );
    if (choice == 'move') {
      await store.deleteGroup(groupId, deleteNotes: false);
      if (_currentGroupId == groupId) setState(() => _currentGroupId = null);
    } else if (choice == 'delete') {
      final ok = await _confirm('Подтверждение', 'Все заметки в группе будут удалены.');
      if (ok) {
        await store.deleteGroup(groupId, deleteNotes: true);
        if (_currentGroupId == groupId) setState(() => _currentGroupId = null);
      }
    }
  }

  Future<String> _ensureGroupForTwo(NoteItem a, NoteItem b) async {
    if (a.groupId != null) return a.groupId!;
    if (b.groupId != null) return b.groupId!;
    String pick(NoteItem n) => n.title.trim().isNotEmpty ? n.title : _firstLine(n.text);
    final t1 = pick(a), t2 = pick(b);
    final title = t1 == t2 ? t1 : '$t1 • $t2';
    final g = await store.createGroup(title);
    await store.moveNoteToGroup(a.id, g.id);
    await store.moveNoteToGroup(b.id, g.id);
    return g.id;
  }

  Future<bool> _openGroup(GroupItem g) async {
    if (g.locked && !store.isUnlocked(g.id)) {
      final ok = await _askUnlock(context, g);
      if (ok != true) return false;
      store.markUnlocked(g.id);
    }
    setState(() => _currentGroupId = g.id);
    return true;
  }

  Future<void> _groupMenu(BuildContext context, GroupItem g, RelativeRect pos) async {
    final value = await showMenu<String>(
      context: context,
      position: pos,
      items: const [
        PopupMenuItem(value: 'open', child: Text('Открыть')),
        PopupMenuItem(value: 'rename', child: Text('Переименовать')),
        PopupMenuItem(value: 'color', child: Text('Цвет группы')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'lock', child: Text('Приватность / Пароль')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'delete', child: Text('Удалить группу')),
      ],
    );
    if (value == null) return;

    if (value == 'open') {
      await _openGroup(g);
    } else if (value == 'rename') {
      final t = await _askText(context, 'Название группы', initial: g.title);
      if (t != null && t.trim().isNotEmpty) await store.renameGroup(g.id, t.trim());
    } else if (value == 'color') {
      final c = await _pickColor(context, initial: g.colorHex == null ? null : Color(g.colorHex!));
      await store.setGroupColor(g.id, c?.value);
    } else if (value == 'lock') {
      if (!g.locked) {
        final pass = await _askPasswordNew(context);
        if (pass != null && pass.isNotEmpty) {
          await store.setGroupPassword(g.id, passHash: _hash(pass));
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Пароль установлен')));
        }
      } else {
        final action = await _choose(context, ['Сменить пароль', 'Снять пароль']);
        if (action == 0) {
          final old = await _askPasswordOld(context);
          if (old == null) return;
          final newPass = await _askPasswordNew(context);
          if (newPass == null || newPass.isEmpty) return;
          final ok = await store.changeGroupPassword(g.id, oldHash: _hash(old), newHash: _hash(newPass));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Пароль изменён' : 'Неверный пароль')));
          }
        } else if (action == 1) {
          final old = await _askPasswordOld(context);
          if (old == null) return;
          final ok = await store.clearGroupPassword(g.id, oldHash: _hash(old));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Пароль снят' : 'Неверный пароль')));
          }
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
    final groupsToShow = _currentGroupId == null ? allGroups : <GroupItem>[];
    final notesToShow = allNotes.where((n) => n.groupId == _currentGroupId).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    GroupItem? currentGroup;
    if (_currentGroupId != null) currentGroup = allGroups.firstWhere((g) => g.id == _currentGroupId);

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Expanded(child: Text(_currentGroupId == null ? 'Notes Vault' : currentGroup!.title)),
          if (currentGroup?.colorHex != null)
            Container(
              width: 12, height: 12, margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Color(currentGroup!.colorHex!),
                shape: BoxShape.circle,
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
            ),
        ]),
        leading: _currentGroupId == null
            ? null
            : IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _currentGroupId = null)),
        actions: [
          if (currentGroup != null)
            Builder(
              builder: (ctx) => IconButton(
                tooltip: 'Меню группы',
                icon: const Icon(Icons.more_vert),
                onPressed: () {
                  final box = ctx.findRenderObject() as RenderBox?;
                  final pos = box?.localToGlobal(Offset.zero) ?? Offset.zero;
                  _groupMenu(ctx, currentGroup!, RelativeRect.fromLTRB(pos.dx, kToolbarHeight, 0, 0));
                },
              ),
            ),
          IconButton(
            tooltip: 'Тема',
            icon: Icon(widget.isDark ? Icons.light_mode : Icons.dark_mode),
            onPressed: widget.onToggleTheme,
          ),
        ],
        bottom: currentGroup?.colorHex != null
            ? PreferredSize(preferredSize: const Size.fromHeight(4), child: Container(height: 4, color: Color(currentGroup!.colorHex!)))
            : null,
      ),
      body: Stack(
        children: [
          if (!store.loaded)
            const Center(child: CircularProgressIndicator())
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
                          final locked = g.locked && !store.isUnlocked(g.id);
                          final color = g.colorHex != null ? Color(g.colorHex!) : null;

                          return DragTarget<_DragNote>(
                            onWillAccept: (d) { setState(() => _hoverGroupId = g.id); return d != null; },
                            onLeave: (_) => setState(() => _hoverGroupId = null),
                            onAccept: (d) async { setState(() => _hoverGroupId = null); await store.moveNoteToGroup(d.id, g.id); },
                            builder: (context, candidate, rejected) => LongPressDraggable<_DragData>(
                              data: _DragGroup(g.id),
                              feedback: _GroupChipFeedback(title: g.title, color: color),
                              onDragStarted: () => setState(() { _dragging = true; _overTrash = false; }),
                              onDragEnd: (_) => setState(() { _dragging = false; _overTrash = false; }),
                              childWhenDragging: const _GhostCard(),
                              child: _GroupTileFixed(
                                group: g,
                                notesCount: count,
                                locked: locked,
                                color: color,
                                highlighted: _hoverGroupId == g.id,
                                onOpen: () => _openGroup(g),
                                onMenu: (ctx) {
                                  final rb = ctx.findRenderObject() as RenderBox?;
                                  final pos = rb?.localToGlobal(Offset.zero) ?? Offset.zero;
                                  _groupMenu(ctx, g, RelativeRect.fromLTRB(pos.dx, pos.dy + 40, 0, 0));
                                },
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
                        final list = notesToShow;
                        final n = list[i];
                        final color = n.colorHex != null ? Color(n.colorHex!) : null;
                        return LongPressDraggable<_DragNote>(
                          data: _DragNote(n.id),
                          feedback: _NoteChipFeedback(text: n.title.isNotEmpty ? n.title : _firstLine(n.text), color: color),
                          onDragStarted: () => setState(() { _dragging = true; _overTrash = false; }),
                          onDragEnd: (_) => setState(() { _dragging = false; _overTrash = false; }),
                          childWhenDragging: const _GhostCard(),
                          child: DragTarget<_DragNote>(
                            onWillAccept: (d) { setState(() => _hoverNoteId = n.id); return d != null && d.id != n.id; },
                            onLeave: (_) => setState(() => _hoverNoteId = null),
                            onAccept: (d) async {
                              setState(() => _hoverNoteId = null);
                              final src = store.notes.firstWhere((x) => x.id == d.id);
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
                              onDeleteTap: () async {
                                if (await _confirm('Удалить заметку?', 'Действие нельзя отменить.')) {
                                  await store.removeNote(n.id);
                                }
                              },
                              onUnGroupTap: _currentGroupId == null ? null : () async => store.moveNoteToGroup(n.id, null),
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

          // Кнопка-корзина (перенос для удаления)
          if (_dragging)
            Positioned(
              top: 16, left: 16,
              child: DragTarget<_DragData>(
                onWillAccept: (d) { setState(() => _overTrash = true); return d != null; },
                onLeave: (_) => setState(() => _overTrash = false),
                onAccept: (d) async {
                  setState(() => _overTrash = false);
                  if (d is _DragNote) {
                    if (await _confirm('Удалить заметку?', 'Действие нельзя отменить.')) {
                      await store.removeNote(d.id);
                    }
                  } else if (d is _DragGroup) {
                    await _deleteGroupFlow(d.id);
                  }
                },
                builder: (context, candidate, rejected) {
                  final color = _overTrash ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.errorContainer;
                  final fg = _overTrash ? Theme.of(context).colorScheme.onError : Theme.of(context).colorScheme.onErrorContainer;
                  return Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle,
                      boxShadow: const [BoxShadow(blurRadius: 8, spreadRadius: 1, offset: Offset(0,2))]),
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
}

/* ===================== GROUP TILE (fixed indicators & menu) ===================== */

class _GroupTileFixed extends StatelessWidget {
  final GroupItem group;
  final int notesCount;
  final bool locked;
  final Color? color;
  final bool highlighted;
  final VoidCallback onOpen;
  final void Function(BuildContext ctx) onMenu;

  const _GroupTileFixed({
    required this.group,
    required this.notesCount,
    required this.locked,
    required this.color,
    required this.highlighted,
    required this.onOpen,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        side: BorderSide(color: highlighted ? Theme.of(context).colorScheme.primary : Colors.transparent),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Stack(
          children: [
            if (color != null) Positioned.fill(child: Container(color: color!.withOpacity(0.07))),
            if (color != null) Positioned(left: 0, right: 0, top: 0, height: 5, child: Container(color: color)),
            // Меню в правом верхнем углу
            Positioned(
              top: 4, right: 4,
              child: Builder(
                builder: (ctx) => IconButton(
                  tooltip: 'Меню группы',
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => onMenu(ctx),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Заголовок с отступом, чтобы не наезжать на ⋮
                  Padding(
                    padding: const EdgeInsets.only(right: 36),
                    child: Text(
                      group.title.isEmpty ? 'Группа' : group.title,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      if (locked) const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Icon(Icons.lock, size: 18),
                      ),
                      if (color != null)
                        Container(
                          width: 14, height: 14, margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: color, shape: BoxShape.circle,
                            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                          ),
                        ),
                      Expanded(
                        child: Text('Заметок: $notesCount',
                          textAlign: TextAlign.right,
                          style: Theme.of(context).textTheme.bodySmall),
                      ),
                    ],
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

/* ===================== NOTE CARD & DRAG FEEDBACK ===================== */

class _NoteCard extends StatelessWidget {
  final NoteItem note;
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
        side: BorderSide(color: highlighted ? Theme.of(context).colorScheme.primary : Colors.transparent),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            if (color != null)
              Positioned.fill(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    height: 5,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(12), topRight: Radius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (inGroupScreen && onUnGroupTap != null)
                    IconButton(tooltip: 'Убрать из группы', onPressed: onUnGroupTap, icon: const Icon(Icons.call_made, size: 20)),
                  const Spacer(),
                  IconButton(tooltip: 'Удалить', onPressed: onDeleteTap, icon: const Icon(Icons.delete_outline, size: 20)),
                ]),
                Text(note.title.isEmpty ? 'Без названия' : note.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Expanded(child: Text(note.text.isEmpty ? 'Без текста' : note.text, maxLines: 6, overflow: TextOverflow.ellipsis)),
                const SizedBox(height: 6),
                Row(children: [
                  if (color != null)
                    Container(
                      width: 14, height: 14, margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: color, shape: BoxShape.circle,
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                    ),
                  Expanded(child: Text(_fmt(note.updatedAt), style: Theme.of(context).textTheme.bodySmall)),
                ]),
              ]),
            ),
          ],
        ),
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
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (color != null) Container(width: 8, height: 24, margin: const EdgeInsets.only(right: 8), color: color),
          Flexible(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis)),
        ]),
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
/* ===================== NOTE EDITOR ===================== */

class NoteEditor extends StatefulWidget {
  final NoteItem? note;
  final String? groupId;
  const NoteEditor({super.key, this.note, this.groupId});

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late TextEditingController _titleCtrl;
  late TextEditingController _textCtrl;
  bool _numbering = false;
  Color? _color;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.note?.title ?? '');
    _textCtrl = TextEditingController(text: widget.note?.text ?? '');
    _color = widget.note?.colorHex != null ? Color(widget.note!.colorHex!) : null;
  }

  void _toggleNumbering() {
    setState(() {
      _numbering = !_numbering;
      if (_numbering && _textCtrl.text.trim().isEmpty) {
        _textCtrl.text = '1. ';
        _textCtrl.selection = TextSelection.collapsed(offset: _textCtrl.text.length);
      }
    });
  }

  void _onChanged(String val) {
    if (_numbering && val.endsWith('\n')) {
      final lines = val.split('\n');
      final next = lines.length;
      _textCtrl.text = val + '$next. ';
      _textCtrl.selection = TextSelection.collapsed(offset: _textCtrl.text.length);
    }
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    final text = _textCtrl.text.trim();
    final n = widget.note ?? NoteItem.newNote();
    n.title = title;
    n.text = text;
    n.colorHex = _color?.value;
    n.groupId = widget.groupId;
    Navigator.pop(context, n);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.note == null ? 'Новая заметка' : 'Редактирование'),
        actions: [
          IconButton(
            tooltip: 'Включить/выключить нумерацию',
            icon: Icon(_numbering ? Icons.format_list_numbered : Icons.format_list_bulleted),
            onPressed: _toggleNumbering,
          ),
          IconButton(
            tooltip: 'Цвет заметки',
            icon: const Icon(Icons.palette_outlined),
            onPressed: () async {
              final c = await _pickColor(context, initial: _color);
              if (c != null) setState(() => _color = c);
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(labelText: 'Заголовок', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TextField(
              controller: _textCtrl,
              onChanged: _onChanged,
              expands: true,
              minLines: null,
              maxLines: null,
              decoration: const InputDecoration(
                hintText: 'Текст заметки...',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check),
                  label: const Text('Сохранить'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  label: const Text('Отмена'),
                ),
              ),
            ],
          ),
        ]),
      ),
    );
  }
}

/* ===================== COLOR PICKER ===================== */

Future<Color?> _pickColor(BuildContext context, {Color? initial}) async {
  Color? selected = initial;
  return await showDialog<Color>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Выберите цвет'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _palette().map((c) {
            final selectedNow = selected?.value == c.value;
            return GestureDetector(
              onTap: () => selected = c,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selectedNow
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                    width: selectedNow ? 3 : 1,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.pop(context, selected),
            child: const Text('Готово'),
          ),
        ],
      );
    },
  );
}

/* ===================== PASSWORD / PROMPTS ===================== */

Future<String?> _askText(BuildContext context, String label, {String? initial}) async {
  final ctrl = TextEditingController(text: initial);
  return await showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(label),
      content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Введите текст')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('OK')),
      ],
    ),
  );
}

Future<String?> _askPasswordNew(BuildContext context) async {
  final ctrl = TextEditingController();
  return await showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Установить пароль'),
      content: TextField(
        controller: ctrl,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Пароль'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Сохранить')),
      ],
    ),
  );
}

Future<String?> _askPasswordOld(BuildContext context) async {
  final ctrl = TextEditingController();
  return await showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Введите текущий пароль'),
      content: TextField(
        controller: ctrl,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Пароль'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('OK')),
      ],
    ),
  );
}

Future<bool?> _askUnlock(BuildContext context, GroupItem g) async {
  final ctrl = TextEditingController();
  return await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('Разблокировать "${g.title}"'),
      content: TextField(
        controller: ctrl,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Пароль'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
        FilledButton(
          onPressed: () async {
            final ok = await VaultStore.verifyPassword(g, ctrl.text);
            Navigator.pop(context, ok);
          },
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/* ===================== HELPERS ===================== */

List<Color> _palette() => const [
  Color(0xFFE57373), Color(0xFFF06292), Color(0xFFBA68C8), Color(0xFF9575CD),
  Color(0xFF7986CB), Color(0xFF64B5F6), Color(0xFF4FC3F7), Color(0xFF4DD0E1),
  Color(0xFF4DB6AC), Color(0xFF81C784), Color(0xFFAED581), Color(0xFFDCE775),
  Color(0xFFFFF176), Color(0xFFFFD54F), Color(0xFFFFB74D), Color(0xFFFF8A65),
  Color(0xFFA1887F), Color(0xFF90A4AE),
];

String _firstLine(String t) {
  final lines = t.trim().split('\n');
  return lines.isNotEmpty ? lines.first.trim() : '';
}

String _fmt(int ms) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  final sameDay = dt.year == now.year && dt.month == now.month && dt.day == now.day;
  return sameDay
      ? '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
      : '${dt.day}.${dt.month}.${dt.year}';
}

String _hash(String input) => input.split('').fold<int>(0, (a, c) => a + c.codeUnitAt(0)).toString();
