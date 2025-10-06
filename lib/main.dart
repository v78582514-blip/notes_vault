import 'dart:convert';
import 'dart:ui' as ui; // blur
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NotesVaultApp());
}

/* ============================ APP / THEME ============================ */

class NotesVaultApp extends StatefulWidget {
  const NotesVaultApp({super.key});
  @override
  State<NotesVaultApp> createState() => _NotesVaultAppState();
}

class _NotesVaultAppState extends State<NotesVaultApp> {
  final store = VaultStore();

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

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: Colors.indigo,
      brightness: store.isDark ? Brightness.dark : Brightness.light,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Notes Vault',
      themeMode: store.isDark ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(useMaterial3: true, colorScheme: scheme),
      darkTheme: ThemeData(useMaterial3: true, colorScheme: scheme),
      home: NotesHome(store: store),
    );
  }
}

/* ============================ MODELS ============================ */

class NoteItem {
  String id;
  String? groupId;
  String title;
  String text;
  bool numbered;
  int? colorHex;
  int updatedAt;

  NoteItem({
    required this.id,
    this.groupId,
    this.title = '',
    this.text = '',
    this.numbered = false,
    this.colorHex,
    required this.updatedAt,
  });

  factory NoteItem.newNote({String? groupId}) => NoteItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        groupId: groupId,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'groupId': groupId,
        'title': title,
        'text': text,
        'numbered': numbered,
        'colorHex': colorHex,
        'updatedAt': updatedAt,
      };

  static NoteItem fromJson(Map<String, dynamic> j) => NoteItem(
        id: j['id'],
        groupId: j['groupId'],
        title: j['title'] ?? '',
        text: j['text'] ?? '',
        numbered: j['numbered'] ?? false,
        colorHex: j['colorHex'],
        updatedAt: j['updatedAt'] ?? 0,
      );
}

class GroupItem {
  String id;
  String title;
  int? colorHex;
  String? pass; // для демо: хранится как plain; на проде — хэш+salt
  int updatedAt;

  GroupItem({
    required this.id,
    this.title = '',
    this.colorHex,
    this.pass,
    required this.updatedAt,
  });

  bool get isPrivate => (pass != null && pass!.isNotEmpty);

  factory GroupItem.newGroup() => GroupItem(
        id: 'g_${DateTime.now().microsecondsSinceEpoch}',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'colorHex': colorHex,
        'pass': pass,
        'updatedAt': updatedAt,
      };

  static GroupItem fromJson(Map<String, dynamic> j) => GroupItem(
        id: j['id'],
        title: j['title'] ?? '',
        colorHex: j['colorHex'],
        pass: j['pass'],
        updatedAt: j['updatedAt'] ?? 0,
      );
}

/* ============================ STORE ============================ */

class VaultStore extends ChangeNotifier {
  static const _kNotes = 'nv_notes_v1';
  static const _kGroups = 'nv_groups_v1';
  static const _kTheme = 'nv_theme_dark';
  static const _kFirstRun = 'nv_first_run_done';

  final List<NoteItem> _notes = [];
  final List<GroupItem> _groups = [];
  bool _loaded = false;
  bool _isDark = true;

  bool get isLoaded => _loaded;
  bool get isDark => _isDark;
  List<NoteItem> get notes => List.unmodifiable(_notes);
  List<GroupItem> get groups => List.unmodifiable(_groups);

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _isDark = p.getBool(_kTheme) ?? true;

    final gRaw = p.getString(_kGroups);
    final nRaw = p.getString(_kNotes);
    if (gRaw != null) {
      _groups
        ..clear()
        ..addAll(((jsonDecode(gRaw) as List).cast<Map<String, dynamic>>())
            .map(GroupItem.fromJson));
    }
    if (nRaw != null) {
      _notes
        ..clear()
        ..addAll(((jsonDecode(nRaw) as List).cast<Map<String, dynamic>>())
            .map(NoteItem.fromJson));
    }

    final firstRun = p.getBool(_kFirstRun) ?? false;
    if (!firstRun) {
      _installFixtures();
      await p.setBool(_kFirstRun, true);
      await _save();
    }

