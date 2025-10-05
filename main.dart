
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await settings.load();
  runApp(const NotesApp());
}

/* === Settings (Theme) === */
final settings = SettingsStore();
enum AppThemeMode { system, light, dark }
class SettingsStore extends ChangeNotifier {
  static const _k = 'settings_theme_v1';
  AppThemeMode themeMode = AppThemeMode.system;
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_k);
    if (raw != null) {
      final m = Map<String, dynamic>.from(jsonDecode(raw));
      themeMode = switch (m['theme'] as String? ?? 'system') {
        'light' => AppThemeMode.light,
        'dark' => AppThemeMode.dark,
        _ => AppThemeMode.system,
      };
    }
  }
  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_k, jsonEncode({
      'theme': switch (themeMode) {
        AppThemeMode.light => 'light',
        AppThemeMode.dark => 'dark',
        _ => 'system',
      }
    }));
  }
  Future<void> setTheme(AppThemeMode m) async { themeMode = m; await _save(); notifyListeners(); }
  ThemeMode get asFlutter => switch (themeMode) {
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}

/* === App === */
class NotesApp extends StatelessWidget {
  const NotesApp({super.key});
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'notes_vault',
        themeMode: settings.asFlutter,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
          inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
        ),
        darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.dark),
        ),
        home: const HomePage(),
      ),
    );
  }
}

/* === Model === */
class Note {
  String id;
  String text;
  int? colorHex;
  String? groupId;
  bool numbered;
  int updatedAtMs;
  Note({required this.id, required this.text, this.colorHex, this.groupId, this.numbered=false, required this.updatedAtMs});
  factory Note.newNote()=> Note(id: DateTime.now().microsecondsSinceEpoch.toString(), text:'', updatedAtMs: DateTime.now().millisecondsSinceEpoch);
  Map<String,dynamic> toJson()=> {'id':id,'text':text,'colorHex':colorHex,'groupId':groupId,'numbered':numbered,'updatedAtMs':updatedAtMs};
  static Note fromJson(Map<String,dynamic> j)=> Note(id:j['id'], text:j['text']??'', colorHex:j['colorHex'], groupId:j['groupId'], numbered:j['numbered']??false, updatedAtMs:j['updatedAtMs']??DateTime.now().millisecondsSinceEpoch);
}
class Group {
  String id;
  String title;
  bool isPrivate;
  String? password; // plain for simplicity
  int updatedAtMs;
  Group({required this.id, required this.title, required this.updatedAtMs, this.isPrivate=false, this.password});
  Map<String,dynamic> toJson()=> {'id':id,'title':title,'isPrivate':isPrivate,'password':password,'updatedAtMs':updatedAtMs};
  static Group fromJson(Map<String,dynamic> j)=> Group(id:j['id'], title:j['title']??'', updatedAtMs:j['updatedAtMs']??DateTime.now().millisecondsSinceEpoch, isPrivate:j['isPrivate']??false, password:j['password']);
}

/* === Store === */
class Store extends ChangeNotifier {
  static const _k='nv_store_v1';
  final List<Note> _notes=[]; final List<Group> _groups=[];
  bool loaded=false; String? err;
  List<Note> get notes=> List.unmodifiable(_notes);
  List<Group> get groups=> List.unmodifiable(_groups);

  Future<void> load() async {
    try{
      final p=await SharedPreferences.getInstance();
      final raw=p.getString(_k);
      if(raw!=null){
        final m=jsonDecode(raw);
        final ns=(m['notes'] as List? ?? []).map((e)=>Note.fromJson(Map<String,dynamic>.from(e))).toList();
        final gs=(m['groups'] as List? ?? []).map((e)=>Group.fromJson(Map<String,dynamic>.from(e))).toList();
        _notes..clear()..addAll(ns); _groups..clear()..addAll(gs);
      }
      if(_notes.isEmpty){
        _notes.addAll([
          Note(id: DateTime.now().microsecondsSinceEpoch.toString(), text:'Добро пожаловать!\n∎ Перетаскивайте заметки друг на друга — группы\n∎ Долгое удержание — перетаскивание\n∎ Меню «⋮» на карточке — Поделиться/Экспорт', colorHex: const Color(0xFF64B5F6).value, updatedAtMs: DateTime.now().millisecondsSinceEpoch),
        ]);
        await _save();
      }
    }catch(e){ err='$e'; } finally { loaded=true; notifyListeners(); }
  }
  Future<void> _save() async {
    final p=await SharedPreferences.getInstance();
    await p.setString(_k, jsonEncode({'notes': _notes.map((e)=>e.toJson()).toList(), 'groups': _groups.map((e)=>e.toJson()).toList()}));
  }
  Future<void> addNote(Note n) async { _notes.add(n); await _save(); notifyListeners(); }
  Future<void> updNote(Note n) async { final i=_notes.indexWhere((x)=>x.id==n.id); if(i!=-1){ _notes[i]=n; await _save(); notifyListeners(); } }
  Future<void> delNote(String id) async { _notes.removeWhere((n)=>n.id==id); await _save(); notifyListeners(); }
  Future<void> addGroup(Group g) async { _groups.add(g); await _save(); notifyListeners(); }
  Future<void> updGroup(Group g) async { final i=_groups.indexWhere((x)=>x.id==g.id); if(i!=-1){ _groups[i]=g; await _save(); notifyListeners(); } }
  Future<void> delGroup(String id) async { _notes.removeWhere((n)=>n.groupId==id); _groups.removeWhere((g)=>g.id==id); await _save(); notifyListeners(); }
  List<Note> inGroup(String gid)=> _notes.where((n)=>n.groupId==gid).toList();

