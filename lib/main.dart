import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:typed_data';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NotesVaultApp());
}

// === МОДЕЛИ ===
class NoteItem {
  String id;
  String title;
  String text;
  bool numbered;
  int? colorHex;
  String? groupId;
  int updatedAt;

  NoteItem({
    required this.id,
    required this.title,
    required this.text,
    this.numbered = false,
    this.colorHex,
    this.groupId,
    required this.updatedAt,
  });

  factory NoteItem.newNote({String? groupId}) => NoteItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: '',
        text: '',
        groupId: groupId,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'text': text,
        'numbered': numbered,
        'colorHex': colorHex,
        'groupId': groupId,
        'updatedAt': updatedAt,
      };

  static NoteItem fromJson(Map<String, dynamic> j) => NoteItem(
        id: j['id'],
        title: j['title'],
        text: j['text'],
        numbered: j['numbered'] ?? false,
        colorHex: j['colorHex'],
        groupId: j['groupId'],
        updatedAt: j['updatedAt'] ?? 0,
      );
}

class GroupItem {
  String id;
  String title;
  int? colorHex;
  String? passHash;
  int updatedAt;

  bool get isPrivate => passHash != null;

  GroupItem({
    required this.id,
    required this.title,
    this.colorHex,
    this.passHash,
    required this.updatedAt,
  });

  factory GroupItem.newGroup() => GroupItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: 'Новая группа',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'colorHex': colorHex,
        'passHash': passHash,
        'updatedAt': updatedAt,
      };

  static GroupItem fromJson(Map<String, dynamic> j) => GroupItem(
        id: j['id'],
        title: j['title'],
        colorHex: j['colorHex'],
        passHash: j['passHash'],
        updatedAt: j['updatedAt'] ?? 0,
      );
}
// === ХРАНИЛИЩЕ ===
class VaultStore extends ChangeNotifier {
  static const _notesKey = 'notes_vault_notes';
  static const _groupsKey = 'notes_vault_groups';
  final List<NoteItem> notes = [];
  final List<GroupItem> groups = [];
  bool loaded = false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final notesRaw = prefs.getString(_notesKey);
    final groupsRaw = prefs.getString(_groupsKey);

    if (notesRaw != null) {
      notes.clear();
      notes.addAll((jsonDecode(notesRaw) as List)
          .map((e) => NoteItem.fromJson(e))
          .toList());
    }

    if (groupsRaw != null) {
      groups.clear();
      groups.addAll((jsonDecode(groupsRaw) as List)
          .map((e) => GroupItem.fromJson(e))
          .toList());
    }

    if (notes.isEmpty && groups.isEmpty) _createDemoData();

    loaded = true;
    notifyListeners();
  }

  void _createDemoData() {
    final demo = List.generate(
        6,
        (i) => NoteItem(
            id: 'demo$i',
            title: 'Пример заметки ${i + 1}',
            text: 'Это тестовая заметка №${i + 1}.',
            updatedAt: DateTime.now().millisecondsSinceEpoch));
    notes.addAll(demo);
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _notesKey, jsonEncode(notes.map((e) => e.toJson()).toList()));
    await prefs.setString(
        _groupsKey, jsonEncode(groups.map((e) => e.toJson()).toList()));
  }

  Future<void> addNote(NoteItem n) async {
    notes.add(n);
    await save();
    notifyListeners();
  }

  Future<void> updateNote(NoteItem n) async {
    final i = notes.indexWhere((x) => x.id == n.id);
    if (i != -1) notes[i] = n;
    await save();
    notifyListeners();
  }

  Future<void> removeNote(NoteItem n) async {
    notes.removeWhere((x) => x.id == n.id);
    await save();
    notifyListeners();
  }

  Future<void> addGroup(GroupItem g) async {
    groups.add(g);
    await save();
    notifyListeners();
  }

  Future<void> updateGroup(GroupItem g) async {
    final i = groups.indexWhere((x) => x.id == g.id);
    if (i != -1) groups[i] = g;
    await save();
    notifyListeners();
  }

  Future<void> removeGroup(GroupItem g) async {
    notes.removeWhere((x) => x.groupId == g.id);
    groups.remove(g);
    await save();
    notifyListeners();
  }
}

// === APP ===
class NotesVaultApp extends StatefulWidget {
  const NotesVaultApp({super.key});
  @override
  State<NotesVaultApp> createState() => _NotesVaultAppState();
}

