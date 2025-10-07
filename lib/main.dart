// === БЛОК 1/4 === lib/main.dart (начало файла до _GroupTile) ===
import 'dart:convert';
import 'dart:ui';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NotesVaultApp());
}

/// =======================
/// МОДЕЛИ ДАННЫХ
/// =======================

class Group {
  String id;
  String title;
  int? colorHex; // ARGB int (0xFFRRGGBB)
  bool locked;
  String? passwordHash; // демо: обычная строка

  Group({
    required this.id,
    required this.title,
    this.colorHex,
    this.locked = false,
    this.passwordHash,
  });

  Color? get color => colorHex == null ? null : Color(colorHex!);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'colorHex': colorHex,
        'locked': locked,
        'passwordHash': passwordHash,
      };

  static Group fromJson(Map<String, dynamic> j) => Group(
        id: j['id'],
        title: j['title'],
        colorHex: j['colorHex'],
        locked: j['locked'] ?? false,
        passwordHash: j['passwordHash'],
      );

  Group copyWith({
    String? id,
    String? title,
    int? colorHex,
    bool? locked,
    String? passwordHash,
  }) {
    return Group(
      id: id ?? this.id,
      title: title ?? this.title,
      colorHex: colorHex ?? this.colorHex,
      locked: locked ?? this.locked,
      passwordHash: passwordHash ?? this.passwordHash,
    );
  }
}

class Note {
  String id;
  String title;
  String text;
  String? groupId;
  int? colorHex; // ARGB int
  int updatedAt;

  Note({
    required this.id,
    required this.title,
    required this.text,
    this.groupId,
    this.colorHex,
    required this.updatedAt,
  });