  Future<void> addToGroup(String noteId, String gid) async { final i=_notes.indexWhere((n)=>n.id==noteId); if(i!=-1){ _notes[i].groupId=gid; _notes[i].updatedAtMs=DateTime.now().millisecondsSinceEpoch; await _save(); notifyListeners(); } }
  Future<void> removeFromGroup(String noteId) async { final i=_notes.indexWhere((n)=>n.id==noteId); if(i!=-1){ _notes[i].groupId=null; _notes[i].updatedAtMs=DateTime.now().millisecondsSinceEpoch; await _save(); notifyListeners(); } }
  Future<void> createGroupWith(String aId, String bId) async {
    final a=_notes.firstWhere((n)=>n.id==aId); final b=_notes.firstWhere((n)=>n.id==bId);
    if(a.groupId!=null && b.groupId==null){ await addToGroup(b.id, a.groupId!); return; }
    if(b.groupId!=null && a.groupId==null){ await addToGroup(a.id, b.groupId!); return; }
    final gid=DateTime.now().microsecondsSinceEpoch.toString();
    final g=Group(id:gid, title:'Группа', updatedAtMs: DateTime.now().millisecondsSinceEpoch);
    _groups.add(g);
    a.groupId=gid; b.groupId=gid;
    await _save(); notifyListeners();
  }

  // Export / Import
  String exportNoteJson(Note n)=> jsonEncode(n.toJson());
  String exportGroupJson(String gid){
    final g=_groups.firstWhere((x)=>x.id==gid);
    final items=inGroup(gid).map((e)=>e.toJson()).toList();
    return jsonEncode({'group': g.toJson(), 'notes': items});
  }
  Future<String> importNoteJson(String raw) async {
    final n=Note.fromJson(Map<String,dynamic>.from(jsonDecode(raw)));
    if(_notes.any((x)=>x.id==n.id)) n.id=DateTime.now().microsecondsSinceEpoch.toString();
    await addNote(n); return 'Импортирована заметка';
  }
  Future<String> importGroupJson(String raw) async {
    final m=jsonDecode(raw);
    final g=Group.fromJson(Map<String,dynamic>.from(m['group']));
    final notes=(m['notes'] as List? ?? []).map((e)=>Note.fromJson(Map<String,dynamic>.from(e))).toList();
    final gid = _groups.any((x)=>x.id==g.id) ? DateTime.now().microsecondsSinceEpoch.toString() : g.id;
    await addGroup(Group(id:gid, title:g.title, updatedAtMs: DateTime.now().millisecondsSinceEpoch, isPrivate:g.isPrivate, password:g.password));
    for(final n in notes){ n.groupId=gid; if(_notes.any((x)=>x.id==n.id)) n.id=DateTime.now().microsecondsSinceEpoch.toString(); await addNote(n); }
    return 'Импортирована группа и ${notes.length} заметок';
  }
}