    _loaded = true;
    notifyListeners();
  }

  void _installFixtures() {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (int i = 1; i <= 6; i++) {
      _notes.add(NoteItem(
        id: 'demo_$i',
        title: 'Пример $i',
        text: 'Это тестовая заметка №$i\n— редактируй меня!',
        numbered: i.isOdd,
        colorHex: _palette[i % _palette.length].value,
        updatedAt: now - i * 1000,
      ));
    }
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kNotes, jsonEncode(_notes.map((e) => e.toJson()).toList()));
    await p.setString(_kGroups, jsonEncode(_groups.map((e) => e.toJson()).toList()));
    await p.setBool(_kTheme, _isDark);
  }

  Future<void> toggleTheme() async {
    _isDark = !_isDark;
    await _save();
    notifyListeners();
  }

  /* Notes */
  Future<void> upsertNote(NoteItem n) async {
    final i = _notes.indexWhere((x) => x.id == n.id);
    n.updatedAt = DateTime.now().millisecondsSinceEpoch;
    if (i == -1) _notes.add(n); else _notes[i] = n;
    await _save(); notifyListeners();
  }

  Future<void> deleteNote(String id) async {
    _notes.removeWhere((e) => e.id == id);
    await _save(); notifyListeners();
  }

  Future<void> moveNoteToGroup(String id, String? groupId) async {
    final i = _notes.indexWhere((e) => e.id == id);
    if (i == -1) return;
    _notes[i].groupId = groupId;
    _notes[i].updatedAt = DateTime.now().millisecondsSinceEpoch;
    await _save(); notifyListeners();
  }

  /* Groups */
  Future<void> upsertGroup(GroupItem g) async {
    final i = _groups.indexWhere((x) => x.id == g.id);
    g.updatedAt = DateTime.now().millisecondsSinceEpoch;
    if (i == -1) _groups.add(g); else _groups[i] = g;
    await _save(); notifyListeners();
  }

  Future<bool> verifyPassword(GroupItem g, String input) async {
    return (g.pass ?? '') == input;
  }

  Future<void> deleteGroup(String id) async {
    _groups.removeWhere((e) => e.id == id);
    _notes.removeWhere((n) => n.groupId == id); // удаляем и заметки этой группы
    await _save(); notifyListeners();
  }
}

/* ============================ HOME ============================ */

class NotesHome extends StatefulWidget {
  final VaultStore store;
  const NotesHome({super.key, required this.store});
  @override
  State<NotesHome> createState() => _NotesHomeState();
}

class _NotesHomeState extends State<NotesHome> {
  String? _openGroupId; // null => корень
  bool _showTrash = false;

  VaultStore get store => widget.store;

  List<NoteItem> get _visibleNotes => store.notes
      .where((n) => n.groupId == _openGroupId)
      .toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  List<GroupItem> get _rootGroups => store.groups
      .where((g) => _openGroupId == null)
      .toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  Future<void> _openNoteEditor({NoteItem? note}) async {
    final res = await Navigator.push<NoteItem>(
      context,
      MaterialPageRoute(builder: (_) => NoteEditor(note: note, groupId: _openGroupId)),
    );
    if (res != null) await store.upsertNote(res);
  }

  Future<void> _openGroupEditor({GroupItem? group}) async {
    final res = await Navigator.push<GroupItem>(
      context,
      MaterialPageRoute(builder: (_) => GroupEditor(group: group)),
    );
    if (res != null) await store.upsertGroup(res);
  }

  Future<void> _openGroup(GroupItem g) async {
    if (g.isPrivate) {
      final ok = await _askPassword(g);
      if (!ok) return;
    }
    setState(() => _openGroupId = g.id);
  }

