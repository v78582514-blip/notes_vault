import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NotesVaultApp());
}

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
  String? pass;
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
  final List<NoteItem> _notes = [];
  final List<GroupItem> _groups = [];
  bool _isDark = true;

  bool get isDark => _isDark;
  List<NoteItem> get notes => List.unmodifiable(_notes);
  List<GroupItem> get groups => List.unmodifiable(_groups);

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _isDark = p.getBool(_kTheme) ?? true;
    final gRaw = p.getString(_kGroups);
    final nRaw = p.getString(_kNotes);
    if (gRaw != null) {
      _groups.addAll(((jsonDecode(gRaw) as List).cast<Map<String, dynamic>>())
          .map(GroupItem.fromJson));
    }
    if (nRaw != null) {
      _notes.addAll(((jsonDecode(nRaw) as List).cast<Map<String, dynamic>>())
          .map(NoteItem.fromJson));
    }
    if (_notes.isEmpty) _installFixtures();
    notifyListeners();
  }

  void _installFixtures() {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (int i = 1; i <= 6; i++) {
      _notes.add(NoteItem(
        id: 'n$i',
        title: 'Заметка $i',
        text: 'Это тестовая заметка №$i\nМожно редактировать или удалить.',
        updatedAt: now,
      ));
    }
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kNotes, jsonEncode(_notes.map((e) => e.toJson()).toList()));
    await p.setString(_kGroups, jsonEncode(_groups.map((e) => e.toJson()).toList()));
    await p.setBool(_kTheme, _isDark);
  }

  Future<void> addNote(NoteItem n) async {
    _notes.add(n);
    await save();
    notifyListeners();
  }

  Future<void> updateNote(NoteItem n) async {
    final i = _notes.indexWhere((x) => x.id == n.id);
    if (i != -1) _notes[i] = n;
    await save();
    notifyListeners();
  }

  Future<void> removeNote(String id) async {
    _notes.removeWhere((n) => n.id == id);
    await save();
    notifyListeners();
  }

  Future<void> addGroup(GroupItem g) async {
    _groups.add(g);
    await save();
    notifyListeners();
  }

  Future<void> removeGroup(String id) async {
    _groups.removeWhere((g) => g.id == id);
    _notes.removeWhere((n) => n.groupId == id);
    await save();
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _isDark = !_isDark;
    await save();
    notifyListeners();
  }
}

/* ============================ UI ============================ */

class NotesHome extends StatefulWidget {
  final VaultStore store;
  const NotesHome({super.key, required this.store});
  @override
  State<NotesHome> createState() => _NotesHomeState();
}

class _NotesHomeState extends State<NotesHome> {
  GroupItem? openedGroup;

  @override
  Widget build(BuildContext context) {
    final groups = widget.store.groups;
    final notes = widget.store.notes
        .where((n) => n.groupId == openedGroup?.id)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(openedGroup?.title ?? 'Заметки'),
        actions: [
          IconButton(
            icon: const Icon(Icons.color_lens_outlined),
            onPressed: widget.store.toggleTheme,
          ),
        ],
      ),
      body: openedGroup == null
          ? GridView.count(
              crossAxisCount: 2,
              children: [
                for (final g in groups)
                  _GroupTile(
                    group: g,
                    onOpen: () {
                      if (g.isPrivate) {
                        _askPassword(g);
                      } else {
                        setState(() => openedGroup = g);
                      }
                    },
                    onEdit: () => _editGroup(g),
                    onDelete: () => _confirmDeleteGroup(g),
                    blurred: false,
                  ),
              ],
            )
          : GridView.count(
              crossAxisCount: 2,
              children: [
                for (final n in notes)
                  GestureDetector(
                    onTap: () => _editNote(n),
                    onLongPress: () => _confirmDeleteNote(n),
                    child: Card(
                      color: n.colorHex != null ? Color(n.colorHex!) : null,
                      margin: const EdgeInsets.all(8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          n.title.isEmpty ? 'Без названия' : n.title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: openedGroup == null ? _createGroup : _createNote,
        child: Icon(openedGroup == null ? Icons.add_box : Icons.note_add),
      ),
    );
  }

  Future<void> _askPassword(GroupItem g) async {
    final ctrl = TextEditingController();
    final pass = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Введите пароль'),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          decoration: const InputDecoration(hintText: 'Пароль'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('OK')),
        ],
      ),
    );
    if (pass == g.pass) {
      setState(() => openedGroup = g);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Неверный пароль')),
      );
    }
  }

  Future<void> _createGroup() async {
    final g = GroupItem.newGroup();
    await widget.store.addGroup(g);
  }

  Future<void> _editGroup(GroupItem g) async {
    final ctrl = TextEditingController(text: g.title);
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Название группы'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Введите название')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          TextButton(
            onPressed: () async {
              g.title = ctrl.text;
              await widget.store.save();
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    setState(() {});
  }

  Future<void> _createNote() async {
    final n = NoteItem.newNote(groupId: openedGroup?.id);
    await widget.store.addNote(n);
  }

  Future<void> _editNote(NoteItem n) async {
    final titleCtrl = TextEditingController(text: n.title);
    final textCtrl = TextEditingController(text: n.text);
    await showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: titleCtrl, decoration: const InputDecoration(hintText: 'Заголовок')),
          TextField(controller: textCtrl, minLines: 5, maxLines: 12, decoration: const InputDecoration(hintText: 'Текст')),
          Row(children: [
            Expanded(
              child: TextButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('Сохранить'),
                onPressed: () async {
                  n.title = titleCtrl.text;
                  n.text = textCtrl.text;
                  n.updatedAt = DateTime.now().millisecondsSinceEpoch;
                  await widget.store.updateNote(n);
                  if (mounted) Navigator.pop(context);
                },
              ),
            ),
            Expanded(
              child: TextButton.icon(
                icon: const Icon(Icons.cancel),
                label: const Text('Отмена'),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _confirmDeleteNote(NoteItem n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить заметку?'),
        content: const Text('Это действие нельзя отменить.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok == true) widget.store.removeNote(n.id);
  }

  Future<void> _confirmDeleteGroup(GroupItem g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить группу?'),
        content: const Text('Все заметки внутри также будут удалены.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok == true) widget.store.removeGroup(g.id);
  }
}

/* ============================ GROUP TILE ============================ */
class _GroupTile extends StatelessWidget {
  final GroupItem group;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool blurred;

  const _GroupTile({
    required this.group,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    required this.blurred,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final color = group.colorHex != null ? Color(group.colorHex!) : null;

    Widget content = Card(
      margin: const EdgeInsets.all(8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: color?.withOpacity(0.15),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (color != null)
                Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              Expanded(
                child: Text(
                  group.title.isEmpty ? 'Без названия' : group.title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              if (group.isPrivate)
                const Icon(Icons.lock_outline, size: 20),
              IconButton(icon: const Icon(Icons.more_vert), onPressed: onEdit),
            ],
          ),
        ),
      ),
    );

    if (blurred) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            content,
            BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                color: Colors.black.withOpacity(0.3),
                alignment: Alignment.center,
                child: const Icon(Icons.lock_outline, size: 36, color: Colors.white70),
              ),
            ),
          ],
        ),
      );
    }

    return content;
  }
}