/* === UI === */
class HomePage extends StatefulWidget { const HomePage({super.key}); @override State<HomePage> createState()=>_HomePageState(); }
class _HomePageState extends State<HomePage>{
  final store=Store(); final search=TextEditingController(); bool dragging=false;
  @override void initState(){ super.initState(); store.addListener(()=>setState((){})); store.load(); }
  @override void dispose(){ store.dispose(); search.dispose(); super.dispose(); }
  @override Widget build(BuildContext context){
    final items = [
      ...store.groups.map((g)=>_GridItem.group(g)),
      ...store.notes.where((n)=>n.groupId==null).map((n)=>_GridItem.note(n)),
    ].where((it){
      final q=search.text.trim().toLowerCase();
      if(q.isEmpty) return true;
      if(it.isGroup) return it.group!.title.toLowerCase().contains(q) || store.inGroup(it.group!.id).any((n)=>n.text.toLowerCase().contains(q));
      return it.note!.text.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: TextField(controller:search, decoration: const InputDecoration(hintText:'Поиск…', isDense:true), onChanged: (_)=>setState((){})),
        actions: [
          IconButton(icon: const Icon(Icons.download), tooltip:'Импорт', onPressed: _openImport),
          IconButton(icon: const Icon(Icons.settings), onPressed: _openSettings),
          IconButton(icon: const Icon(Icons.add), tooltip:'Новая', onPressed: ()=>_openNote()),
        ],
      ),
      body: !store.loaded? const Center(child:CircularProgressIndicator()) :
        Padding(
          padding: const EdgeInsets.only(top:8,left:8,right:8,bottom:80),
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: .95),
            itemCount: items.length,
            itemBuilder: (_,i){
              final it=items[i];
              if(it.isGroup){
                final g=it.group!; final within=store.inGroup(g.id);
                return LongPressDraggable<_DragPayload>(
                  data: _DragPayload.group(g.id),
                  feedback: _dragFeedback(_GroupCard(group:g, notes:within, onTap: ()=>_openGroup(g))),
                  onDragStarted: ()=>setState(()=>dragging=true),
                  onDragEnd: (_)=>setState(()=>dragging=false),
                  child: DragTarget<_DragPayload>(
                    onWillAccept: (p)=>p!=null,
                    onAccept: (p) async {
                      if(p.isNote) await store.addToGroup(p.id, g.id);
                      if(p.isGroup && p.id!=g.id){
                        for(final n in store.inGroup(p.id)){ await store.addToGroup(n.id, g.id); }
                        await store.delGroup(p.id);
                      }
                    },
                    builder: (_,__,___)=> _GroupCard(
                      group:g, notes:within, onTap: ()=>_openGroup(g),
                      menu: PopupMenuButton<String>(
                        onSelected: (v){
                          if(v=='share') _shareGroup(g);
                          if(v=='export') _exportGroup(g);
                          if(v=='private') _togglePrivate(g);
                        },
                        itemBuilder: (_)=>[
                          const PopupMenuItem(value:'share', child: Text('Поделиться')),
                          const PopupMenuItem(value:'export', child: Text('Экспорт JSON')),
                          PopupMenuItem(value:'private', child: Text(g.isPrivate? 'Снять приватность' : 'Сделать приватной')),
                        ],
                      ),
                    ),
                  ),
                );
              }else{
                final n=it.note!;
                return LongPressDraggable<_DragPayload>(
                  data: _DragPayload.note(n.id),
                  feedback: _dragFeedback(_NoteCard(n, onTap: ()=>_openNote(src:n))),
                  onDragStarted: ()=>setState(()=>dragging=true),
                  onDragEnd: (_)=>setState(()=>dragging=false),
                  child: DragTarget<_DragPayload>(
                    onWillAccept: (p)=>p!=null,
                    onAccept: (p) async {
                      if(p.isNote && p.id!=n.id) await store.createGroupWith(p.id, n.id);
                      if(p.isGroup){ await store.addToGroup(n.id, p.id); }
                    },
                    builder: (_,__,___)=> _NoteCard(n,
                      onTap: ()=>_openNote(src:n),
                      menu: PopupMenuButton<String>(
                        onSelected: (v){ if(v=='share') Share.share(n.text, subject: _first(n.text)); if(v=='export') _exportNote(n); },
                        itemBuilder: (_)=> const [
                          PopupMenuItem(value:'share', child: Text('Поделиться')),
                          PopupMenuItem(value:'export', child: Text('Экспорт JSON')),
                        ],
                      ),
                    ),
                  ),
                );
              }
            },
          ),
        ),
      floatingActionButton: dragging? _DeleteFab(onAccept: (p) async {
        final ok = await _confirm(context, 'Удалить?', p.isNote? 'Удалить заметку?' : 'Удалить группу и её заметки?');
        if(ok!=true) return;
        if(p.isNote) await store.delNote(p.id); else await store.delGroup(p.id);
        setState(()=>dragging=false);
      }) : null,
    );
  }

  Widget _dragFeedback(Widget child)=> Material(color:Colors.transparent, child: Opacity(opacity:.9, child: SizedBox(width:160, child: child)));
  Future<void> _openNote({Note? src}) async {
    final res = await showModalBottomSheet<Note>(_ , context: context, isScrollControlled: true, showDragHandle: true, builder: (_)=> NoteEditor(note: src));
    if(res==null) return;
    if(src==null) await store.addNote(res); else await store.updNote(res);
  }
  Future<void> _openGroup(Group g) async {
    if(g.isPrivate){
      final ok = await _askPass(g);
      if(ok!=true) return;
    }
    await showModalBottomSheet<void>(_ , context: context, isScrollControlled: true, showDragHandle: true, builder: (_)=> GroupEditor(
      group: g,
      notesProvider: ()=>store.inGroup(g.id),
      onRename: (t) async => store.updGroup(Group(id:g.id, title:t, updatedAtMs: DateTime.now().millisecondsSinceEpoch, isPrivate:g.isPrivate, password:g.password)),
      onEditNote: (n) async => _openNote(src:n),
      onUngroupNote: (n) async => store.removeFromGroup(n.id),
      onDeleteNote: (n) async => store.delNote(n.id),
      onExportGroup: ()=> _exportGroup(g),
      onShareGroup: ()=> _shareGroup(g),
      onTogglePrivate: ()=> _togglePrivate(g),
      onChangePassword: ()=> _changePassword(g),
    ));
  }
  void _openSettings(){
    showModalBottomSheet<void>(_ , context: context, showDragHandle: true, builder: (_)=> const SettingsSheet());
  }
  void _openImport(){
    showModalBottomSheet<void>(_ , context: context, showDragHandle: true, isScrollControlled: true, builder: (_)=> ImportCenter(
      onImportNote: (raw) async { final msg= await store.importNoteJson(raw); if(context.mounted){ Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg))); }},
      onImportGroup: (raw) async { final msg= await store.importGroupJson(raw); if(context.mounted){ Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg))); }},
    ));
  }

  void _exportNote(Note n){ Share.share(store.exportNoteJson(n), subject:'Экспорт заметки (JSON)'); }
  void _exportGroup(Group g){ Share.share(store.exportGroupJson(g.id), subject:'Экспорт группы (JSON)'); }
  void _shareGroup(Group g){
    final title = g.title.isEmpty? 'Группа' : g.title;
    final body = ['# $title', ...store.inGroup(g.id).map((n)=>n.text)].join('\n\n');
    Share.share(body, subject:title);
  }
  Future<bool?> _askPass(Group g) async {
    final c=TextEditingController();
    return showDialog<bool>(context: context, builder: (_)=> AlertDialog(
      title: const Text('Пароль'),
      content: TextField(controller:c, obscureText:true, decoration: const InputDecoration(labelText:'Введите пароль')),
      actions: [ TextButton(onPressed: ()=>Navigator.pop(context,false), child: const Text('Отмена')), FilledButton(onPressed: ()=>Navigator.pop(context, c.text==(g.password??'')), child: const Text('Ок')), ],
    ));
  }
  Future<void> _changePassword(Group g) async {
    final c=TextEditingController(text:g.password??'');
    final res = await showDialog<String?>(context: context, builder: (_)=> AlertDialog(
      title: const Text('Пароль группы'),
      content: TextField(controller:c, obscureText:true, decoration: const InputDecoration(labelText:'Новый пароль (пусто — снять)')),
      actions: [ TextButton(onPressed: ()=>Navigator.pop(context,null), child: const Text('Отмена')), FilledButton(onPressed: ()=>Navigator.pop(context,c.text), child: const Text('Сохранить')) ],
    ));
    if(res==null) return;
    await store.updGroup(Group(id:g.id, title:g.title, updatedAtMs: DateTime.now().millisecondsSinceEpoch, isPrivate: res.isNotEmpty, password: res.isEmpty? null: res));
  }
  Future<void> _togglePrivate(Group g) async {
    if(g.isPrivate){ await store.updGroup(Group(id:g.id, title:g.title, updatedAtMs: DateTime.now().millisecondsSinceEpoch, isPrivate:false, password:null)); }
    else { await _changePassword(g); }
  }
}