  Color? get color => colorHex == null ? null : Color(colorHex!);

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
        groupId: j['groupId'],
        colorHex: j['colorHex'],
        updatedAt: j['updatedAt'] ?? DateTime.now().millisecondsSinceEpoch,
      );

  Note copyWith({
    String? id,
    String? title,
    String? text,
    String? groupId,
    Color? color,
    int? updatedAt,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      text: text ?? this.text,
      groupId: groupId ?? this.groupId,
      colorHex: color == null ? colorHex : color.toARGB32(),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Вспомогательное расширение для сохранения цвета
extension _ColorToArgb on Color {
  int toARGB32() =>
      ((a * 255).toInt() << 24) |
      ((r * 255).toInt() << 16) |
      ((g * 255).toInt() << 8) |
      (b * 255).toInt();
}

/// =======================
/// ХРАНИЛИЩЕ (SharedPreferences)
/// =======================

class VaultStore extends ChangeNotifier {
  static const _kGroups = 'groups_v1';
  static const _kNotes = 'notes_v1';
  static const _kTheme = 'theme_v1'; // 'light' | 'dark' | 'system'

  final List<Group> _groups = [];
  final List<Note> _notes = [];
  ThemeMode themeMode = ThemeMode.system;

  List<Group> get groups => List.unmodifiable(_groups);
  List<Note> notesOf(String? groupId) =>
      _notes.where((n) => n.groupId == groupId).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();

    // тема
    final t = p.getString(_kTheme);
    if (t == 'dark') themeMode = ThemeMode.dark;
    if (t == 'light') themeMode = ThemeMode.light;

    // группы/заметки
    final gRaw = p.getStringList(_kGroups) ?? [];
    final nRaw = p.getStringList(_kNotes) ?? [];
    _groups
      ..clear()
      ..addAll(gRaw.map((s) => Group.fromJson(jsonDecode(s))));
    _notes
      ..clear()
      ..addAll(nRaw.map((s) => Note.fromJson(jsonDecode(s))));

    // демо-данные при первом запуске
    if (_groups.isEmpty && _notes.isEmpty) {
  // создаём стандартные группы
  final gWork = Group(
    id: 'g_work',
    title: 'Работа',
    colorHex: 0xFF1565C0,
  );
  final gLife = Group(
    id: 'g_life',
    title: 'Личное',
    colorHex: 0xFF2E7D32,
  );
  final gSecret = Group(
    id: 'g_secret',
    title: 'Приватное',
    colorHex: 0xFF7B1FA2,
    locked: false, // теперь открытая — пользователь может сам установить пароль позже
  );

  _groups.addAll([gWork, gLife, gSecret]);

  // одна стартовая заметка с описанием приложения
  _notes.add(
    Note(
      id: 'n_intro',
      title: 'Добро пожаловать в Notes Vault',
      text: '''
Это приложение создано для удобного и безопасного хранения ваших заметок.

📂 Основные функции:
• Создание заметок с цветами и группами  
• Перетаскивание заметок в группы  
• Создание новых групп путём объединения заметок  
• Защита приватных групп паролем  
• Экспорт и импорт заметок (в JSON)  
• Умная нумерация списков в редакторе  
• Тёмная и светлая темы оформления  
• Поиск по всем заметкам  
• Возможность делиться заметками как текстом, Markdown или HTML  

💡 Попробуйте создать новую заметку или группу, перетащить заметку на другую — и вы увидите, как просто всё устроено!
      ''',
      groupId: null,
      colorHex: 0xFFFFA000,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ),
  );

  await _saveAll();
}

      await _saveAll();
    }

    notifyListeners();
  }

  Future<void> _saveAll() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(
        _kGroups, _groups.map((g) => jsonEncode(g.toJson())).toList());
    await p.setStringList(
        _kNotes, _notes.map((n) => jsonEncode(n.toJson())).toList());
  }

  Future<void> setTheme(ThemeMode mode) async {
    themeMode = mode;
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _kTheme,
      mode == ThemeMode.dark
          ? 'dark'
          : mode == ThemeMode.light
              ? 'light'
              : 'system',
    );
    notifyListeners();
  }

  // группы
  Future<void> upsertGroup(Group g) async {
    final i = _groups.indexWhere((x) => x.id == g.id);
    if (i >= 0) {
      _groups[i] = g;
    } else {
      _groups.add(g);
    }
    await _saveAll();
    notifyListeners();
  }

  Future<void> deleteGroup(String id) async {
    // удаляем вместе с заметками
    _notes.removeWhere((n) => n.groupId == id);
    _groups.removeWhere((g) => g.id == id);
    await _saveAll();
    notifyListeners();
  }

  // заметки
  Future<void> upsertNote(Note n) async {
    final i = _notes.indexWhere((x) => x.id == n.id);
    if (i >= 0) {
      _notes[i] = n.copyWith(updatedAt: DateTime.now().millisecondsSinceEpoch);
    } else {
      _notes.add(
        n.copyWith(updatedAt: DateTime.now().millisecondsSinceEpoch),
      );
    }
    await _saveAll();
    notifyListeners();
  }

  Future<void> deleteNote(String id) async {
    _notes.removeWhere((n) => n.id == id);
    await _saveAll();
    notifyListeners();
  }

  Future<void> moveNoteToGroup(String noteId, String? groupId) async {
    final i = _notes.indexWhere((n) => n.id == noteId);
    if (i >= 0) {
      _notes[i] = _notes[i].copyWith(
        groupId: groupId,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _saveAll();
      notifyListeners();
    }
  }

  Group? groupById(String? id) =>
      id == null ? null : _groups.firstWhere((g) => g.id == id);

  Future<bool> verifyPassword(Group g, String input) async {
    return (g.passwordHash ?? '').trim() == input.trim();
  }
}

/// =======================
/// ПРИЛОЖЕНИЕ + ТЕМА
/// =======================

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
    store.load();
  }

  @override
  Widget build(BuildContext context) {
    final light = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF3F51B5),
        brightness: Brightness.light,
      ),
      cardTheme: const CardThemeData(margin: EdgeInsets.all(8)),
    );

    final dark = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF7986CB),
        brightness: Brightness.dark,
      ),
      cardTheme: const CardThemeData(margin: EdgeInsets.all(8)),
    );

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Notes Vault',
        theme: light,
        darkTheme: dark,
        themeMode: store.themeMode,
        home: NotesHome(store: store),
      ),
    );
  }
}

/// =======================
/// ГЛАВНЫЙ ЭКРАН
/// =======================

class NotesHome extends StatefulWidget {
  const NotesHome({super.key, required this.store});
  final VaultStore store;

  @override
  State<NotesHome> createState() => _NotesHomeState();
}

class _NotesHomeState extends State<NotesHome> with TickerProviderStateMixin {
  String? _currentGroupId;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  String? _dragNoteId;
  bool _dragging = false;

  VaultStore get store => widget.store;

