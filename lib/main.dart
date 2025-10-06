import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const NotesVaultApp());

class NotesVaultApp extends StatelessWidget {
  const NotesVaultApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notes Vault',
      theme: ThemeData.dark(useMaterial3: true),
      home: const NotesHome(),
    );
  }
}

class Note {
  String title;
  String content;
  Color color;
  int? groupId;

  Note({
    required this.title,
    required this.content,
    this.color = Colors.grey,
    this.groupId,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'content': content,
        'color': color.value,
        'groupId': groupId,
      };

  static Note fromJson(Map<String, dynamic> json) => Note(
        title: json['title'],
        content: json['content'],
        color: Color(json['color']),
        groupId: json['groupId'],
      );
}

class Group {
  int id;
  String title;
  Color color;
  bool locked;
  String? password;

  Group({
    required this.id,
    required this.title,
    this.color = Colors.blueGrey,
    this.locked = false,
    this.password,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'color': color.value,
        'locked': locked,
        'password': password,
      };

  static Group fromJson(Map<String, dynamic> json) => Group(
        id: json['id'],
        title: json['title'],
        color: Color(json['color']),
        locked: json['locked'],
        password: json['password'],
      );
}
class NotesHome extends StatefulWidget {
  const NotesHome({super.key});
  @override
  State<NotesHome> createState() => _NotesHomeState();
}

class _NotesHomeState extends State<NotesHome> {
  // Данные
  List<Note> notes = [];
  List<Group> groups = [];

  // Выбранная группа (для просмотра её заметок)
  int? _selectedGroupId;
  // Временные «разблокированные» группы (разрешён просмотр до перезапуска)
  final Set<int> _unlockedOnce = {};

  // Drag states
  bool _dragging = false;

  // Загрузка
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final nRaw = prefs.getString('notes_v2');
    final gRaw = prefs.getString('groups_v2');

    if (gRaw != null) {
      final list = (jsonDecode(gRaw) as List).cast<Map<String, dynamic>>();
      groups = list.map(Group.fromJson).toList();
    }
    if (nRaw != null) {
      final list = (jsonDecode(nRaw) as List).cast<Map<String, dynamic>>();
      notes = list.map(Note.fromJson).toList();
    }

    if (groups.isEmpty && notes.isEmpty) {
      _createFixtures();
      await _saveData();
    }

    setState(() => _loaded = true);
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('groups_v2', jsonEncode(groups.map((e) => e.toJson()).toList()));
    await prefs.setString('notes_v2', jsonEncode(notes.map((e) => e.toJson()).toList()));
  }

  void _createFixtures() {
    groups = [
      Group(id: 1, title: 'Работа', color: Colors.indigo),
      Group(id: 2, title: 'Личное', color: Colors.teal),
      Group(id: 3, title: 'Идеи', color: Colors.purple),
    ];
    notes = List.generate(
      6,
      (i) => Note(
        title: 'Заметка ${i + 1}',
        content: 'Тестовая заметка ${i + 1}\nПеретащи меня в группу сверху.',
        color: Colors.primaries[i % Colors.primaries.length],
      ),
    );
  }

  // Удобные выборки
  Group? get _selectedGroup =>
      _selectedGroupId == null ? null : groups.firstWhere((g) => g.id == _selectedGroupId, orElse: () => groups.first);

  List<Note> get _visibleNotes {
    if (_selectedGroupId == null) {
      // корневые заметки
      return notes.where((n) => n.groupId == null).toList();
    }
    final g = _selectedGroup;
    if (g == null) return [];
    final lockedAndHidden = g.locked && !_unlockedOnce.contains(g.id);
    if (lockedAndHidden) return []; // скрываем заметки закрытой группы
    return notes.where((n) => n.groupId == g.id).toList();
  }

  // ==== Операции ====

  Future<void> _addNote() async {
    final created = await showDialog<Note>(
      context: context,
      builder: (_) => NoteEditor(), // придёт в части 3
    );
    if (created == null) return;
    if (_selectedGroupId != null && (!(_selectedGroup?.locked ?? false) || _unlockedOnce.contains(_selectedGroupId))) {
      created.groupId = _selectedGroupId;
    }
    setState(() => notes.add(created));
    await _saveData();
  }