class _GridItem{
  final Note? note; final Group? group;
  _GridItem.note(this.note): group=null;
  _GridItem.group(this.group): note=null;
  bool get isNote=> note!=null; bool get isGroup=> group!=null;
}
class _DragPayload{
  final String type; final String id;
  _DragPayload._(this.type,this.id);
  factory _DragPayload.note(String id)=> _DragPayload._('note', id);
  factory _DragPayload.group(String id)=> _DragPayload._('group', id);
  bool get isNote=> type=='note'; bool get isGroup=> type=='group';
}

class _DeleteFab extends StatelessWidget{
  final void Function(_DragPayload) onAccept;
  const _DeleteFab({required this.onAccept});
  @override Widget build(BuildContext context){
    final cs=Theme.of(context).colorScheme;
    return DragTarget<_DragPayload>(
      onWillAccept: (_)=>true,
      onAccept: onAccept,
      builder: (_,cand,__)=>
        FloatingActionButton.extended(
          onPressed: null,
          backgroundColor: cand.isNotEmpty? cs.error : cs.error.withOpacity(.85),
          label: const Row(children:[Icon(Icons.delete_forever,color:Colors.white), SizedBox(width:8), Text('Удалить', style: TextStyle(color: Colors.white))]),
        ),
    );
  }
}