  // Все заметки (без группы + по всем группам) — для поиска/мерджа
  List<Note> _allNotes() {
    final list = <Note>[];
    list.addAll(store.notesOf(null));
    for (final g in store.groups) {
      list.addAll(store.notesOf(g.id));
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    _currentGroupId = null;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (_, __) {
        final notes = store.notesOf(_currentGroupId);
        final groups = store.groups;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              _currentGroupId == null
                  ? 'Все заметки'
                  : (store.groupById(_currentGroupId!)?.title ?? 'Группа'),
            ),
            actions: [
              IconButton(
                tooltip: 'Поиск',
                onPressed: () async {
                  await showSearch<Note?>(
                    context: context,
                    delegate: _NotesSearchDelegate(
                      notes: _allNotes(),
                      onOpen: (n) => _editNote(context, n),
                    ),
                  );
                },
                icon: const Icon(Icons.search),
              ),
              IconButton(
                tooltip: 'Сменить тему',
                onPressed: () {
                  final next = {
                    ThemeMode.system: ThemeMode.dark,
                    ThemeMode.dark: ThemeMode.light,
                    ThemeMode.light: ThemeMode.system,
                  }[store.themeMode]!;
                  store.setTheme(next);
                },
                icon: Icon(
                  switch (store.themeMode) {
                    ThemeMode.dark => Icons.dark_mode,
                    ThemeMode.light => Icons.light_mode,
                    _ => Icons.brightness_auto,
                  },
                ),
              ),
            ],
          ),
          body: Stack(
            children: [
              Column(
                children: [
                  _groupsStrip(context, groups),
                  const SizedBox(height: 6),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        Text(
                          'Заметки',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Показать без группы',
                          onPressed: () =>
                              setState(() => _currentGroupId = null),
                          icon: const Icon(Icons.folder_open),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: _notesGrid(context, notes)),
                ],
              ),
              if (_dragging) _deleteDropZone(context),
            ],
          ),
          floatingActionButton: _fabColumn(context),
        );
      },
    );
  }

  /// FAB: добавить заметку / группу
  Widget _fabColumn(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.small(
          heroTag: 'add_group',
          tooltip: 'Добавить группу',
          onPressed: () async => _editGroup(context),
          child: const Icon(Icons.create_new_folder),
        ),
        const SizedBox(height: 12),
        FloatingActionButton(
          heroTag: 'add_note',
          tooltip: 'Добавить заметку',
          onPressed: () async => _editNote(context),
          child: const Icon(Icons.add),
        ),
      ],
    );
  }// === БЛОК 2/4 === lib/main.dart (от _groupsStrip до _NoteGhostCard) ===

  /// Полоса групп (каждая — DragTarget<String>)
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
            onWillAcceptWithDetails: (_) => true,
            onAcceptWithDetails: (details) async {
              if (g.locked) {
                final ok = await _askPassword(g);
                if (!ok) return;
              }
              await store.moveNoteToGroup(details.data, g.id);
            },
            builder: (context, _, __) {
              final color = g.color ?? Theme.of(context).colorScheme.primary;

              return GestureDetector(
                onTap: () async {
                  if (g.locked) {
                    final ok = await _askPassword(g);
                    if (!ok) return;
                  }
                  setState(() => _currentGroupId = g.id);
                },
                onLongPress: () => _groupMenu(context, g),
                child: _GroupTile(
                  group: g,
                  color: color,
                  selected: _currentGroupId == g.id,
                  blurred: g.locked && _currentGroupId != g.id,
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// Сетка заметок: каждая карточка — Drop target + Draggable
  Widget _notesGrid(BuildContext context, List<Note> notes) {
    final size = MediaQuery.of(context).size;
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    final cols = (size.width < 700 || isPortrait) ? 2 : 3;

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 12,
        crossAxisSpacing: 14,
        childAspectRatio: 1.32,
      ),
      itemCount: notes.length,
      itemBuilder: (context, i) {
        final n = notes[i];
        final c =
            n.color ?? Theme.of(context).colorScheme.surfaceContainerHighest;

        // Ячейка принимает drop другой заметки (чтобы объединить их в новую группу)
        return DragTarget<String>(
          onWillAcceptWithDetails: (details) => details.data != n.id,
          onAcceptWithDetails: (details) async {
            await _mergeNotesIntoNewGroup(details.data, n.id);
            _dragNoteId = null;
            setState(() => _dragging = false);
          },
          builder: (context, candidate, rejected) {
            final isHover = candidate.isNotEmpty;

            return Stack(
              children: [
                LongPressDraggable<String>(
                  data: n.id,
                  dragAnchorStrategy: childDragAnchorStrategy,
                  onDragStarted: () {
                    _dragNoteId = n.id;
                    setState(() => _dragging = true);
                  },
                  onDragEnd: (_) {
                    _dragNoteId = null;
                    setState(() => _dragging = false);
                  },
                  feedback: _NoteGhostCard(color: c),
                  childWhenDragging: const _NoteGhostCard(),
                  child: _NoteCard(
                    note: n,
                    onTap: () => _editNote(context, n),
                    onDelete: () => _confirmDeleteNote(context, n),
                    onShare: () => _shareNote(context, n),
                  ),
                ),

                // Подсветка, когда над карточкой держат другую
                if (isHover)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2.5,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  /// Найти заметку по id
  Note? _noteById(String id) {
    for (final n in _allNotes()) {
      if (n.id == id) return n;
    }
    return null;
  }

  /// Объединить две заметки в новую группу (через диалог группы)
  Future<void> _mergeNotesIntoNewGroup(String id1, String id2) async {
    if (id1 == id2) return;

    final a = _noteById(id1);
    final b = _noteById(id2);
    if (a == null || b == null) return;

    final created = await showDialog<Group>(
      context: context,
      builder: (_) => const _GroupEditorDialog(),
    );
    if (created == null) return;

    await store.upsertGroup(created);
    await store.upsertNote(a.copyWith(groupId: created.id));
    await store.upsertNote(b.copyWith(groupId: created.id));

    setState(() => _currentGroupId = created.id);
  }

  /// Зона удаления (DragTarget снизу)
  Widget _deleteDropZone(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: DragTarget<String>(
          onWillAcceptWithDetails: (_) => true,
          onAcceptWithDetails: (_) async {
            final id = _dragNoteId;
            if (id == null) return;
            final ok = await _askConfirm(
              context,
              title: 'Удалить заметку?',
              message: 'Действие невозможно отменить.',
            );
            if (ok) await store.deleteNote(id);
          },
          builder: (context, _, __) => Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: scheme.error.withOpacity(.15),
              borderRadius: BorderRadius.circular(44),
              border: Border.all(color: scheme.error, width: 2),
              boxShadow: const [BoxShadow(blurRadius: 16, spreadRadius: 2)],
            ),
            child: Icon(Icons.delete, color: scheme.error, size: 34),
          ),
        ),
      ),
    );
  }

  /// Меню группы
  Future<void> _groupMenu(BuildContext context, Group g) async {
    final action = await _choose(context, [
      'Открыть',
      if (!g.locked) 'Сделать приватной',
      if (g.locked) 'Снять пароль',
      'Переименовать/цвет',
      'Удалить',
    ]);
    if (action == null) return;

    switch (action) {
      case 'Открыть':
        if (g.locked) {
          final ok = await _askPassword(g);
          if (!ok) return;
        }
        setState(() => _currentGroupId = g.id);
        break;

      case 'Сделать приватной':
        final pass = await _askNewPassword(context);
        if (pass != null && pass.isNotEmpty) {
          await store.upsertGroup(g.copyWith(locked: true, passwordHash: pass));
        }
        break;

      case 'Снять пароль':
        final ok = await _askPassword(g);
        if (ok) {
          await store.upsertGroup(g.copyWith(locked: false, passwordHash: null));
        }
        break;

      case 'Переименовать/цвет':
        await _editGroup(context, g);
        break;

      case 'Удалить':
        final yes = await _askConfirm(
          context,
          title: 'Удалить группу?',
          message: 'Все заметки в группе будут удалены.',
        );
        if (yes) {
          if (_currentGroupId == g.id) _currentGroupId = null;
          await store.deleteGroup(g.id);
        }
        break;
    }
  }

  /// ========= Диалоги редактирования =========

  Future<void> _editGroup(BuildContext context, [Group? original]) async {
    final updated = await showDialog<Group>(
      context: context,
      builder: (_) => _GroupEditorDialog(group: original),
    );
    if (updated != null) await store.upsertGroup(updated);
  }

  Future<void> _editNote(BuildContext context, [Note? original]) async {
    final updated = await showDialog<Note>(
      context: context,
      builder: (_) => _NoteEditorDialog(
        note: original,
        defaultGroupId: _currentGroupId,
      ),
    );
    if (updated != null) await store.upsertNote(updated);
  }

  Future<void> _confirmDeleteNote(BuildContext context, Note n) async {
    final ok = await _askConfirm(
      context,
      title: 'Удалить заметку?',
      message: 'Действие невозможно отменить.',
    );
    if (ok) await store.deleteNote(n.id);
  }

  /// ========= Вспомогательные модалки =========

  Future<bool> _askConfirm(BuildContext context,
      {required String title, required String message}) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => _ConfirmDialog(title: title, message: message),
        ) ??
        false;
  }

  Future<String?> _askNewPassword(BuildContext context) async {
    return showDialog<String>(
      context: context,
      builder: (_) => const _PasswordEditorDialog(),
    );
  }

  Future<bool> _askPassword(Group g) async {
    final res = await showDialog<String>(
      context: context,
      builder: (_) => _PasswordAskDialog(groupTitle: g.title),
    );
    if (res == null) return false;
    return store.verifyPassword(g, res);
  }

  Future<String?> _choose(BuildContext context, List<String> options) async {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final o in options)
              ListTile(
                title: Text(o),
                onTap: () => Navigator.pop(context, o),
              ),
          ],
        ),
      ),
    );
  }

  /// ====== ФОРМАТИРОВАНИЕ И ШАРИНГ ЗАМЕТКИ ======

  String _fmtNoteAsPlain(Note n) {
    final title = n.title.trim().isEmpty ? 'Без заголовка' : n.title.trim();
    final time = _fmtTime(n.updatedAt);
    return '$title\n$time\n\n${n.text}';
  }

  String _fmtNoteAsMarkdown(Note n) {
    final title = n.title.trim().isEmpty ? 'Без заголовка' : n.title.trim();
    final time = _fmtTime(n.updatedAt);
    return '# $title\n\n*Обновлено: $time*\n\n${n.text}';
  }

  String _fmtNoteAsHtml(Note n) {
    final title = n.title.trim().isEmpty ? 'Без заголовка' : n.title.trim();
    final time = _fmtTime(n.updatedAt);
    final escaped = _escapeHtml(n.text).replaceAll('\n', '<br/>');
    return '''
<!doctype html>
<html lang="ru">
  <head>
    <meta charset="utf-8"/>
    <title>${_escapeHtml(title)}</title>
    <meta name="viewport" content="width=device-width, initial-scale=1"/>
    <style>
      body { font-family: -apple-system, Roboto, Segoe UI, Arial, sans-serif; padding: 16px; line-height: 1.45; }
      h1 { margin: 0 0 8px; font-size: 22px; }
      .time { color: #777; margin: 0 0 16px; font-size: 12px; }
      pre, code { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
    </style>
  </head>
  <body>
    <h1>${_escapeHtml(title)}</h1>
    <div class="time">Обновлено: ${_escapeHtml(time)}</div>
    <div>${escaped}</div>
  </body>
</html>''';
  }

  String _escapeHtml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  Future<void> _shareNote(BuildContext context, Note n) async {
    final choice = await _choose(context, [
      'Как текст',
      'Как Markdown (.md)',
      'Как HTML (.html)',
    ]);
    if (choice == null) return;

    try {
      switch (choice) {
        case 'Как текст':
          await Share.share(
            _fmtNoteAsPlain(n),
            subject: n.title.isEmpty ? 'Заметка' : n.title,
          );
          break;

        case 'Как Markdown (.md)':
          {
            final dir = await getTemporaryDirectory();
            final file = File('${dir.path}/note_${n.id}.md');
            await file.writeAsString(_fmtNoteAsMarkdown(n), encoding: utf8);
            await Share.shareXFiles(
              [XFile(file.path, mimeType: 'text/markdown')],
              subject: n.title.isEmpty ? 'Заметка' : n.title,
              text: 'См. прикрепленный файл Markdown',
            );
          }
          break;

        case 'Как HTML (.html)':
          {
            final dir = await getTemporaryDirectory();
            final file = File('${dir.path}/note_${n.id}.html');
            await file.writeAsString(_fmtNoteAsHtml(n), encoding: utf8);
            await Share.shareXFiles(
              [XFile(file.path, mimeType: 'text/html')],
              subject: n.title.isEmpty ? 'Заметка' : n.title,
              text: 'См. прикрепленный HTML-файл',
            );
          }
          break;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось поделиться: $e')),
        );
      }
    }
  }
}