  Future<bool> _askPassword(GroupItem g) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Группа «${g.title.isEmpty ? 'Без названия' : g.title}»'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Пароль'), obscureText: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ОК')),
        ],
      ),
    );
    if (ok != true) return false;
    final passOk = await store.verifyPassword(g, ctrl.text);
    if (!passOk && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Неверный пароль')));
    }
    return passOk;
  }

  Future<void> _confirmDeleteNote(NoteItem n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить заметку?'),
        content: Text(n.title.isEmpty ? 'Заметка без заголовка' : n.title),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok == true) await store.deleteNote(n.id);
  }

  Future<void> _confirmDeleteGroup(GroupItem g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить группу и все её заметки?'),
        content: Text(g.title.isEmpty ? 'Группа без названия' : g.title),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok == true) await store.deleteGroup(g.id);
  }

  @override
  Widget build(BuildContext context) {
    final groups = _rootGroups;
    final notes = _visibleNotes;

    return Scaffold(
      appBar: AppBar(
        title: Text(_openGroupId == null ? 'Notes Vault' : 'Группа'),
        leading: _openGroupId != null
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _openGroupId = null))
            : null,
        actions: [
          IconButton(
            tooltip: 'Тема',
            icon: Icon(store.isDark ? Icons.dark_mode : Icons.light_mode),
            onPressed: store.toggleTheme,
          ),
          PopupMenuButton<String>(
            tooltip: 'Меню',
            onSelected: (v) {
              if (v == 'new_note') _openNoteEditor();
              if (v == 'new_group') _openGroupEditor();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'new_note', child: ListTile(leading: Icon(Icons.note_add), title: Text('Новая заметка'))),
              if (_openGroupId == null)
                const PopupMenuItem(value: 'new_group', child: ListTile(leading: Icon(Icons.folder_open), title: Text('Новая группа'))),
            ],
          ),
        ],
        bottom: _openGroupId != null
            ? _GroupIndicatorBar(group: store.groups.firstWhere((g) => g.id == _openGroupId))
            : null,
      ),
      body: !store.isLoaded
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                  child: CustomScrollView(
                    slivers: [
                      if (_openGroupId == null && groups.isNotEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
                            child: Text('Группы', style: Theme.of(context).textTheme.titleMedium),
                          ),
                        ),
                      if (_openGroupId == null && groups.isNotEmpty)
                        SliverGrid.builder(
                          itemCount: groups.length,
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.1),
                          itemBuilder: (_, i) {
                            final g = groups[i];
                            return _GroupTile(
                              group: g,
                              onOpen: () => _openGroup(g),
                              onEdit: () => _openGroupEditor(group: g),
                              onDelete: () => _confirmDeleteGroup(g),
                              child: DragTarget<NoteItem>(
                                onWillAccept: (n) => n != null,
                                onAccept: (n) => store.moveNoteToGroup(n.id, g.id),
                                builder: (c, cand, rej) => const SizedBox.expand(),
                              ),
                            );
                          },
                        ),
                      if (notes.isNotEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 4, bottom: 8, top: 16),
                            child: Text('Заметки', style: Theme.of(context).textTheme.titleMedium),
                          ),
                        ),
                      SliverGrid.builder(
                        itemCount: notes.length,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.1),
                        itemBuilder: (_, i) {
                          final n = notes[i];
                          return LongPressDraggable<NoteItem>(
                            data: n,
                            onDragStarted: () => setState(() => _showTrash = true),
                            onDragEnd: (_) => setState(() => _showTrash = false),
                            feedback: _GhostCard(title: n.title, color: n.colorHex != null ? Color(n.colorHex!) : null),
                            childWhenDragging: const _GhostCard(),
                            child: _NoteTile(
                              note: n,
                              onOpen: () => _openNoteEditor(note: n),
                              onDelete: () => _confirmDeleteNote(n),
                            ),
                          );
                        },
                      ),
                      if (groups.isEmpty && notes.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(child: Text('Нет заметок')),
                        ),
                    ],
                  ),
                ),
                // Корзина (DragTarget) — для удаления заметок переносом
                Positioned(
                  right: 16, bottom: 16,
                  child: DragTarget<NoteItem>(
                    onWillAccept: (_) => true,
                    onAccept: (n) => _confirmDeleteNote(n),
                    builder: (_, cand, __) => AnimatedScale(
                      duration: const Duration(milliseconds: 180),
                      scale: _showTrash ? 1 : 0,
                      child: FloatingActionButton.large(
                        heroTag: 'trash',
                        onPressed: () {},
                        backgroundColor: Theme.of(context).colorScheme.errorContainer,
                        child: const Icon(Icons.delete_forever),
                      ),
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNoteEditor,
        icon: const Icon(Icons.add),
        label: const Text('Новая'),
      ),
    );
  }
}

/* ============================ GROUP TILE (BLUR) ============================ */

class _GroupTile extends StatelessWidget {
  final GroupItem group;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Widget child; // DragTarget overlay