class _NoteCard extends StatelessWidget{
  final Note n; final VoidCallback onTap; final PopupMenuButton<String>? menu;
  const _NoteCard(this.n,{required this.onTap, this.menu});
  @override Widget build(BuildContext context){
    final color = n.colorHex!=null? Color(n.colorHex!): null;
    return Card(child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      onDoubleTap: () async { await Clipboard.setData(ClipboardData(text:n.text)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Текст скопирован'))); },
      child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
        Row(children:[
          Container(width:14,height:14, decoration: BoxDecoration(color: color??Colors.transparent, shape: BoxShape.circle, border: Border.all(color: Theme.of(context).colorScheme.outlineVariant))),
          const SizedBox(width:8),
          Expanded(child: Text(_first(n.text).isEmpty? 'Без названия': _first(n.text), maxLines:1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
          if(menu!=null) menu!,
        ]),
        const SizedBox(height:8),
        Expanded(child: Text(_rest(n.text), maxLines:6, overflow: TextOverflow.ellipsis)),
      ])),
    ));
  }
}

class _GroupCard extends StatelessWidget{
  final Group group; final List<Note> notes; final VoidCallback onTap; final PopupMenuButton<String>? menu;
  const _GroupCard({required this.group, required this.notes, required this.onTap, this.menu});
  @override Widget build(BuildContext context){
    final preview = notes.take(3).toList();
    return Card(child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
        Row(children:[
          Icon(group.isPrivate? Icons.lock : Icons.folder, size:18),
          const SizedBox(width:8),
          Expanded(child: Text(group.title.isEmpty? 'Группа': group.title, maxLines:1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
          Text('${notes.length}', style: Theme.of(context).textTheme.labelLarge),
          if(menu!=null) menu!,
        ]),
        const SizedBox(height:10),
        Expanded(child: Row(children:[
          for(final n in preview) Expanded(child: Container(
            margin: const EdgeInsets.only(right:6), padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: (n.colorHex!=null? Color(n.colorHex!) : Theme.of(context).colorScheme.surfaceVariant).withOpacity(.4), borderRadius: BorderRadius.circular(8)),
            child: Text(_first(n.text).isEmpty? 'Без названия': _first(n.text), maxLines:2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
          )),
          if(preview.length<3) Expanded(child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
            child: const Icon(Icons.add, size:20),
          )),
        ])),
      ])),
    ));
  }
}