String _fmtTime(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.hour)}:${two(d.minute)}  ${two(d.day)}.${two(d.month)}.${d.year}';
}

/// =======================
/// КАРТОЧКИ / ТАЙЛЫ
/// =======================

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.group,
    required this.color,
    required this.selected,
    required this.blurred,
  });

  final Group group;
  final Color color;
  final bool selected;
  final bool blurred;

  @override
  Widget build(BuildContext context) {
    final border = Border.all(
      color: selected ? color : color.withOpacity(.5),
      width: selected ? 3 : 2,
    );

    final base = Container(
      width: 180,
      height: 110,
      decoration: BoxDecoration(
        color: color.withOpacity(.08),
        borderRadius: BorderRadius.circular(22),
        border: border,
      ),
      padding: const EdgeInsets.all(16),
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Text(
              group.title.isEmpty ? 'Без названия' : group.title,
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Icon(Icons.folder, size: 32, color: color),
          ),
          if (group.locked)
            Align(
              alignment: Alignment.centerRight,
              child: Icon(Icons.lock, color: color, size: 26),
            ),
        ],
      ),
    );

    if (!blurred) return base;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        children: [
          base,
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(color: Colors.black.withOpacity(.2)),
            ),
          ),
          const Positioned.fill(
            child: Center(
              child: Icon(Icons.hide_source, size: 40, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.onTap,
    required this.onDelete,
    required this.onShare,
  });

  final Note note;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = note.color ?? scheme.primary;

    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                note.title.isEmpty ? 'Без заголовка' : note.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Text(
                  note.text,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _fmtTime(note.updatedAt),
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: scheme.outline),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Поделиться',
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints.tightFor(width: 32, height: 32),
                    iconSize: 18,
                    onPressed: onShare,
                    icon: const Icon(Icons.ios_share),
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    tooltip: 'Удалить',
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints.tightFor(width: 32, height: 32),
                    iconSize: 18,
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
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

class _NoteGhostCard extends StatelessWidget {
  const _NoteGhostCard({this.color});
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.surfaceContainerHighest;
    return Opacity(
      opacity: .6,
      child: Container(
        width: 220,
        height: 140,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
    );
  }
}// === БЛОК 3/4 === lib/main.dart (поиск + диалоги до _GroupEditorDialog) ===

/// =======================
/// ПОИСК ЗАМЕТОК
/// =======================

class _NotesSearchDelegate extends SearchDelegate<Note?> {
  _NotesSearchDelegate({
    required this.notes,
    required this.onOpen,
  });

  final List<Note> notes;
  final void Function(Note) onOpen;

  @override
  List<Widget>? buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) {
    final items = _filtered();
    return _list(context, items);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final items = _filtered();
    return _list(context, items);
  }

  List<Note> _filtered() {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return notes;
    return notes.where((n) {
      final title = (n.title).toLowerCase();
      final text = (n.text).toLowerCase();
      return title.contains(q) || text.contains(q);
    }).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Widget _list(BuildContext context, List<Note> items) {
    if (items.isEmpty) {
      return const Center(child: Text('Ничего не найдено'));
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final n = items[i];
        return ListTile(
          leading: const Icon(Icons.note_outlined),
          title: Text(n.title.isEmpty ? 'Без заголовка' : n.title),
          subtitle: Text(
            n.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(
            _fmtTime(n.updatedAt),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          onTap: () {
            onOpen(n);
            close(context, n);
          },
        );
      },
    );
  }
}

/// =======================
/// ДИАЛОГИ
/// =======================

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({required this.title, required this.message});
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Удалить'),
        ),
      ],
    );
  }
}