  const _GroupTile({
    super.key,
    required this.group,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final color = group.colorHex != null ? Color(group.colorHex!) : null;
    final locked = group.isPrivate;

    final titleLine = Row(children: [
      Expanded(
        child: Text(
          group.title.isEmpty ? 'Без названия' : group.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      if (locked) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.lock, size: 16)),
    ]);

    final metaLine = Text('Обновлено: ${_fmtDate(group.updatedAt)}',
        style: Theme.of(context).textTheme.bodySmall);

    final innerContent = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        titleLine,
        const Spacer(),
        metaLine,
      ]),
    );

    return Stack(
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          elevation: 1,
          child: InkWell(
            onTap: onOpen,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(height: 6, color: color ?? Colors.transparent), // цвет всегда виден
                Expanded(
                  child: locked
                      ? Stack(fit: StackFit.expand, children: [
                          // контент под блюром
                          ImageFiltered(
                            imageFilter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: innerContent,
                          ),
                          // лёгкое затемнение для 100% нечитаемости
                          Container(color: Theme.of(context).colorScheme.surface.withOpacity(0.35)),
                          // центр. замок
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.lock, size: 28),
                            ),
                          ),
                        ])
                      : innerContent,
                ),
              ],
            ),
          ),
        ),
        // Меню ⋮ — всегда поверх
        Positioned(
          left: 4, top: 4,
          child: Material(
            color: Colors.transparent,
            child: PopupMenuButton<String>(
              tooltip: 'Действия',
              onSelected: (v) {
                if (v == 'open') onOpen();
                if (v == 'edit') onEdit();
                if (v == 'del') onDelete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'open', child: ListTile(leading: Icon(Icons.folder_open), title: Text('Открыть'))),
                PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit), title: Text('Редактировать'))),
                PopupMenuItem(value: 'del', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Удалить'))),
              ],
              child: const CircleAvatar(radius: 16, child: Icon(Icons.more_vert, size: 18)),
            ),
          ),
        ),
        // DragTarget overlay
        Positioned.fill(child: IgnorePointer(child: child)),
      ],
    );
  }
}

/* ============================ NOTE TILE ============================ */

class _NoteTile extends StatelessWidget {
  final NoteItem note;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  const _NoteTile({super.key, required this.note, required this.onOpen, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final color = note.colorHex != null ? Color(note.colorHex!) : null;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(height: 6, color: color ?? Colors.transparent),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(note.title.isEmpty ? 'Без названия' : note.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Expanded(child: Text(note.text, maxLines: 5, overflow: TextOverflow.ellipsis)),
                const SizedBox(height: 8),
                Row(children: [
                  Icon(Icons.access_time, size: 14, color: Theme.of(context).textTheme.bodySmall?.color),
                  const SizedBox(width: 4),
                  Text(_fmtDate(note.updatedAt), style: Theme.of(context).textTheme.bodySmall),
                  const Spacer(),
                  IconButton(tooltip: 'Удалить', icon: const Icon(Icons.delete_outline), onPressed: onDelete),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/* ============================ DRAG FEEDBACK ============================ */

class _GhostCard extends StatelessWidget {
  final String? title;
  final Color? color;
  const _GhostCard({this.title, this.color});
  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.7,
      child: Card(
        child: SizedBox(
          width: 160, height: 120,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(height: 6, color: color ?? Colors.transparent),
            Expanded(child: Center(child: Text(title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis))),
          ]),
        ),
      ),
    );
  }
}

/* ============================ NOTE EDITOR ============================ */

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
    _textCtrl  = TextEditingController(text: widget.note?.text  ?? '');
    _numbering = widget.note?.numbered ?? false;
    _color     = widget.note?.colorHex != null ? Color(widget.note!.colorHex!) : null;
    if (_numbering) _ensureFirstLineNumbered();
  }

  void _ensureFirstLineNumbered() {
    final text = _textCtrl.text;
    if (text.isEmpty) {
      _textCtrl.text = '1. ';
      _textCtrl.selection = TextSelection.collapsed(offset: _textCtrl.text.length);
      return;
    }
    final lines = text.split('\n');
    if (!RegExp(r'^\s*\d+\.\s').hasMatch(lines.first)) {
      lines[0] = '1. ${lines.first}';
      final joined = lines.join('\n');
      _textCtrl.value = TextEditingValue(text: joined, selection: TextSelection.collapsed(offset: joined.length));
    }
  }