/* === Editors === */
class NoteEditor extends StatefulWidget{ final Note? note; const NoteEditor({super.key,this.note}); @override State<NoteEditor> createState()=>_NoteEditorState(); }
class _NoteEditorState extends State<NoteEditor>{
  late final TextEditingController _c; TextEditingValue _last = const TextEditingValue(); bool _internal=false; bool _numbered=false;
  @override void initState(){ super.initState(); _c=TextEditingController(text: widget.note?.text??''); _last=_c.value; _numbered= widget.note?.numbered?? false; _c.addListener(_onChanged); }
  @override void dispose(){ _c.removeListener(_onChanged); _c.dispose(); super.dispose(); }
  void _onChanged(){
    if(_internal){ _last=_c.value; return; }
    final now=_c.value, old=_last; final caret=now.selection.baseOffset;
    if(_numbered && caret>=0){
      final lineStart = now.text.lastIndexOf('\n', caret-1)+1;
      final lineEnd = now.text.indexOf('\n', caret); final end = lineEnd==-1? now.text.length : lineEnd;
      final line = now.text.substring(lineStart, end);
      final hasPrefix = RegExp(r'^\d+\. ').hasMatch(line);

      final insertedOne = now.text.length == old.text.length + 1 and now.selection.baseOffset == old.selection.baseOffset + 1;
      if(insertedOne){
        final ch = now.text[caret-1];
        if(ch!='\n' && !hasPrefix){
          final pre = now.text.substring(lineStart, caret);
          if(pre.trim().length==1){
            final before = now.text.substring(0, lineStart);
            final lastBreak = before.lastIndexOf('\n\n');
            final blockStart = lastBreak>=0? lastBreak+2 : 0;
            final block = before.substring(blockStart);
            final blockLines = block.isEmpty? <String>[] : block.split('\n');
            int count=0; for(final l in blockLines){ final stripped = l.replaceFirst(RegExp(r'^\d+\. '), ''); if(stripped.trim().isNotEmpty) count++; }
            final number = (count==0)? 1 : count+1;
            final insert = '$number. ';
            _internal=true; _c.value = TextEditingValue(text: now.text.replaceRange(lineStart, lineStart, insert), selection: TextSelection.collapsed(offset: caret + insert.length)); _internal=false; _last=_c.value; return;
          }
        }
      }

      final insertedNl = now.text.length == old.text.length + 1 and now.selection.baseOffset == old.selection.baseOffset + 1 and now.text.substring(0, caret).endsWith('\n');
      if(insertedNl){
        final before = now.text.substring(0, caret);
        final lines = before.split('\n'); final prev = lines.length>=2? lines[lines.length-2] : '';
        if(RegExp(r'^\d+\. $').hasMatch(prev)){
          final startPrev = before.lastIndexOf('\n', before.length - prev.length - 2);
          final absStart = startPrev==-1? 0 : startPrev+1; final absEnd = absStart + prev.length;
          final newText = now.text.replaceRange(absStart, absEnd, '');
          final delta = prev.length;
          _internal=true; _c.value = TextEditingValue(text:newText, selection: TextSelection.collapsed(offset: caret - delta)); _internal=false; _last=_c.value; return;
        }
        final lastBreak = before.substring(0, before.length-1).lastIndexOf('\n\n');
        final blockStart = lastBreak>=0? lastBreak+2 : 0;
        final blockText = before.substring(blockStart, before.length-1);
        final blockLines = blockText.isEmpty? <String>[] : blockText.split('\n');
        int count=0; for(final l in blockLines){ final stripped = l.replaceFirst(RegExp(r'^\d+\. '), ''); if(stripped.trim().isNotEmpty) count++; }
        final next = count+1; final insert = '$next. ';
        _internal=true; _c.value = TextEditingValue(text: now.text.replaceRange(caret, caret, insert), selection: TextSelection.collapsed(offset: caret + insert.length)); _internal=false; _last=_c.value; return;
      }
    }
    _last=now;
  }

  void _maybeInsertFirst(){
    final v=_c.value; final caret=v.selection.baseOffset; if(caret<0) return;
    final lineStart = v.text.lastIndexOf('\n', caret-1)+1;
    final lineEnd = v.text.indexOf('\n', caret); final end = lineEnd==-1? v.text.length: lineEnd;
    final line = v.text.substring(lineStart, end);
    final hasPrefix = RegExp(r'^\d+\. ').hasMatch(line);
    final left=v.text.substring(lineStart, caret);
    if(!hasPrefix && left.trim().isEmpty && line.trim().isEmpty){
      final insert='1. ';
      _internal=true; _c.value=TextEditingValue(text: v.text.replaceRange(lineStart, lineStart, insert), selection: TextSelection.collapsed(offset: caret + insert.length)); _internal=false; _last=_c.value;
    }
  }

  @override Widget build(BuildContext context){
    final isNew = widget.note==null;
    return SafeArea(child: Padding(
      padding: EdgeInsets.only(left:16,right:16, top:8, bottom: MediaQuery.of(context).viewInsets.bottom+12),
      child: Column(mainAxisSize: MainAxisSize.min, children:[
        Align(alignment: Alignment.centerLeft, child: Text(isNew? 'Новая заметка':'Редактирование', style: Theme.of(context).textTheme.titleLarge)),
        const SizedBox(height:8),
        Row(children:[
          Expanded(child: OutlinedButton.icon(onPressed: ()=>Navigator.maybePop(context), icon: const Icon(Icons.close), label: const Text('Отмена'))),
          const SizedBox(width:12),
          Expanded(child: FilledButton.icon(onPressed: (){
            final text=_c.text.trimRight();
            final note=(widget.note?? Note.newNote())..text=text..numbered=_numbered..updatedAtMs=DateTime.now().millisecondsSinceEpoch;
            Navigator.pop(context, note);
          }, icon: const Icon(Icons.save), label: const Text('Сохранить'))),
        ]),
        const SizedBox(height:8),
        SwitchListTile(
          dense:true, contentPadding: EdgeInsets.zero,
          value: _numbered, onChanged: (v){ setState(()=>_numbered=v); if(v) _maybeInsertFirst(); },
          title: const Text('Нумерация строк'),
        ),
        const SizedBox(height:10),
        TextField(controller:_c, autofocus:true, minLines:8, maxLines:16, keyboardType: TextInputType.multiline, textInputAction: TextInputAction.newline, decoration: const InputDecoration(hintText:'Текст заметки…')),
      ]),
    ));
  }
}