class _NotesVaultAppState extends State<NotesVaultApp> {
  bool _dark = true;
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      home: NotesHomePage(
        onToggleTheme: () => setState(() => _dark = !_dark),
      ),
    );
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

  @override
  void initState() {
    super.initState();
    store.load();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        if (!store.loaded) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text('Заметки'),
            actions: [
              IconButton(
                icon: const Icon(Icons.brightness_6),
                onPressed: widget.onToggleTheme,
              ),
            ],
          ),
          body: GridView.count(
            crossAxisCount: 2,
            padding: const EdgeInsets.all(12),
            children: [
              for (final g in store.groups)
                _GroupTile(
                  group: g,
                  onOpen: () {},
                  onEdit: () {},
                  onDelete: () => store.removeGroup(g),
                ),
              for (final n in store.notes.where((n) => n.groupId == null))
                Card(
                  color:
                      n.colorHex != null ? Color(n.colorHex!) : Colors.transparent,
                  child: ListTile(
                    title: Text(n.title),
                    subtitle: Text(n.text),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
// === РЕДАКТОР ЗАМЕТОК ===
class NoteEditor extends StatefulWidget {
  final NoteItem? note;
  final String? groupId;
  const NoteEditor({super.key, this.note, this.groupId});

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late TextEditingController _title;
  late TextEditingController _text;
  bool _numbering = false;
  Color? _color;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.note?.title ?? '');
    _text = TextEditingController(text: widget.note?.text ?? '');
    _color =
        widget.note?.colorHex != null ? Color(widget.note!.colorHex!) : null;
    _numbering = widget.note?.numbered ?? false;

    if (_numbering) _ensureFirstNumber();
  }

  void _ensureFirstNumber() {
    final text = _text.text;
    if (text.isEmpty) {
      _text.text = '1. ';
      _text.selection = TextSelection.collapsed(offset: _text.text.length);
    } else {
      final lines = text.split('\n');
      final first = lines.first;
      if (!RegExp(r'^\s*\d+\.\s').hasMatch(first)) {
        lines[0] = '1. $first';
        final joined = lines.join('\n');
        _text.text = joined;
        _text.selection = TextSelection.collapsed(offset: joined.length);
      }
    }
  }

  void _toggleNumbering() {
    setState(() => _numbering = !_numbering);
    if (_numbering) _ensureFirstNumber();
  }

  Future<void> _save() async {
    final note = widget.note ?? NoteItem.newNote(groupId: widget.groupId);
    note.title = _title.text.trim();
    note.text = _text.text;
    note.numbered = _numbering;
    note.colorHex = _color?.value;
    note.updatedAt = DateTime.now().millisecondsSinceEpoch;
    Navigator.pop(context, note);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text(widget.note == null ? 'Новая заметка' : 'Редактирование'),
        actions: [
          IconButton(
            icon: Icon(
              _numbering
                  ? Icons.format_list_numbered
                  : Icons.format_list_bulleted,
            ),
            tooltip: 'Нумерация',
            onPressed: _toggleNumbering,
          ),
          IconButton(
            icon: const Icon(Icons.palette_outlined),
            tooltip: 'Цвет',
            onPressed: () async {
              final c = await _pickColor(context, initial: _color);
              if (c != null) setState(() => _color = c);
            },
          ),
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Сохранить',
            onPressed: _save,
          ),
        ],
        bottom: _color != null
            ? PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: Container(height: 4, color: _color),
              )
            : null,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(
                labelText: 'Заголовок', border: OutlineInputBorder()),
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
                  hintText: 'Текст заметки...', border: OutlineInputBorder()),
            ),
          ),
        ]),
      ),
    );
  }
}

// === ВЫБОР ЦВЕТА ===
Future<Color?> _pickColor(BuildContext context, {Color? initial}) async {
  final colors = _palette();
  return showDialog<Color>(
    context: context,
    builder: (_) {
      Color? selected = initial;
      return AlertDialog(
        title: const Text('Выберите цвет'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in colors)
              InkWell(
                onTap: () => selected = c,
                child: StatefulBuilder(
                  builder: (context, setStateInner) {
                    final selectedNow = selected?.value == c.value;
                    return GestureDetector(
                      onTap: () => setStateInner(() => selected = c),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selectedNow
                                ? Colors.white
                                : Colors.grey.shade400,
                            width: selectedNow ? 3 : 1,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Отмена')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const Text('Готово')),
        ],
      );
    },
  );
}

// === НУМЕРАЦИЯ ===
class _NumberingFormatter extends TextInputFormatter {
  final bool Function() isOn;
  _NumberingFormatter(this.isOn);

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (!isOn()) return newValue;
    final caret = newValue.selection.baseOffset;
    if (caret <= 0 || caret > newValue.text.length) return newValue;
    if (newValue.text[caret - 1] != '\n') return newValue;

    // Найдём номер предыдущей строки
    final prevStart = newValue.text.lastIndexOf('\n', caret - 2) + 1;
    final prevLine = newValue.text.substring(prevStart, caret - 1);

    final reg = RegExp(r'^\s*(\d+)\.\s');
    final m = reg.firstMatch(prevLine);
    if (m == null) return newValue;

    final next = int.parse(m.group(1)!) + 1;
    final prefix = '$next. ';

    final text = newValue.text.substring(0, caret) +
        prefix +
        newValue.text.substring(caret);

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret + prefix.length),
    );
  }
}

// === ЦВЕТА ===
List<Color> _palette() => const [
      Colors.red,
      Colors.pink,
      Colors.purple,
      Colors.deepPurple,
      Colors.indigo,
      Colors.blue,
      Colors.lightBlue,
      Colors.cyan,
      Colors.teal,
      Colors.green,
      Colors.lightGreen,
      Colors.lime,
      Colors.yellow,
      Colors.orange,
      Colors.deepOrange,
      Colors.brown,
      Colors.grey,
      Colors.blueGrey,
    ];

// === ХЭШ ===
String _hash(String text) {
  final bytes = utf8.encode(text);
  final digest = sha256.convert(bytes);
  return digest.toString();
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
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              if (group.isPrivate)
                const Icon(Icons.lock_outline, size: 20),
              IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: onEdit,
              ),
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
                child: const Center(
                  child: Icon(Icons.lock_outline, size: 32, color: Colors.white70),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return content;
  }
}}