  void _toggleNumbering() {
    setState(() => _numbering = !_numbering);
    if (_numbering) _ensureFirstLineNumbered();
  }

  Future<void> _save() async {
    final n = widget.note ?? NoteItem.newNote(groupId: widget.groupId);
    n.title     = _titleCtrl.text.trim();
    n.text      = _textCtrl.text;
    n.numbered  = _numbering;
    n.colorHex  = _color?.value;
    n.updatedAt = DateTime.now().millisecondsSinceEpoch;
    Navigator.pop(context, n);
  }

  @override
  Widget build(BuildContext context) {
    final previewColor = _color ?? Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.note == null ? 'Новая заметка' : 'Редактирование'),
        actions: [
          IconButton(
            tooltip: 'Нумерация',
            icon: Icon(_numbering ? Icons.format_list_numbered : Icons.format_list_bulleted),
            onPressed: _toggleNumbering,
          ),
          IconButton(
            tooltip: 'Цвет',
            icon: const Icon(Icons.palette_outlined),
            onPressed: () async {
              final c = await _pickColor(context, initial: _color);
              if (c != null) setState(() => _color = c);
            },
          ),
          IconButton(tooltip: 'Сохранить', icon: const Icon(Icons.check), onPressed: _save),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(4), child: Container(height: 4, color: previewColor)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Заголовок', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          Expanded(
            child: TextField(
              controller: _textCtrl,
              inputFormatters: [_NumberingFormatter(() => _numbering)],
              expands: true,
              minLines: null, maxLines: null,
              decoration: const InputDecoration(hintText: 'Текст…', border: OutlineInputBorder()),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Форматтер нумерации: продолжает список на Enter, завершает при строке "N. " без текста.
class _NumberingFormatter extends TextInputFormatter {
  final bool Function() isOn;
  _NumberingFormatter(this.isOn);

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (!isOn()) return newValue;
    final caret = newValue.selection.baseOffset;
    if (caret <= 0 || caret > newValue.text.length) return newValue;
    if (newValue.text[caret - 1] != '\n') return newValue;

    final prevStart = newValue.text.lastIndexOf('\n', caret - 2) + 1;
    final prevLine = newValue.text.substring(prevStart, caret - 1);

    final onlyNum = RegExp(r'^\s*(\d+)\.\s*$');
    final numbered = RegExp(r'^\s*(\d+)\.\s');

    if (onlyNum.hasMatch(prevLine)) {
      // оставить пустую строку — не продолжаем
      return newValue;
    }

    final m = numbered.firstMatch(prevLine);
    if (m == null) return newValue;

    final next = int.tryParse(m.group(1) ?? '') ?? 1;
    final prefix = '${next + 1}. ';

    final text = newValue.text.substring(0, caret) + prefix + newValue.text.substring(caret);
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: caret + prefix.length));
  }
}

/* ============================ GROUP EDITOR ============================ */

class GroupEditor extends StatefulWidget {
  final GroupItem? group;
  const GroupEditor({super.key, this.group});
  @override
  State<GroupEditor> createState() => _GroupEditorState();
}

