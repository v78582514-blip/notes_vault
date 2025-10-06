// lib/main.dart — PART 1/3

import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NotesVaultApp());
}

/// ======= MODELS =======

class Note {
  String id;
  String title;
  String text;
  String groupId; // '' = в корне
  int? colorHex;
  int updatedAt;

  Note({
    required this.id,
    required this.title,
    required this.text,
    required this.groupId,
    this.colorHex,
    required this.updatedAt,
  });

  factory Note.newNote({String groupId = ''}) => Note(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: '',
        text: '',
        groupId: groupId,
        colorHex: null,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'text': text,
        'groupId': groupId,
        'colorHex': colorHex,
        'updatedAt': updatedAt,
      };

  static Note fromJson(Map<String, dynamic> j) => Note(
        id: j['id'],
        title: j['title'] ?? '',
        text: j['text'] ?? '',
        groupId: j['groupId'] ?? '',
        colorHex: j['colorHex'],
        updatedAt: j['updatedAt'] ?? 0,
      );
}

class Group {
  String id;
  String title;
  int? colorHex;
  bool locked; // приватная
  String? passwordHash; // для простоты: хранится как текст (демо)

  Group({
    required this.id,
    required this.title,
    this.colorHex,
    this.locked = false,
    this.passwordHash,
  });

  factory Group.newGroup() => Group(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'colorHex': colorHex,
        'locked': locked,
        'passwordHash': passwordHash,
      };

  static Group fromJson(Map<String, dynamic> j) => Group(
        id: j['id'],
        title: j['title'] ?? '',
        colorHex: j['colorHex'],
        locked: j['locked'] ?? false,
        passwordHash: j['passwordHash'],
      );
}

/// ======= STORE (SharedPreferences) =======

class VaultStore extends ChangeNotifier {
  static const _kData = 'notes_vault_v2';
  static const _kTheme = 'notes_vault_theme';

  final List<Group> _groups = [];
  final List<Note> _notes = [];
  bool _loaded = false;
  bool get isLoaded => _loaded;

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  List<Group> get groups => List.unmodifiable(_groups);
  List<Note> get notes => List.unmodifiable(_notes);

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kData);
    if (raw != null) {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final g = (map['groups'] as List).cast<Map<String, dynamic>>();
      final n = (map['notes'] as List).cast<Map<String, dynamic>>();
      _groups
        ..clear()
        ..addAll(g.map(Group.fromJson));
      _notes
        ..clear()
        ..addAll(n.map(Note.fromJson));
    }
    // Тема
    final t = p.getString(_kTheme);
    if (t == 'dark') _themeMode = ThemeMode.dark;
    if (t == 'light') _themeMode = ThemeMode.light;

    // демоданные при первом запуске
    if (_groups.isEmpty && _notes.isEmpty) {
      final gWork = Group()
        ..id = 'g_work'
        ..title = 'Работа'
        ..colorHex = const Color(0xFF1565C0).value;
      final gLife = Group()
        ..id = 'g_life'
        ..title = 'Личное'
        ..colorHex = const Color(0xFF2E7D32).value;
      final gSecret = Group()
        ..id = 'g_secret'
        ..title = 'Секреты'
        ..colorHex = const Color(0xFF7B1FA2).value
        ..locked = true
        ..passwordHash = '1234'; // демо-пароль

      _groups.addAll([gWork, gLife, gSecret]);

      _notes.addAll([
        Note.newNote(groupId: '').copyWithDemo(
          title: 'Заметка №1',
          text: 'Это тестовая заметка номер 1.\nМожно её отредактировать.',
          color: const Color(0xFFFF8F00),
        ),
        Note.newNote(groupId: '').copyWithDemo(
          title: 'Заметка №2',
          text: 'Это тестовая заметка номер 2.\nМожно её отредактировать.',
          color: const Color(0xFF00BFA5),
        ),
        Note.newNote(groupId: '').copyWithDemo(
          title: 'Заметка №3',
          text: 'Это тестовая заметка номер 3.\nМожно её отредактировать.',
          color: const Color(0xFFE91E63),
        ),
        Note.newNote(groupId: 'g_work').copyWithDemo(
          title: 'План спринта',
          text: '1. Бэклог\n2. Оценки\n3. Демо',
          color: const Color(0xFFFFA000),
        ),
        Note.newNote(groupId: 'g_life').copyWithDemo(
          title: 'Покупки',
          text: 'Молоко\nХлеб\nСыр',
          color: const Color(0xFF9CCC65),
        ),
        Note.newNote(groupId: 'g_secret').copyWithDemo(
          title: 'Пароли',
          text: 'Очень приватно.',
          color: const Color(0xFFAB47BC),
        ),
      ]);
      await _save();
    }

    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    final map = {
      'groups': _groups.map((e) => e.toJson()).toList(),
      'notes': _notes.map((e) => e.toJson()).toList(),
    };
    await p.setString(_kData, jsonEncode(map));
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kTheme,
        mode == ThemeMode.dark ? 'dark' : mode == ThemeMode.light ? 'light' : 'system');
    notifyListeners();
  }

  // CRUD Groups
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

  Future<void> removeGroup(String groupId) async {
    // При удалении — удаляем и её заметки
    _notes.removeWhere((n) => n.groupId == groupId);
    _groups.removeWhere((g) => g.id == groupId);
    await _save();
    notifyListeners();
  }

  // CRUD Notes
  Future<void> addNote(Note n) async {
    _notes.add(n);
    await _save();
    notifyListeners();
  }

  Future<void> updateNote(Note n) async {
    final i = _notes.indexWhere((x) => x.id == n.id);
    if (i != -1) _notes[i] = n..updatedAt = nowMs();
    await _save();
    notifyListeners();
  }

  Future<void> removeNote(String id) async {
    _notes.removeWhere((n) => n.id == id);
    await _save();
    notifyListeners();
  }

  Future<void> moveNoteToGroup(String noteId, String groupId) async {
    final i = _notes.indexWhere((x) => x.id == noteId);
    if (i != -1) {
      _notes[i].groupId = groupId;
      _notes[i].updatedAt = nowMs();
      await _save();
      notifyListeners();
    }
  }

  Group? getGroup(String id) =>
      id.isEmpty ? null : _groups.firstWhere((g) => g.id == id, orElse: () => Group.newGroup());

  // Приватность
  static Future<bool> verifyPassword(Group g, String input) async {
    // демо-проверка
    return (g.passwordHash ?? '') == input;
  }
}