class GroupEditor extends StatelessWidget{
  final Group group;
  final List<Note> Function() notesProvider;
  final Future<void> Function(String title) onRename;
  final Future<void> Function(Note note) onEditNote;
  final Future<void> Function(Note note) onUngroupNote;
  final Future<void> Function(Note note) onDeleteNote;
  final VoidCallback onExportGroup;
  final VoidCallback onShareGroup;
  final Future<void> Function() onTogglePrivate;
  final Future<void> Function() onChangePassword;
  const GroupEditor({super.key, required this.group, required this.notesProvider, required this.onRename, required this.onEditNote, required this.onUngroupNote, required this.onDeleteNote, required this.onExportGroup, required this.onShareGroup, required this.onTogglePrivate, required this.onChangePassword});
  @override Widget build(BuildContext context){
    final notes = notesProvider();
    final titleCtrl = TextEditingController(text: group.title);
    return SafeArea(child: Padding(
      padding: EdgeInsets.only(left:16,right:16, top:8, bottom: MediaQuery.of(context).viewInsets.bottom+12),
      child: Column(mainAxisSize: MainAxisSize.min, children:[
        Align(alignment: Alignment.centerLeft, child: Text('Группа', style: Theme.of(context).textTheme.titleLarge)),
        const SizedBox(height:8),
        Row(children:[
          Expanded(child: OutlinedButton.icon(onPressed: ()=>Navigator.maybePop(context), icon: const Icon(Icons.close), label: const Text('Отмена'))),
          const SizedBox(width:12),
          Expanded(child: FilledButton.icon(onPressed: () async { await onRename(titleCtrl.text.trim()); if(context.mounted) Navigator.pop(context); }, icon: const Icon(Icons.save), label: const Text('Сохранить'))),
        ]),
        const SizedBox(height:12),
        TextField(controller:titleCtrl, decoration: const InputDecoration(labelText:'Заголовок группы')),
        const SizedBox(height:12),
        Wrap(spacing:8, runSpacing:8, children:[
          FilledButton.icon(onPressed: onShareGroup, icon: const Icon(Icons.share), label: const Text('Поделиться')),
          OutlinedButton.icon(onPressed: onExportGroup, icon: const Icon(Icons.upload), label: const Text('Экспорт JSON')),
          OutlinedButton.icon(onPressed: onTogglePrivate, icon: Icon(group.isPrivate? Icons.lock_open : Icons.lock), label: Text(group.isPrivate? 'Снять приватность':'Сделать приватной')),
          if(group.isPrivate) OutlinedButton.icon(onPressed: onChangePassword, icon: const Icon(Icons.password), label: const Text('Пароль')),
        ]),
        const SizedBox(height:12),
        Align(alignment: Alignment.centerLeft, child: Text('Заметки (${notes.length}):', style: Theme.of(context).textTheme.labelLarge)),
        const SizedBox(height:8),
        ConstrainedBox(constraints: const BoxConstraints(maxHeight: 300), child: ListView.separated(
          itemCount: notes.length, separatorBuilder: (_, __)=> const Divider(height:1),
          itemBuilder: (_,i){
            final n=notes[i];
            return ListTile(
              dense:true,
              leading: const Icon(Icons.note),
              title: Text(_first(n.text).isEmpty? 'Без названия': _first(n.text), maxLines:1, overflow: TextOverflow.ellipsis),
              subtitle: Text(_rest(n.text), maxLines:1, overflow: TextOverflow.ellipsis),
              onTap: ()=> onEditNote(n),
              trailing: Wrap(spacing:8, children:[
                IconButton(tooltip:'Отделить', icon: const Icon(Icons.call_split), onPressed: ()=> onUngroupNote(n)),
                IconButton(tooltip:'Удалить', icon: const Icon(Icons.delete_outline), onPressed: ()=> onDeleteNote(n)),
              ]),
            );
          },
        )),
      ]),
    ));
  }
}