class _GroupEditorState extends State<GroupEditor> {
  late TextEditingController _title;
  Color? _color;
  bool _private = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.group?.title ?? '');
    _color = widget.group?.colorHex != null ? Color(widget.group!.colorHex!) : null;
    _private = widget.group?.isPrivate ?? false;
  }

  Future<void> _editPassword(GroupItem g) async {
    // если был пароль — спросим старый
    if (g.isPrivate) {
      final ok = await _askOldPass(g);
      if (!ok) return;
    }
    // установить / снять
    final newPass = await _askNewPass(initialOn: _private);
    if (newPass == null) return;
    setState(() => _private = newPass.isNotEmpty);
    g.pass = newPass.isEmpty ? null : newPass;
  }

  Future<bool> _askOldPass(GroupItem g) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Введите старый пароль'),
        content: TextField(controller: ctrl, obscureText: true, decoration: const InputDecoration(labelText: 'Пароль')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ОК')),
        ],
      ),
    );
    if (ok != true) return false;
    final passOk = (g.pass ?? '') == ctrl.text;
    if (!passOk && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Неверный пароль')));
    }
    return passOk;
  }

  Future<String?> _askNewPass({required bool initialOn}) async {
    final ctrl = TextEditingController();
    bool on = initialOn;
    return showDialog<String>(
      context: context,
      builder: (_) => StatefulBuilder(builder: (c, setSt) {
        return AlertDialog(
          title: const Text('Приватность'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                value: on,
                onChanged: (v) => setSt(() => on = v),
                title: const Text('Сделать группу приватной'),
              ),
              if (on)
                TextField(controller: ctrl, obscureText: true, decoration: const InputDecoration(labelText: 'Новый пароль')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(context, on ? ctrl.text : ''), child: const Text('Готово')),
          ],
        );
      }),
    );
  }

  Future<void> _save() async {
    final g = widget.group ?? GroupItem.newGroup();
    g.title = _title.text.trim();
    g.colorHex = _color?.value;
    if (!_private) g.pass = null;
    Navigator.pop(context, g);
  }

  @override
  Widget build(BuildContext context) {
    final previewColor = _color ?? Theme.of(context).colorScheme.primary;
    final g = widget.group;
    return Scaffold(
      appBar: AppBar(
        title: Text(g == null ? 'Новая группа' : 'Редактирование группы'),
        actions: [
          IconButton(
            tooltip: 'Цвет',
            icon: const Icon(Icons.palette_outlined),
            onPressed: () async {
              final c = await _pickColor(context, initial: _color);
              if (c != null) setState(() => _color = c);
            },
          ),
          IconButton(
            tooltip: 'Пароль',
            icon: Icon(_private ? Icons.lock : Icons.lock_open),
            onPressed: () async {
              final temp = g ?? GroupItem.newGroup()..pass = _private ? 'x' : null;
              await _editPassword(temp);
              setState(() => _private = temp.isPrivate);
              if (g != null) g.pass = temp.pass;
            },
          ),
          IconButton(tooltip: 'Сохранить', icon: const Icon(Icons.check), onPressed: _save),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(4), child: Container(height: 4, color: previewColor)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(controller: _title, decoration: const InputDecoration(labelText: 'Название группы', border: OutlineInputBorder())),
      ),
    );
  }
}

/* ============================ HELPERS ============================ */

class _GroupIndicatorBar extends StatelessWidget implements PreferredSizeWidget {
  final GroupItem group;
  const _GroupIndicatorBar({required this.group, super.key});
  @override
  Size get preferredSize => const Size.fromHeight(4);
  @override
  Widget build(BuildContext context) {
    final color = group.colorHex != null ? Color(group.colorHex!) : Theme.of(context).colorScheme.primary;
    return Container(height: 4, color: color);
  }
}

String _fmtDate(int ms) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int n) => n.toString().padLeft(2, '0');
  final sameDay = DateTime.now().difference(dt).inDays == 0;
  return sameDay
      ? '${two(dt.hour)}:${two(dt.minute)}'
      : '${two(dt.day)}.${two(dt.month)}.${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
}

Future<Color?> _pickColor(BuildContext context, {Color? initial}) async {
  final palette = _palette;
  Color? selected = initial;
  return showDialog<Color>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Выберите цвет'),
      content: SizedBox(
        width: 320,
        child: Wrap(
          spacing: 12, runSpacing: 12,
          children: [
            _ColorChip(label: 'Без цвета', selected: selected == null, color: Colors.transparent, onTap: () => selected = null),
            for (final c in palette)
              _ColorChip(color: c, selected: selected?.value == c.value, onTap: () => selected = c),
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
    final border = selected ? Border.all(width: 3, color: Theme.of(context).colorScheme.primary) : null;
    final bg = color == Colors.transparent ? Theme.of(context).colorScheme.surfaceVariant : color;
    final dot = Container(width: 34, height: 34, decoration: BoxDecoration(color: bg, shape: BoxShape.circle, border: border));
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: label == null ? dot : Row(mainAxisSize: MainAxisSize.min, children: [dot, const SizedBox(width: 8), Text(label!)]),
    );
  }
}

const List<Color> _palette = [
  Color(0xFF64B5F6), Color(0xFF4DD0E1), Color(0xFF81C784), Color(0xFFFFF176),
  Color(0xFFFFD54F), Color(0xFFFF8A65), Color(0xFF9575CD), Color(0xFF90A4AE),
];