/// ======= APP =======

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
    final light = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3F51B5)),
      cardTheme: const CardTheme(margin: EdgeInsets.all(8)),
    );
    final dark = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7986CB), brightness: Brightness.dark),
      cardTheme: const CardTheme(margin: EdgeInsets.all(8)),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Notes Vault',
      theme: light,
      darkTheme: dark,
      themeMode: store.themeMode,
      home: NotesHome(store: store),
    );
  }
}

/// ======= HOME =======

class NotesHome extends StatefulWidget {
  final VaultStore store;
  const NotesHome({super.key, required this.store});
  @override
  State<NotesHome> createState() => _NotesHomeState();
}

class _NotesHomeState extends State<NotesHome> {
  String _currentGroupId = ''; // какая группа выбрана сверху (для заголовка)
  String? _dragNoteId; // id заметки, которую тянем
  bool _showBin = false; // показать урну

  VaultStore get store => widget.store;

  @override
  Widget build(BuildContext context) {
    final gTop = store.groups;
    final notesAll = store.notes;

    // Раздел: заметки в выбранной (или во всех)
    final visibleNotes = notesAll
        .where((n) => _currentGroupId.isEmpty ? true : n.groupId == _currentGroupId)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final currentGroup = store.getGroup(_currentGroupId);

    return Scaffold(
      appBar: AppBar(
        title: Text(currentGroup == null || _currentGroupId.isEmpty ? 'Notes Vault' : currentGroup.title),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Тема',
            icon: const Icon(Icons.color_lens),
            onSelected: (v) {
              if (v == 'light') store.setThemeMode(ThemeMode.light);
              if (v == 'dark') store.setThemeMode(ThemeMode.dark);
              if (v == 'system') store.setThemeMode(ThemeMode.system);
            },
            itemBuilder: (c) => const [
              PopupMenuItem(value: 'light', child: Text('Светлая тема')),
              PopupMenuItem(value: 'dark', child: Text('Тёмная тема')),
              PopupMenuItem(value: 'system', child: Text('Системная')),
            ],
          ),
        ],
      ),
      floatingActionButton: _fabColumn(context),
      body: !store.isLoaded
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    _groupsStrip(context, gTop),
                    const SizedBox(height: 8),
                    Expanded(child: _notesGrid(context, visibleNotes)),
                  ],
                ),
                if (_showBin) _deleteBinOverlay(context),
              ],
            ),
    );
  }

  /// FAB: добавить заметку / группу
  Widget _fabColumn(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton(
          heroTag: 'add_group',
          onPressed: () async {
            final created = await showDialog<Group>(
              context: context,
              builder: (_) => GroupEditorDialog(group: Group.newGroup()),
            );
            if (created != null) {
              await store.addGroup(created);
            }
          },
          child: const Icon(Icons.folder),
        ),
        const SizedBox(height: 12),
        FloatingActionButton(
          heroTag: 'add_note',
          onPressed: () async {
            final note = await showDialog<Note>(
              context: context,
              builder: (_) => NoteEditorDialog(note: Note.newNote(groupId: _currentGroupId)),
            );
            if (note != null) {
              await store.addNote(note);
            }
          },
          child: const Icon(Icons.add),
        ),
      ],
    );
  }

  // ====== продолжение ниже (часть 2/3) ======
}