  Future<void> _editNote(Note n) async {
    final updated = await showDialog<Note>(
      context: context,
      builder: (_) => NoteEditor(initial: n),
    );
    if (updated == null) return;
    setState(() {
      final i = notes.indexOf(n);
      notes[i] = updated;
    });
    await _saveData();
  }

  Future<void> _deleteNote(Note n) async {
    final ok = await _confirm(context, 'Удалить заметку?');
    if (!ok) return;
    setState(() => notes.remove(n));
    await _saveData();
  }

  Future<void> _addGroup() async {
    final created = await showDialog<Group>(
      context: context,
      builder: (_) => GroupEditor(), // придёт в части 3
    );
    if (created == null) return;
    setState(() => groups.add(created));
    await _saveData();
  }

  Future<void> _editGroup(Group g) async {
    final updated = await showDialog<Group>(
      context: context,
      builder: (_) => GroupEditor(initial: g),
    );
    if (updated == null) return;
    setState(() {
      final i = groups.indexOf(g);
      groups[i] = updated;
      // если поменяли приватность/пароль — сбросим временную разблокировку
      if (updated.locked) _unlockedOnce.remove(updated.id);
    });
    await _saveData();
  }

  Future<void> _deleteGroup(Group g) async {
    final ok = await _confirm(context, 'Удалить группу и все её заметки?');
    if (!ok) return;
    setState(() {
      notes.removeWhere((n) => n.groupId == g.id);
      groups.remove(g);
      if (_selectedGroupId == g.id) _selectedGroupId = null;
      _unlockedOnce.remove(g.id);
    });
    await _saveData();
  }

  Future<void> _openLocked(Group g) async {
    final ok = await _askPassword(context, g);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Неверный пароль')));
      return;
    }
    setState(() => _unlockedOnce.add(g.id));
  }