class _PasswordAskDialog extends StatefulWidget {
  const _PasswordAskDialog({required this.groupTitle});
  final String groupTitle;

  @override
  State<_PasswordAskDialog> createState() => _PasswordAskDialogState();
}

class _PasswordAskDialogState extends State<_PasswordAskDialog> {
  final _ctrl = TextEditingController();
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Пароль для «${widget.groupTitle}»'),
      content: TextField(
        controller: _ctrl,
        obscureText: _obscure,
        decoration: InputDecoration(
          labelText: 'Пароль',
          suffixIcon: IconButton(
            icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          child: const Text('Ок'),
        ),
      ],
    );
  }
}

class _PasswordEditorDialog extends StatefulWidget {
  const _PasswordEditorDialog();

  @override
  State<_PasswordEditorDialog> createState() => _PasswordEditorDialogState();
}

class _PasswordEditorDialogState extends State<_PasswordEditorDialog> {
  final _p1 = TextEditingController();
  final _p2 = TextEditingController();
  bool _ob1 = true, _ob2 = true; // <— латиница: o-b-1 / o-b-2

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Новый пароль'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _p1,
            obscureText: _ob1,
            decoration: InputDecoration(
              labelText: 'Пароль',
              suffixIcon: IconButton(
                onPressed: () => setState(() => _ob1 = !_ob1),
                icon: Icon(_ob1 ? Icons.visibility_off : Icons.visibility),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _p2,
            obscureText: _ob2,
            decoration: InputDecoration(
              labelText: 'Повторите пароль',
              suffixIcon: IconButton(
                onPressed: () => setState(() => _ob2 = !_ob2),
                icon: Icon(_ob2 ? Icons.visibility_off : Icons.visibility),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            final a = _p1.text.trim(), b = _p2.text.trim();
            if (a.isEmpty || a != b) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Пароли не совпадают')),
              );
              return;
            }
            Navigator.pop(context, a);
          },
          child: const Text('Готово'),
        ),
      ],
    );
  }
}// === БЛОК 4/4 === lib/main.dart (редакторы + выбор цвета + нумерация) ===

