import 'package:flutter/material.dart';

void main() => runApp(const NotesMiniApp());

/* ===================== APP ===================== */

class NotesMiniApp extends StatefulWidget {
  const NotesMiniApp({super.key});
  @override
  State<NotesMiniApp> createState() => _NotesMiniAppState();
}

class _NotesMiniAppState extends State<NotesMiniApp> {
  ThemeMode _mode = ThemeMode.light;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Заметки',
      themeMode: _mode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        cardTheme: const CardTheme(margin: EdgeInsets.all(8)),
      ),
      darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
      ),
      home: NotesHomePage(
        onToggleTheme: () => setState(() {
          _mode = _mode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
        }),
        isDark: _mode == ThemeMode.dark,
      ),
    );
  }
}

/* ===================== MODEL ===================== */

class Note {
  String id;
  String text;
  int updatedAtMs;
  Note({
    required this.id,
    required this.text,
    required this.updatedAtMs,
  });

  factory Note.newNote() => Note(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        text: '',
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
}

/* ===================== HOME ===================== */

class NotesHomePage extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final bool isDark;
  const NotesHomePage({
    super.key,
    required this.onToggleTheme,
    required this.isDark,
  });

  @override
  State<NotesHomePage> createState() => _NotesHomePageState();
}

class _NotesHomePageState extends State<NotesHomePage> {
  final List<Note> _notes = <Note>[];

  Future<void> _openEditor({Note? src}) async {
    final res = await Navigator.of(context).push<Note>(
      MaterialPageRoute(builder: (_) => NoteEditor(note: src)),
    );
    if (res == null) return;
    setState(() {
      if (src == null) {
        _notes.add(res);
      } else {
        final i = _notes.indexWhere((n) => n.id == src.id);
        if (i != -1) _notes[i] = res;
      }
    });
  }

  void _delete(Note n) {
    setState(() => _notes.removeWhere((x) => x.id == n.id));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Заметки'),
        actions: [
          IconButton(
            tooltip: 'Сменить тему',
            icon: Icon(widget.isDark ? Icons.light_mode : Icons.dark_mode),
            onPressed: widget.onToggleTheme,
          ),
        ],
      ),
      body: _notes.isEmpty
          ? const Center(child: Text('Нет заметок'))
          : GridView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _notes.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemBuilder: (_, i) {
                final n = _notes[i];
                return GestureDetector(
                  onTap: () => _openEditor(src: n),
                  onLongPress: () => _confirmDelete(n),
                  child: Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              n.text.isEmpty ? 'Без текста' : n.text,
                              maxLines: 8,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _formatTime(n.updatedAtMs),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Padding(
        // поднимаем кнопку, чтобы не задевала системную панель
        padding: const EdgeInsets.only(bottom: 72),
        child: FloatingActionButton.extended(
          onPressed: () => _openEditor(),
          icon: const Icon(Icons.add),
          label: const Text('Новая'),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Note n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить заметку?'),
        content: const Text('Действие нельзя отменить.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok == true) _delete(n);
  }

  String _formatTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return 'Обновлено: ${_pad(dt.day)}.${_pad(dt.month)}.${dt.year} ${_pad(dt.hour)}:${_pad(dt.minute)}';
    // _pad — ниже
  }
}

String _pad(int n) => n.toString().padLeft(2, '0');

/* ===================== EDITOR ===================== */

class NoteEditor extends StatefulWidget {
  final Note? note;
  const NoteEditor({super.key, this.note});

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late final TextEditingController _c;
  bool _numbered = false;
  TextEditingValue _last = const TextEditingValue();
  bool _internalEdit = false;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.note?.text ?? '');
    _last = _c.value;
    _c.addListener(_onChanged);
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    _c.dispose();
    super.dispose();
  }

  void _toggleNumbering() {
    setState(() => _numbered = !_numbered);
    // При включении — если строка пустая, поставить "1. "
    if (_numbered && _c.text.trim().isEmpty) {
      _internalEdit = true;
      _c.text = '1. ';
      _c.selection = TextSelection.collapsed(offset: _c.text.length);
      _internalEdit = false;
      _last = _c.value;
    }
  }

  void _onChanged() {
    if (_internalEdit) return;
    final now = _c.value;
    final old = _last;
    final caret = now.selection.baseOffset;

    if (_numbered && caret >= 0) {
      final insertedOneChar =
          now.text.length == old.text.length + 1 &&
          now.selection.baseOffset == old.selection.baseOffset + 1;

      // Нажат Enter — начинаем новый нумерованный пункт
      if (insertedOneChar &&
          now.text.substring(0, caret).endsWith('\n')) {
        final before = now.text.substring(0, caret);
        final lines = before.split('\n');
        // считаем непустые пункты (без префикса "N. ")
        int count = 0;
        for (final l in lines) {
          final stripped = l.replaceFirst(RegExp(r'^\d+\. '), '');
          if (stripped.trim().isNotEmpty) count++;
        }
        final nextNum = count + 1;
        final insert = '$nextNum. ';

        _internalEdit = true;
        _c.value = TextEditingValue(
          text: now.text.replaceRange(caret, caret, insert),
          selection: TextSelection.collapsed(offset: caret + insert.length),
        );
        _internalEdit = false;
        _last = _c.value;
        return;
      }

      // Если включили нумерацию и курсор в пустой первой строке — подставим "1. "
      final lineStart = now.text.lastIndexOf('\n', caret - 1) + 1;
      final lineEnd = now.text.indexOf('\n', caret);
      final end = lineEnd == -1 ? now.text.length : lineEnd;
      final line = now.text.substring(lineStart, end);
      final hasPrefix = RegExp(r'^\d+\. ').hasMatch(line);
      final left = now.text.substring(lineStart, caret);
      if (!hasPrefix && left.trim().isEmpty && line.trim().isEmpty) {
        const insert = '1. ';
        _internalEdit = true;
        _c.value = TextEditingValue(
          text: now.text.replaceRange(lineStart, lineStart, insert),
          selection: TextSelection.collapsed(offset: caret + insert.length),
        );
        _internalEdit = false;
        _last = _c.value;
        return;
      }
    }

    _last = now;
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.note == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'Новая заметка' : 'Редактирование'),
        actions: [
          IconButton(
            tooltip: 'Нумерация',
            icon: Icon(_numbered ? Icons.format_list_numbered : Icons.list),
            onPressed: _toggleNumbering,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _c,
            autofocus: true,
            minLines: 10,
            maxLines: null,
            decoration: const InputDecoration(
              hintText: 'Текст заметки…',
              border: InputBorder.none,
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          // поднимаем кнопки, чтобы не мешала системная панель
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.close),
                  label: const Text('Отмена'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    final note = (widget.note ?? Note.newNote())
                      ..text = _c.text.trimRight()
                      ..updatedAtMs = DateTime.now().millisecondsSinceEpoch;
                    Navigator.pop(context, note);
                  },
                  icon: const Icon(Icons.save),
                  label: const Text('Сохранить'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
