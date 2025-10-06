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
  List<Note> notes = [];
  List<Group> groups = [];
  bool numbering = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final n = prefs.getString('notes');
    final g = prefs.getString('groups');
    setState(() {
      notes = n != null ? (jsonDecode(n) as List).map((e) => Note.fromJson(e)).toList() : [];
      groups = g != null ? (jsonDecode(g) as List).map((e) => Group.fromJson(e)).toList() : [];
    });
    if (notes.isEmpty && groups.isEmpty) _createTestData();
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('notes', jsonEncode(notes.map((e) => e.toJson()).toList()));
    prefs.setString('groups', jsonEncode(groups.map((e) => e.toJson()).toList()));
  }

  void _createTestData() {
    groups = [
      Group(id: 1, title: 'Работа', color: Colors.indigo),
      Group(id: 2, title: 'Личное', color: Colors.purple),
    ];
    notes = List.generate(
      6,
      (i) => Note(
        title: 'Заметка ${i + 1}',
        content: 'Пример содержания заметки ${i + 1}',
        color: Colors.primaries[i % Colors.primaries.length],
      ),
    );
    _saveData();
  }

  void _addNote() async {
    final note = await Navigator.push(context,
        MaterialPageRoute(builder: (_) => NoteEditor(numbering: numbering)));
    if (note != null) {
      setState(() => notes.add(note));
      _saveData();
    }
  }

  void _addGroup() async {
    final controller = TextEditingController();
    await showDialog(
        context: context,
        builder: (_) => AlertDialog(
              title: const Text('Новая группа'),
              content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Название')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
                ElevatedButton(
                    onPressed: () {
                      setState(() {
                        groups.add(Group(id: DateTime.now().millisecondsSinceEpoch, title: controller.text));
                      });
                      _saveData();
                      Navigator.pop(context);
                    },
                    child: const Text('Создать')),
              ],
            ));
  }

  void _toggleLock(Group group) async {
    if (!group.locked) {
      final passCtrl = TextEditingController();
      await showDialog(
          context: context,
          builder: (_) => AlertDialog(
                title: const Text('Установить пароль'),
                content: TextField(controller: passCtrl, obscureText: true),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
                  ElevatedButton(
                      onPressed: () {
                        setState(() {
                          group.password = passCtrl.text;
                          group.locked = true;
                        });
                        _saveData();
                        Navigator.pop(context);
                      },
                      child: const Text('Сохранить')),
                ],
              ));
    } else {
      final passCtrl = TextEditingController();
      await showDialog(
          context: context,
          builder: (_) => AlertDialog(
                title: const Text('Снять пароль'),
                content: TextField(controller: passCtrl, obscureText: true),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
                  ElevatedButton(
                      onPressed: () {
                        if (passCtrl.text == group.password) {
                          setState(() {
                            group.locked = false;
                            group.password = null;
                          });
                          _saveData();
                        }
                        Navigator.pop(context);
                      },
                      child: const Text('Подтвердить')),
                ],
              ));
    }
  }

  Widget _buildGroup(Group g) {
    return GestureDetector(
      onLongPress: () => _toggleLock(g),
      onTap: () {
        if (g.locked) {
          final ctrl = TextEditingController();
          showDialog(
              context: context,
              builder: (_) => AlertDialog(
                    title: Text('Группа ${g.title} защищена'),
                    content: TextField(controller: ctrl, obscureText: true, decoration: const InputDecoration(labelText: 'Пароль')),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
                      ElevatedButton(
                          onPressed: () {
                            if (ctrl.text == g.password) {
                              setState(() => g.locked = false);
                              _saveData();
                              Navigator.pop(context);
                            }
                          },
                          child: const Text('Разблокировать')),
                    ],
                  ));
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.all(6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: g.color.withOpacity(0.8),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (g.locked)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Center(
                      child: Text('☠️', style: TextStyle(fontSize: 48, color: Colors.white.withOpacity(0.9))),
                    ),
                  ),
                ),
              ),
            Text(g.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleNotes = notes.where((n) => n.groupId == null).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes Vault'),
        actions: [
          IconButton(
              icon: Icon(numbering ? Icons.format_list_numbered : Icons.format_list_bulleted),
              onPressed: () => setState(() => numbering = !numbering)),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 120,
            child: ListView(scrollDirection: Axis.horizontal, children: groups.map(_buildGroup).toList()),
          ),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              children: visibleNotes
                  .map((n) => Card(
                        color: n.color.withOpacity(0.8),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(n.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Expanded(child: Text(n.content, overflow: TextOverflow.fade)),
                            ],
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: _addNote, child: const Icon(Icons.add)),
    );
  }
}

class NoteEditor extends StatefulWidget {
  final bool numbering;
  const NoteEditor({super.key, required this.numbering});
  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  final titleCtrl = TextEditingController();
  final contentCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Новая заметка'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Заголовок')),
            TextField(
              controller: contentCtrl,
              decoration: const InputDecoration(labelText: 'Содержание'),
              maxLines: 6,
              onChanged: (t) {
                if (widget.numbering) {
                  final lines = t.split('\n');
                  for (var i = 0; i < lines.length; i++) {
                    if (!lines[i].startsWith('${i + 1}. ')) {
                      lines[i] = '${i + 1}. ${lines[i].replaceAll(RegExp(r'^\d+\. '), '')}';
                    }
                  }
                  final newText = lines.join('\n');
                  if (newText != t) {
                    contentCtrl.text = newText;
                    contentCtrl.selection = TextSelection.collapsed(offset: newText.length);
                  }
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        ElevatedButton(
            onPressed: () => Navigator.pop(context,
                Note(title: titleCtrl.text, content: contentCtrl.text, color: Colors.blueGrey)),
            child: const Text('Сохранить')),
      ],
    );
  }
}