class _GroupEditorDialog extends StatefulWidget {
  const _GroupEditorDialog({this.group});
  final Group? group;

  @override
  State<_GroupEditorDialog> createState() => _GroupEditorDialogState();
}

class _GroupEditorDialogState extends State<_GroupEditorDialog> {
  late final TextEditingController _title;
  Color? _color;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.group?.title ?? '');
    _color = widget.group?.color;
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.group == null;
    final id = widget.group?.id ?? 'g_${DateTime.now().microsecondsSinceEpoch}';

    return AlertDialog(
      scrollable: true,
      title: Text(isNew ? 'Новая группа' : 'Редактирование группы'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Название'),
          ),
          const SizedBox(height: 12),
          _ColorPicker(
            value: _color,
            onChanged: (c) => setState(() => _color = c),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            final g = Group(
              id: id,
              title: _title.text.trim().isEmpty
                  ? 'Без названия'
                  : _title.text.trim(),
              colorHex: _color?.toARGB32(),
              locked: widget.group?.locked ?? false,
              passwordHash: widget.group?.passwordHash,
            );
            Navigator.pop(context, g);
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

class _NoteEditorDialog extends StatefulWidget {
  const _NoteEditorDialog({this.note, this.defaultGroupId});
  final Note? note;
  final String? defaultGroupId;

  @override
  State<_NoteEditorDialog> createState() => _NoteEditorDialogState();
}

class _NoteEditorDialogState extends State<_NoteEditorDialog> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late String _id;
  late String? _groupId;
  Color? _color;
  bool _numbering = false;

  @override
  void initState() {
    super.initState();
    _id = widget.note?.id ?? 'n_${DateTime.now().microsecondsSinceEpoch}';
    _title = TextEditingController(text: widget.note?.title ?? '');
    _body = TextEditingController(text: widget.note?.text ?? '');
    _groupId = widget.note?.groupId ?? widget.defaultGroupId;
    _color = widget.note?.color;
  }

  void _toggleNumbering() {
    setState(() => _numbering = !_numbering);

    if (_numbering) {
      final v = _body.value;
      final text = v.text;
      final sel = v.selection;
      final cursor = sel.isValid ? sel.start : text.length;

      final lineStart = text.lastIndexOf('\n', cursor - 1) + 1;
      final lineEndN = text.indexOf('\n', cursor);
      final lineEnd = lineEndN == -1 ? text.length : lineEndN;
      final line = text.substring(lineStart, lineEnd);

      if (line.trim().isEmpty) {
        final withOne = text.replaceRange(cursor, cursor, '1. ');
        _body.value = v.copyWith(
          text: withOne,
          selection: TextSelection.collapsed(offset: cursor + 3),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: LayoutBuilder(
        builder: (context, constraints) => ConstrainedBox(
          constraints: BoxConstraints(maxHeight: constraints.maxHeight * 0.95),
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.note == null
                              ? 'Новая заметка'
                              : 'Редактирование',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: _numbering
                            ? 'Нумерация: включена'
                            : 'Нумерация: выключена',
                        onPressed: _toggleNumbering,
                        icon: Icon(
                          Icons.format_list_numbered,
                          color: _numbering
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Цвет',
                        onPressed: () async {
                          final picked = await showDialog<Color?>(
                            context: context,
                            builder: (_) => _ColorDialog(initial: _color),
                          );
                          if (picked != null) setState(() => _color = picked);
                        },
                        icon: const Icon(Icons.color_lens_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: _title,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Заголовок'),
                  ),
                  const SizedBox(height: 12),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilterChip(
                      label: Text(_groupId == null
                          ? 'Без группы'
                          : 'Сбросить группу'),
                      selected: _groupId == null,
                      onSelected: (_) => setState(() => _groupId = null),
                    ),
                  ),
                  const SizedBox(height: 8),

                  TextField(
                    controller: _body,
                    minLines: 8,
                    maxLines: 16,
                    keyboardType: TextInputType.multiline,
                    inputFormatters: [
                      _NumberingFormatter(() => _numbering),
                    ],
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Текст заметки…',
                    ),
                  ),

                  const SizedBox(height: 16),

                  _ColorPicker(
                    value: _color,
                    onChanged: (c) => setState(() => _color = c),
                  ),

                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Отмена'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () {
                          final note = Note(
                            id: _id,
                            title: _title.text.trim(),
                            text: _body.text,
                            groupId: _groupId,
                            colorHex: _color?.toARGB32(),
                            updatedAt:
                                DateTime.now().millisecondsSinceEpoch,
                          );
                          Navigator.pop(context, note);
                        },
                        child: const Text('Сохранить'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// =======================
/// ВЫБОР ЦВЕТА
/// =======================

class _ColorDialog extends StatefulWidget {
  const _ColorDialog({this.initial});
  final Color? initial;

  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  Color? value;

  @override
  void initState() {
    super.initState();
    value = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Выберите цвет'),
      content: _ColorPicker(
        value: value,
        onChanged: (v) => setState(() => value = v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, widget.initial),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, value),
          child: const Text('Готово'),
        ),
      ],
    );
  }
}

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.value, required this.onChanged});
  final Color? value;
  final ValueChanged<Color?> onChanged;

  static const _palette = [
    Color(0xFFFF7043),
    Color(0xFFE57373),
    Color(0xFFBA68C8),
    Color(0xFF9575CD),
    Color(0xFF64B5F6),
    Color(0xFF4FC3F7),
    Color(0xFF4DB6AC),
    Color(0xFF81C784),
    Color(0xFFAED581),
    Color(0xFFFFD54F),
    Color(0xFFFFB74D),
    Color(0xFFA1887F),
    Color(0xFF90A4AE),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _ColorDot(
          color: null,
          selected: value == null,
          onTap: () => onChanged(null),
        ),
        for (final c in _palette)
          _ColorDot(
            color: c,
            selected: value?.toARGB32() == c.toARGB32(),
            onTap: () => onChanged(c),
          ),
      ],
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ring = selected
        ? Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: 2.5,
              ),
            ),
            child: Center(child: _dot()),
          )
        : _dot();

    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: ring,
    );
  }

  Widget _dot() => Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: color ?? Colors.transparent,
          shape: BoxShape.circle,
          border:
              color == null ? Border.all(color: Colors.grey, width: 1.2) : null,
        ),
      );
}