/* === Import center === */
class ImportCenter extends StatefulWidget{
  final Future<void> Function(String raw) onImportNote;
  final Future<void> Function(String raw) onImportGroup;
  const ImportCenter({super.key, required this.onImportNote, required this.onImportGroup});
  @override State<ImportCenter> createState()=> _ImportCenterState();
}
class _ImportCenterState extends State<ImportCenter>{
  final c=TextEditingController(); bool isGroup=false;
  @override void dispose(){ c.dispose(); super.dispose(); }
  @override Widget build(BuildContext context){
    return SafeArea(child: Padding(
      padding: EdgeInsets.only(left:16,right:16, top:8, bottom: MediaQuery.of(context).viewInsets.bottom+12),
      child: Column(mainAxisSize: MainAxisSize.min, children:[
        Align(alignment: Alignment.centerLeft, child: Text('Импорт JSON', style: Theme.of(context).textTheme.titleLarge)),
        const SizedBox(height:8),
        SwitchListTile(dense:true, contentPadding: EdgeInsets.zero, value:isGroup, onChanged:(v)=>setState(()=>isGroup=v), title: const Text('Импортировать группу')),
        const SizedBox(height:8),
        TextField(controller:c, minLines:6, maxLines:10, decoration: const InputDecoration(hintText:'Вставьте JSON…')),
        const SizedBox(height:8),
        Row(children:[
          Expanded(child: OutlinedButton.icon(onPressed: ()=>Navigator.maybePop(context), icon: const Icon(Icons.close), label: const Text('Отмена'))),
          const SizedBox(width:12),
          Expanded(child: FilledButton.icon(onPressed: () async { final raw=c.text.trim(); if(raw.isEmpty) return; if(isGroup) await widget.onImportGroup(raw); else await widget.onImportNote(raw); }, icon: const Icon(Icons.download_done), label: const Text('Импорт'))),
        ]),
      ]),
    ));
  }
}

/* === SettingsSheet === */
class SettingsSheet extends StatefulWidget{ const SettingsSheet({super.key}); @override State<SettingsSheet> createState()=> _SettingsSheetState(); }
class _SettingsSheetState extends State<SettingsSheet>{
  AppThemeMode _m = settings.themeMode;
  @override Widget build(BuildContext context){
    return SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(16,8,16,12),
      child: Column(mainAxisSize: MainAxisSize.min, children:[
        Align(alignment: Alignment.centerLeft, child: Text('Панель управления', style: Theme.of(context).textTheme.titleLarge)),
        const SizedBox(height:8),
        Row(children:[
          Expanded(child: OutlinedButton.icon(onPressed: ()=>Navigator.maybePop(context), icon: const Icon(Icons.close), label: const Text('Отмена'))),
          const SizedBox(width:12),
          Expanded(child: FilledButton.icon(onPressed: () async { await settings.setTheme(_m); if(context.mounted) Navigator.pop(context); }, icon: const Icon(Icons.save), label: const Text('Сохранить'))),
        ]),
        const SizedBox(height:12),
        SegmentedButton<AppThemeMode>(
          segments: const [
            ButtonSegment(value: AppThemeMode.system, label: Text('Системная'), icon: Icon(Icons.phone_android)),
            ButtonSegment(value: AppThemeMode.light, label: Text('Светлая'), icon: Icon(Icons.wb_sunny_outlined)),
            ButtonSegment(value: AppThemeMode.dark, label: Text('Тёмная'), icon: Icon(Icons.dark_mode_outlined)),
          ],
          selected: {_m},
          onSelectionChanged: (s)=> setState(()=> _m = s.first),
        ),
      ]),
    ));
  }
}

/* === Helpers === */
String _first(String t){ final ls=t.trim().split('\n'); return ls.isEmpty? '' : ls.first.trim(); }
String _rest(String t){ final ls=t.trim().split('\n'); return ls.length<=1? '' : ls.skip(1).join('\n').trim(); }
Future<bool?> _confirm(BuildContext c, String title, String msg){
  return showDialog<bool>(context:c, builder: (_)=> AlertDialog(
    title: Text(title), content: Text(msg),
    actions:[ TextButton(onPressed: ()=>Navigator.pop(c,false), child: const Text('Отмена')), FilledButton(onPressed: ()=>Navigator.pop(c,true), child: const Text('Удалить')) ],
  ));
}