  // ==== UI ====

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: Text(_selectedGroup == null ? 'Notes Vault' : _selectedGroup!.title.isEmpty ? 'Без названия' : _selectedGroup!.title),
            actions: [
              if (_selectedGroupId != null)
                IconButton(
                  tooltip: 'Сбросить выбор',
                  icon: const Icon(Icons.filter_none),
                  onPressed: () => setState(() => _selectedGroupId = null),
                ),
            ],
          ),
          floatingActionButton: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.small(
                heroTag: 'addGroup',
                onPressed: _addGroup,
                child: const Icon(Icons.create_new_folder_outlined),
              ),
              const SizedBox(height: 10),
              FloatingActionButton(
                heroTag: 'addNote',
                onPressed: _addNote,
                child: const Icon(Icons.note_add),
              ),
            ],
          ),
          body: Column(
            children: [
              // === ГРУППЫ (горизонтально) ===
              SizedBox(
                height: 138,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  scrollDirection: Axis.horizontal,
                  itemBuilder: (_, i) => _groupTile(groups[i]),
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemCount: groups.length,
                ),
              ),

              const Divider(height: 1),

              // === ЗАМЕТКИ (сетка) ===
              Expanded(
                child: _lockedSkullIfNeeded()
                    ? _skullPane()
                    : GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.92,
                        ),
                        itemCount: _visibleNotes.length,
                        itemBuilder: (_, i) {
                          final n = _visibleNotes[i];
                          return LongPressDraggable<Note>(
                            data: n,
                            dragAnchorStrategy: pointerDragAnchorStrategy,
                            onDragStarted: () => setState(() => _dragging = true),
                            onDragEnd: (_) => setState(() => _dragging = false),
                            feedback: _noteFeedback(n),
                            childWhenDragging: Opacity(opacity: 0.35, child: _noteCard(n)),
                            child: _noteCard(n),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),

        // === ЗОНА УДАЛЕНИЯ (появляется во время перетаскивания) ===
        if (_dragging)
          Positioned(
            left: 0,
            right: 0,
            bottom: 28,
            child: Center(
              child: DragTarget<Note>(
                onWillAccept: (_) => true,
                onAccept: (n) async => _deleteNote(n),
                builder: (ctx, cand, rej) {
                  final active = cand.isNotEmpty;
                  return AnimatedScale(
                    duration: const Duration(milliseconds: 140),
                    scale: active ? 1.1 : 1.0,
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.28),
                        shape: BoxShape.circle,
                        boxShadow: const [BoxShadow(blurRadius: 18, color: Colors.black26)],
                      ),
                      child: const Center(child: Icon(Icons.delete_forever, size: 40, color: Colors.redAccent)),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  // === Виджеты-помощники ===

  Widget _groupTile(Group g) {
    final color = g.color;
    final lockedAndHidden = g.locked && !_unlockedOnce.contains(g.id);

    return DragTarget<Note>(
      onWillAccept: (_) => !g.locked, // в закрытую группу не даём бросить
      onAccept: (n) async {
        setState(() {
          n.groupId = g.id;
        });
        await _saveData();
      },
      builder: (ctx, cand, rej) {
        final highlight = cand.isNotEmpty;
        final tile = InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            if (g.locked && !_unlockedOnce.contains(g.id)) {
              await _openLocked(g);
            }
            setState(() => _selectedGroupId = g.id);
          },
          onLongPress: () => _editGroup(g),
          child: Stack(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 160,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.20),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: highlight ? Colors.amber : color, width: highlight ? 3 : 2),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    Expanded(
                      child: Text(
                        g.title.isEmpty ? 'Без названия' : g.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (g.locked) const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(Icons.lock_outline, size: 18),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Действия',
                      onSelected: (v) async {
                        if (v == 'edit') _editGroup(g);
                        if (v == 'delete') _deleteGroup(g);
                        if (v == 'lock') {
                          // установить/сменить пароль
                          final updated = await showDialog<Group>(
                            context: context,
                            builder: (_) => GroupEditor(initial: g, forcePrivacyPanel: true),
                          );
                          if (updated != null) {
                            setState(() {
                              final i = groups.indexOf(g);
                              groups[i] = updated;
                              if (updated.locked) _unlockedOnce.remove(updated.id);
                            });
                            await _saveData();
                          }
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(value: 'edit', child: Text('Редактировать')),
                        const PopupMenuItem(value: 'lock', child: Text('Пароль / приватность')),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: const [
                              Icon(Icons.delete_outline, color: Colors.redAccent),
                              SizedBox(width: 8),
                              Text('Удалить', style: TextStyle(color: Colors.redAccent)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (lockedAndHidden)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: Container(color: Colors.black.withOpacity(0.12))),
                        const Text('☠️', style: TextStyle(fontSize: 40)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
        return tile;
      },
    );
  }

  Widget _noteCard(Note n) {
    return GestureDetector(
      onTap: () => _editNote(n),
      onLongPress: () => _deleteNote(n),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: n.color.withOpacity(0.85),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black26)],
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(n.title.isEmpty ? 'Без названия' : n.title,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                n.content,
                maxLines: 7,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(height: 1.2),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.drag_indicator, size: 16),
                const SizedBox(width: 6),
                Text(n.groupId == null ? 'Вне группы' : 'Группа: ${_groupName(n.groupId!)}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _noteFeedback(Note n) => Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.95,
          child: Container(
            width: 180,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: n.color.withOpacity(0.95),
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(blurRadius: 16, color: Colors.black38)],
            ),
            child: Text(
              n.title.isEmpty ? 'Без названия' : n.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ),
        ),
      );

  bool _lockedSkullIfNeeded() {
    final g = _selectedGroup;
    if (g == null) return false;
    return g.locked && !_unlockedOnce.contains(g.id);
  }

  Widget _skullPane() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('☠️', style: TextStyle(fontSize: 96)),
            const SizedBox(height: 12),
            const Text('Группа закрыта'),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                final g = _selectedGroup;
                if (g == null) return;
                await _openLocked(g);
                setState(() {});
              },
              child: const Text('Ввести пароль'),
            ),
          ],
        ),
      );

  String _groupName(int id) => groups.firstWhere((g) => g.id == id, orElse: () => Group(id: 0, title: '???')).title;

  // ==== Диалоги ====

  Future<bool> _confirm(BuildContext context, String title) async {
    return (await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(title),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
            ],
          ),
        )) ??
        false;
  }

  Future<bool> _askPassword(BuildContext context, Group g) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text('«${g.title.isEmpty ? 'Без названия' : g.title}» защищена'),
            content: TextField(
              controller: ctrl,
              obscureText: true,
              decoration: const InputDecoration(hintText: 'Пароль группы'),
              autofocus: true,
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ОК')),
            ],
          ),
        ) ??
        false;

    if (!ok) return false;
    return (g.password ?? '') == ctrl.text;
  }
}
/* ===================== NOTE EDITOR ===================== */
class NoteEditor extends StatefulWidget {
  final Note? initial;
  const NoteEditor({super.key, this.initial});

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late TextEditingController _title;
  late TextEditingController _content;
  late Color _color;
  bool _numbering = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initial?.title ?? '');
    _content = TextEditingController(text: widget.initial?.content ?? '');
    _color = widget.initial?.color ?? Colors.blueGrey;
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  void _toggleNumbering() {
    setState(() => _numbering = !_numbering);
    if (_numbering) {
      // Гарантируем "1. " на текущей строке
      final t = _content.text;
      final sel = _content.selection;
      final caret = sel.baseOffset.clamp(0, t.length);
      final lineStart = t.lastIndexOf('\n', caret - 1) + 1;
      final current = t.substring(lineStart, caret);
      final rx = RegExp(r'^\s*\d+\.\s');
      if (!rx.hasMatch(current)) {
        final newText = t.replaceRange(lineStart, lineStart, '1. ');
        final newCaret = caret + 3;
        _content.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newCaret),
        );
      }
    }
  }

  Future<void> _pickColor() async {
    final c = await _selectColorDialog(context, initial: _color);
    if (c != null) setState(() => _color = c);
  }

  void _save() {
    final n = widget.initial ??
        Note(title: '', content: '', color: _color);
    n.title = _title.text.trim();
    n.content = _content.text;
    n.color = _color;
    Navigator.pop(context, n);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // верхняя цветная полоса
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: _color,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.initial == null ? 'Новая заметка' : 'Редактирование заметки',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: _numbering ? 'Отключить нумерацию' : 'Включить нумерацию',
                    onPressed: _toggleNumbering,
                    icon: Icon(_numbering ? Icons.format_list_numbered : Icons.format_list_numbered_outlined),
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
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Column(
                  children: [
                    TextField(
                      controller: _title,
                      decoration: const InputDecoration(
                        labelText: 'Заголовок',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: TextField(
                        controller: _content,
                        expands: true,
                        minLines: null,
                        maxLines: null,
                        decoration: const InputDecoration(
                          hintText: 'Текст…',
                          border: OutlineInputBorder(),
                        ),
                        inputFormatters: [_NumberingFormatter(() => _numbering)],
                      ),
                    ),
                    const SizedBox(height: 10),
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

/* ===================== GROUP EDITOR ===================== */
class GroupEditor extends StatefulWidget {
  final Group? initial;
  final bool forcePrivacyPanel; // для быстрого доступа из меню
  const GroupEditor({super.key, this.initial, this.forcePrivacyPanel = false});

  @override
  State<GroupEditor> createState() => _GroupEditorState();
}

class _GroupEditorState extends State<GroupEditor> {
  late TextEditingController _title;
  late Color _color;
  bool _locked = false;
  String? _password;

  @override
  void initState() {
    super.initState();
    final g = widget.initial;
    _title = TextEditingController(text: g?.title ?? '');
    _color = g?.color ?? Colors.blueGrey;
    _locked = g?.locked ?? false;
    _password = g?.password;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickColor() async {
    final c = await _selectColorDialog(context, initial: _color);
    if (c != null) setState(() => _color = c);
  }

  Future<void> _toggleLock() async {
    if (!_locked) {
      // включить приватность — спросить новый пароль
      final pass = await _askNewPassword(context);
      if (pass != null && pass.isNotEmpty) {
        setState(() {
          _locked = true;
          _password = pass;
        });
      }
    } else {
      // снять приватность — спросить старый пароль
      final ok = await _verifyOldPassword(context, _password ?? '');
      if (ok) {
        setState(() {
          _locked = false;
          _password = null;
        });
      }
    }
  }

  void _save() {
    final g = widget.initial ??
        Group(
          id: DateTime.now().millisecondsSinceEpoch,
          title: '',
          color: _color,
        );
    g.title = _title.text.trim();
    g.color = _color;
    g.locked = _locked;
    g.password = _password;
    Navigator.pop(context, g);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(height: 4, color: _color),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.initial == null ? 'Новая группа' : 'Редактирование группы',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(tooltip: 'Цвет', onPressed: _pickColor, icon: const Icon(Icons.palette_outlined)),
                  IconButton(
                    tooltip: _locked ? 'Снять приватность' : 'Сделать приватной',
                    onPressed: _toggleLock,
                    icon: Icon(_locked ? Icons.lock : Icons.lock_open),
                  ),
                  IconButton(tooltip: 'Сохранить', onPressed: _save, icon: const Icon(Icons.check)),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                children: [
                  TextField(
                    controller: _title,
                    decoration: const InputDecoration(labelText: 'Название группы', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(width: 18, height: 18, decoration: BoxDecoration(color: _color, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Text('Цвет выбран', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(_locked ? Icons.lock : Icons.lock_open, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        _locked ? 'Приватная (пароль установлен)' : 'Обычная (без пароля)',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  if (widget.forcePrivacyPanel) ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      icon: const Icon(Icons.password),
                      label: Text(_locked ? 'Сменить / снять пароль' : 'Установить пароль'),
                      onPressed: _toggleLock,
                    ),
                  ],
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

/* ===================== PASSWORD HELPERS ===================== */
Future<String?> _askNewPassword(BuildContext context) async {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Новый пароль'),
      content: TextField(controller: ctrl, obscureText: true, decoration: const InputDecoration(hintText: 'Введите пароль')),
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
      title: const Text('Подтвердите пароль'),
      content: TextField(controller: ctrl, obscureText: true, decoration: const InputDecoration(hintText: 'Старый пароль')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ОК')),
      ],
    ),
  );
  return ok == true && ctrl.text == current;
}

/* ===================== COLOR PICKER ===================== */
Future<Color?> _selectColorDialog(BuildContext context, {Color? initial}) async {
  final palette = _palette;
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
            for (final c in palette)
              StatefulBuilder(
                builder: (context, setInner) => GestureDetector(
                  onTap: () => setInner(() => selected = c),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected == c ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor,
                        width: selected == c ? 3 : 1,
                      ),
                    ),
                    child: selected == c ? const Center(child: Icon(Icons.check, size: 18)) : null,
                  ),
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

const List<Color> _palette = [
  Color(0xFF64B5F6), Color(0xFF4DD0E1), Color(0xFF81C784), Color(0xFFFFF176),
  Color(0xFFFFD54F), Color(0xFFFF8A65), Color(0xFF9575CD), Color(0xFF90A4AE),
];

/* ===================== NUMBERING FORMATTER ===================== */
class _NumberingFormatter extends TextInputFormatter {
  final bool Function() isEnabled;
  _NumberingFormatter(this.isEnabled);

  static final _rxNum = RegExp(r'^\s*(\d+)\.\s');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (!isEnabled()) return newValue;

    // Без текстовых изменений — пропускаем
    if (oldValue.text == newValue.text) return newValue;

    final text = newValue.text;
    final sel = newValue.selection;
    final cursor = sel.baseOffset.clamp(0, text.length);

    final lines = text.split('\n');

    // индекс строки курсора
    int lineIndex = 0;
    int acc = 0;
    for (var i = 0; i < lines.length; i++) {
      final len = lines[i].length + (i == lines.length - 1 ? 0 : 1);
      if (cursor <= acc + len) {
        lineIndex = i;
        break;
      }
      acc += len;
    }

    bool _isNumbered(String s) => _rxNum.hasMatch(s);
    String _strip(String s) => s.replaceFirst(_rxNum, '');

    // найти стартовый номер (ищем вверх ближайшую нумерованную строку)
    int currentNum = 1;
    for (int i = lineIndex; i >= 0; i--) {
      if (_isNumbered(lines[i])) {
        final m = _rxNum.firstMatch(lines[i]);
        if (m != null) {
          currentNum = int.tryParse(m.group(1) ?? '1') ?? 1;
          if (i < lineIndex) currentNum++;
        }
        break;
      }
    }

    // перенумеруем блок с текущей строки до первой пустой
    for (int i = lineIndex; i < lines.length; i++) {
      final raw = lines[i];
      if (raw.trim().isEmpty) break;
      final body = _isNumbered(raw) ? _strip(raw) : raw;
      lines[i] = '$currentNum. ${body.trimLeft()}';
      currentNum++;
    }

    final newText = lines.join('\n');
    final delta = newText.length - text.length;
    final newCursor = (cursor + delta).clamp(0, newText.length);

    return newValue.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
      composing: TextRange.empty,
    );
  }
}