/// =======================
/// ФОРМАТТЕР НУМЕРАЦИИ
/// =======================

class _NumberingFormatter extends TextInputFormatter {
  final bool Function() enabled;
  _NumberingFormatter(this.enabled);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!enabled()) return newValue;

    final oldText = oldValue.text;
    final newText = newValue.text;

    // ENTER → добавить "<n>. "
    final enteredNewLine =
        newText.length > oldText.length && newText.endsWith('\n');
    if (enteredNewLine) {
      final cursor = newValue.selection.end;
      final before = newText.substring(0, cursor);
      final lines = before.split('\n');

      int nextNum = 1;
      if (lines.length >= 2) {
        final prev = lines[lines.length - 2];
        final m = RegExp(r'^\s*(\d+)\.\s').firstMatch(prev);
        if (m != null) {
          nextNum = int.tryParse(m.group(1) ?? '0')! + 1;
        }
      }

      final insert = '$nextNum. ';
      final updated = newText.replaceRange(cursor, cursor, insert);
      return newValue.copyWith(
        text: updated,
        selection: TextSelection.collapsed(offset: cursor + insert.length),
      );
    }

    // Удаление префикса "n. " одним бэкспейсом
    final removed = oldText.length > newText.length;
    if (removed) {
      final cur = newValue.selection.end;
      final start = newText.lastIndexOf('\n', cur - 1) + 1;
      final end = newText.indexOf('\n', start);
      final line = newText.substring(start, end == -1 ? newText.length : end);

      if (RegExp(r'^\s*\d+\.\s?$').hasMatch(line)) {
        final prefix = RegExp(r'^\s*\d+\.\s?').firstMatch(line)!.group(0)!;
        final updated = newText.replaceRange(start, start + prefix.length, '');
        final shift = prefix.length;
        return newValue.copyWith(
          text: updated,
          selection: TextSelection.collapsed(offset: cur - shift),
        );
      }
    }

    return newValue;
  }
}