extension on Note {
  Note copyWithDemo({String? title, String? text, Color? color}) {
    return Note(
      id: id,
      title: title ?? this.title,
      text: text ?? this.text,
      groupId: groupId,
      colorHex: color?.value ?? colorHex,
      updatedAt: updatedAt,
    );
  }
}

int nowMs() => DateTime.now().millisecondsSinceEpoch;
```0
 // lib/main.dart — PART 2/3  (продолжение _NotesHomeState)

extension _GroupsAndNotesUI on _NotesHomeState {
  /// Горизонтальная лента групп (с DragTarget — можно бросать заметки)
  Widget _groupsStrip(BuildContext context, List<Group> groups) {
    return SizedBox(
      height: 128,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemCount: groups.length,
        itemBuilder: (c, i) {
          final g = groups[i];
          return DragTarget<String>(
            onWillAccept: (data) => true,
            onAccept: (noteId) async {
              // если группа приватная — спросим пароль перед переносом
              if (g.locked) {
                final ok = await _askPassword(g);
                if (!ok) return;
              }
              await store.moveNoteToGroup(noteId, g.id);
            },
            builder: (context, candidate, rejected) {
              final hovered = candidate.isNotEmpty;
              return _GroupTile(
                group: g,
                highlighted: _currentGroupId == g.id || hovered,
                onOpen: () async {
                  if (g.locked) {
                    final ok = await _askPassword(g);
                    if (!ok) return;
                  }
                  setState(() => _currentGroupId = g.id);
                },
                onEdit: () async {
                  final updated = await showDialog<Group>(
                    context: context,
                    builder: (_) => GroupEditorDialog(group: g),
                  );
                  if (updated != null) await store.updateGroup(updated);
                },
                onDelete: () async {
                  final yes = await _confirm(context,
                      'Удалить группу «${g.title.isEmpty ? 'Без названия' : g.title}» и все её заметки?');
                  if (yes) await store.removeGroup(g.id);
                },
              );
            },
          );
        },
      ),
    );
  }

  /// Сетка заметок (LongPressDraggable + Dismissible-like удаление через урну)
  Widget _notesGrid(BuildContext context, List<Note> notes) {
    if (notes.isEmpty) {
      return const Center(child: Text('Нет заметок'));
    }
    final cross = MediaQuery.of(context).size.width > 600 ? 3 : 2;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cross,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 3 / 2,
      ),
      itemCount: notes.length,
      itemBuilder: (c, i) {
        final n = notes[i];
        return LongPressDraggable<String>(
          data: n.id,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          onDragStarted: () => setState(() {
            _dragNoteId = n.id;
            _showBin = true;
          }),
          onDragEnd: (_) => setState(() {
            _dragNoteId = null;
            _showBin = false;
          }),
          feedback: _NoteCard(note: n, dragging: true),
          childWhenDragging: Opacity(opacity: 0.3, child: _NoteCard(note: n)),
          child: _NoteCard(
            note: n,
            onTap: () async {
              final edited = await showDialog<Note>(
                context: context,
                builder: (_) => NoteEditorDialog(note: n),
              );
              if (edited != null) await store.updateNote(edited);
            },
            onDelete: () async {
              final yes = await _confirm(context, 'Удалить эту заметку?');
              if (yes) await store.removeNote(n.id);
            },
          ),
        );
      },
    );
  }

  /// Полупрозрачная «урна» по центру снизу — принимает бросаемую заметку
  Widget _deleteBinOverlay(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: DragTarget<String>(
          onWillAccept: (id) => true,
          onAccept: (id) async {
            final yes = await _confirm(context, 'Удалить заметку?');
            if (yes) await store.removeNote(id);
          },
          builder: (context, candidate, rejected) {
            final active = candidate.isNotEmpty;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: active ? 88 : 72,
              height: active ? 88 : 72,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(active ? 0.9 : 0.35),
                shape: BoxShape.circle,
                boxShadow: [
                  if (active)
                    const BoxShadow(blurRadius: 16, spreadRadius: 2, color: Colors.black26),
                ],
                border: Border.all(color: Colors.white24),
              ),
              child: const Icon(Icons.delete, size: 36),
            );
          },
        ),
      ),
    );
  }

  Future<bool> _askPassword(Group g) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Группа «${g.title.isEmpty ? 'Без названия' : g.title}» защищена'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Пароль'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(
            onPressed: () async {
              final verified = await VaultStore.verifyPassword(g, ctrl.text);
              Navigator.pop(context, verified);
            },
            child: const Text('ОК'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<bool> _confirm(BuildContext context, String msg) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Подтверждение'),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
        ],
      ),
    );
    return r ?? false;
  }
}

/// Карточка группы в верхней ленте (с индикатором цвета и замком)
class _GroupTile extends StatelessWidget {
  final Group group;
  final bool highlighted;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _GroupTile({
    super.key,
    required this.group,
    required this.highlighted,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final color = group.colorHex != null ? Color(group.colorHex!) : null;

    return GestureDetector(
      onTap: onOpen,
      child: Container(
        width: 180,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: (color ?? Theme.of(context).colorScheme.primary).withOpacity(highlighted ? 0.8 : 0.35),
            width: highlighted ? 2.5 : 1.5,
          ),
          gradient: LinearGradient(
            colors: [
              (color ?? Theme.of(context).colorScheme.surfaceVariant).withOpacity(0.16),
              (color ?? Theme.of(context).colorScheme.surfaceVariant).withOpacity(0.06),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black26)],
        ),
        child: Stack(
          children: [
            // Поле содержания
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.title.isEmpty ? 'Без названия' : group.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                  ),
                  const Spacer(),
                  Icon(
                    group.locked ? Icons.lock : Icons.folder,
                    size: 36,
                    color: color ?? Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
            // Кнопки меню (не перекрывать цвет/замок)
            Positioned(
              right: 4,
              top: 4,
              child: PopupMenuButton<String>(
                tooltip: 'Меню группы',
                onSelected: (v) async {
                  if (v == 'open') onOpen();
                  if (v == 'edit') onEdit();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'open', child: Text('Открыть')),
                  const PopupMenuItem(value: 'edit', child: Text('Редактировать')),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [Icon(Icons.delete_outline), SizedBox(width: 8), Text('Удалить')]),
                  ),
                ],
              ),
            ),

            // Аккуратный индикатор цвета (в отдельной зоне, без пересечения с замком/меню)
            if (color != null)
              Positioned(
                left: 10,
                top: 10,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Карточка заметки
class _NoteCard extends StatelessWidget {
  final Note note;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final bool dragging;

  const _NoteCard({super.key, required this.note, this.onTap, this.onDelete, this.dragging = false});

  @override
  Widget build(BuildContext context) {
    final color = note.colorHex != null ? Color(note.colorHex!) : null;
    final border = color ?? Theme.of(context).colorScheme.primary;

    return Material(
      elevation: dragging ? 10 : 2,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border.withOpacity(0.35), width: 1.4),
            gradient: LinearGradient(
              colors: [
                (color ?? Theme.of(context).colorScheme.surfaceVariant).withOpacity(0.14),
                (color ?? Theme.of(context).colorScheme.surfaceVariant).withOpacity(0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Цветной акцент сверху
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: (color ?? Theme.of(context).colorScheme.primary).withOpacity(0.85),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                note.title.isEmpty ? 'Без заголовка' : note.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  note.text,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.access_time, size: 14, color: Theme.of(context).hintColor),
                  const SizedBox(width: 4),
                  Text(_fmtDate(DateTime.fromMillisecondsSinceEpoch(note.updatedAt)),
                      style: Theme.of(context).textTheme.bodySmall),
                  const Spacer(),
                  if (onDelete != null)
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
    );
  }
}

String _fmtDate(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  final now = DateTime.now();
  final sameDay = dt.year == now.year && dt.month == now.month && dt.day == now.day;
  return sameDay
      ? '${two(dt.hour)}:${two(dt.minute)}'
      : '${two(dt.day)}.${two(dt.month)}.${dt.year}';
}
// lib/main.dart — PART 3/3 (NoteEditorDialog + GroupEditorDialog)

/// ======= NOTE EDITOR =======

class NoteEditorDialog extends StatefulWidget {
  final Note note;
  const NoteEditorDialog({super.key, required this.note});

  @override
  State<NoteEditorDialog> createState() => _NoteEditorDialogState();
}

class _NoteEditorDialogState extends State<NoteEditorDialog> {
  late TextEditingController _titleCtrl;
  late TextEditingController _textCtrl;
  Color? _color;
  bool _numbering = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.note.title);
    _textCtrl = TextEditingController(text: widget.note.text);
    _color = widget.note.colorHex != null ? Color(widget.note.colorHex!) : null;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  void _applyNumbering() {
    if (!_numbering) return;
    final text = _textCtrl.text.split('\n');
    final newText = [
      for (int i = 0; i < text.length; i++) '${i + 1}. ${text[i]}'
    ].join('\n');
    _textCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palette();

    return AlertDialog(
      insetPadding: const EdgeInsets.all(16),
      contentPadding: const EdgeInsets.all(16),
      title: const Text('Редактировать заметку'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Заголовок'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Цвет:'),
                const SizedBox(width: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final c in palette)
                      GestureDetector(
                        onTap: () => setState(() => _color = c),
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _color == c
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Colors.white,
                              width: _color == c ? 2 : 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Checkbox(
                  value: _numbering,
                  onChanged: (v) {
                    setState(() {
                      _numbering = v ?? false;
                      _applyNumbering();
                    });
                  },
                ),
                const Text('Нумерация'),
              ],
            ),
            TextField(
              controller: _textCtrl,
              decoration: const InputDecoration(
                labelText: 'Текст заметки',
                alignLabelWithHint: true,
              ),
              keyboardType: TextInputType.multiline,
              maxLines: 10,
              onChanged: (_) {
                if (_numbering) _applyNumbering();
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            final n = widget.note
              ..title = _titleCtrl.text.trim()
              ..text = _textCtrl.text
              ..colorHex = _color?.value
              ..updatedAt = nowMs();
            Navigator.pop(context, n);
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

/// ======= GROUP EDITOR =======

class GroupEditorDialog extends StatefulWidget {
  final Group group;
  const GroupEditorDialog({super.key, required this.group});

  @override
  State<GroupEditorDialog> createState() => _GroupEditorDialogState();
}

class _GroupEditorDialogState extends State<GroupEditorDialog> {
  late TextEditingController _titleCtrl;
  late TextEditingController _passCtrl;
  Color? _color;
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.group.title);
    _passCtrl = TextEditingController(text: widget.group.passwordHash ?? '');
    _color = widget.group.colorHex != null ? Color(widget.group.colorHex!) : null;
    _locked = widget.group.locked;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palette();

    return AlertDialog(
      title: const Text('Редактировать группу'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Название группы'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Цвет:'),
                const SizedBox(width: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final c in palette)
                      GestureDetector(
                        onTap: () => setState(() => _color = c),
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _color == c
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Colors.white,
                              width: _color == c ? 2 : 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Сделать приватной'),
              value: _locked,
              onChanged: (v) => setState(() => _locked = v),
            ),
            if (_locked)
              TextField(
                controller: _passCtrl,
                decoration: const InputDecoration(labelText: 'Пароль'),
                obscureText: true,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: () {
            final g = widget.group
              ..title = _titleCtrl.text.trim()
              ..colorHex = _color?.value
              ..locked = _locked
              ..passwordHash = _locked ? _passCtrl.text : null;
            Navigator.pop(context, g);
          },
          child: const Text('Готово'),
        ),
      ],
    );
  }
}

/// ======= COLOR PALETTE =======

List<Color> _palette() => const [
      Color(0xFFE57373),
      Color(0xFFF06292),
      Color(0xFFBA68C8),
      Color(0xFF9575CD),
      Color(0xFF7986CB),
      Color(0xFF64B5F6),
      Color(0xFF4FC3F7),
      Color(0xFF4DD0E1),
      Color(0xFF4DB6AC),
      Color(0xFF81C784),
      Color(0xFFAED581),
      Color(0xFFDCE775),
      Color(0xFFFFF176),
      Color(0xFFFFD54F),
      Color(0xFFFFB74D),
      Color(0xFFFF8A65),
      Color(0xFFA1887F),
      Color(0xFF90A4AE),
    ];
