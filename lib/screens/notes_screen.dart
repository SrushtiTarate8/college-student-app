import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:open_filex/open_filex.dart';
import 'theme_provider.dart';

// ── Theme constants ────────────────────────────────────────────────────────────
const Color kYellow      = Color(0xFFFDD835);
const Color kYellowLight = Color(0xFFFFF9C4);
const Color kYellowDeep  = Color(0xFFF9A825);
const Color kYellowAccent= Color(0xFFFFEE58);

const LinearGradient kYellowGradient = LinearGradient(
  colors: [kYellow, kYellowDeep],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const LinearGradient kYellowGradientLight = LinearGradient(
  colors: [Color(0xFFFFF9C4), Color(0xFFFFF176)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

// ─────────────────────────────────────────────────────────────────────────────
// Data model
// ─────────────────────────────────────────────────────────────────────────────

class FolderNode {
  String id;
  String name;
  List<FolderNode> children;
  List<Map<String, dynamic>> notes;

  FolderNode({
    required this.id,
    required this.name,
    List<FolderNode>? children,
    List<Map<String, dynamic>>? notes,
  })  : children = children ?? [],
        notes    = notes    ?? [];

  // Serialise (File objects → path string)
  Map<String, dynamic> toJson() => {
    'id':       id,
    'name':     name,
    'children': children.map((c) => c.toJson()).toList(),
    'notes':    notes.map((n) {
      final m = Map<String, dynamic>.from(n);
      m['date'] = (n['date'] as DateTime).toIso8601String();
      if (n['type'] == 'image' || n['type'] == 'file') {
        m['path'] = (n['file'] as File).path;
        m.remove('file');
      }
      return m;
    }).toList(),
  };

  factory FolderNode.fromJson(Map<String, dynamic> j) {
    final notes = (j['notes'] as List? ?? []).map((n) {
      final m = Map<String, dynamic>.from(n as Map);
      m['date'] = DateTime.parse(m['date'] as String);
      if ((m['type'] == 'image' || m['type'] == 'file') && m['path'] != null) {
        m['file'] = File(m['path'] as String);
        m.remove('path');
      }
      return m;
    }).toList();

    return FolderNode(
      id:       j['id']   as String,
      name:     j['name'] as String,
      children: (j['children'] as List? ?? [])
          .map((c) => FolderNode.fromJson(c as Map<String, dynamic>))
          .toList(),
      notes:    notes.cast<Map<String, dynamic>>(),
    );
  }

  // Recursive find by id
  FolderNode? findById(String targetId) {
    if (id == targetId) return this;
    for (final child in children) {
      final found = child.findById(targetId);
      if (found != null) return found;
    }
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen>
    with SingleTickerProviderStateMixin {
  late FolderNode _root;
  // "Breadcrumb" stack — first item is always root
  final List<FolderNode> _breadcrumb = [];
  bool _loading = true;

  FolderNode get _current => _breadcrumb.last;

  // ── Persistence ───────────────────────────────────────────────────────────

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('notes_tree_v2', jsonEncode(_root.toJson()));
    } catch (e) {
      debugPrint('_save error: $e');
    }
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString('notes_tree_v2');
      if (raw != null) {
        _root = FolderNode.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } else {
        _root = FolderNode(id: 'root', name: 'My Notes');
      }
    } catch (e) {
      debugPrint('_load error: $e');
      _root = FolderNode(id: 'root', name: 'My Notes');
    }
    _breadcrumb
      ..clear()
      ..add(_root);
    if (mounted) setState(() => _loading = false);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _openFolder(FolderNode folder) =>
      setState(() => _breadcrumb.add(folder));

  void _navigateTo(int breadcrumbIndex) {
    if (breadcrumbIndex >= _breadcrumb.length) return;
    setState(() {
      _breadcrumb.removeRange(breadcrumbIndex + 1, _breadcrumb.length);
    });
  }

  // ── CRUD – folders ────────────────────────────────────────────────────────

  void _addFolder(bool isDark) {
    final ctrl = TextEditingController();
    _showInputDialog(
      isDark:  isDark,
      title:   "New Folder",
      hint:    "Folder name",
      confirm: "Create",
      onConfirm: (text) {
        if (text.trim().isEmpty) return;
        setState(() {
          _current.children.add(FolderNode(
            id:   '${DateTime.now().millisecondsSinceEpoch}',
            name: text.trim(),
          ));
        });
        _save();
      },
    );
  }

  void _renameFolder(FolderNode folder, bool isDark) {
    _showInputDialog(
      isDark:       isDark,
      title:        "Rename Folder",
      hint:         "New name",
      initialValue: folder.name,
      confirm:      "Rename",
      onConfirm: (text) {
        if (text.trim().isEmpty) return;
        setState(() => folder.name = text.trim());
        _save();
      },
    );
  }

  void _deleteFolder(FolderNode folder) {
    setState(() => _current.children.remove(folder));
    _save();
  }

  // ── CRUD – notes ──────────────────────────────────────────────────────────

  void _addNote(String text) {
    if (text.trim().isEmpty) return;
    setState(() {
      _current.notes.add({
        'text': text,
        'type': 'text',
        'time': TimeOfDay.now().format(context),
        'date': DateTime.now(),
      });
    });
    _save();
  }

  void _deleteNote(int index) {
    setState(() => _current.notes.removeAt(index));
    _save();
  }

  void _editNote(int index, bool isDark) {
    final ctrl = TextEditingController(
        text: _current.notes[index]['text'] as String);
    showDialog(
      context: context,
      builder: (_) => _styledDialog(
        isDark: isDark,
        title:  "Edit Note",
        content: TextField(
          controller: ctrl,
          maxLines: 5,
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
          decoration: _inputDecoration(isDark, "Edit your note…"),
        ),
        actions: [
          _cancelButton(isDark),
          _confirmButton(
            label: "Update",
            onTap: () {
              setState(() {
                _current.notes[index]['text'] = ctrl.text;
                _current.notes[index]['date'] = DateTime.now();
              });
              _save();
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  // ── Media ─────────────────────────────────────────────────────────────────

  Future<void> _pickImage() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (f != null) {
      setState(() {
        _current.notes.add({
          'text': f.name,
          'file': File(f.path),
          'type': 'image',
          'time': TimeOfDay.now().format(context),
          'date': DateTime.now(),
        });
      });
      _save();
    }
  }

  Future<void> _pickFile() async {
    final r = await FilePicker.platform
        .pickFiles(type: FileType.any, withData: false);
    if (r != null && r.files.single.path != null) {
      setState(() {
        _current.notes.add({
          'text': r.files.single.name,
          'file': File(r.files.single.path!),
          'type': 'file',
          'time': TimeOfDay.now().format(context),
          'date': DateTime.now(),
        });
      });
      _save();
    }
  }

  // ── Open / view ───────────────────────────────────────────────────────────

  Future<void> _openFile(File file) async {
    final res = await OpenFilex.open(file.path);
    if (res.type != ResultType.done && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Cannot open: ${res.message}"),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  void _viewImage(File file) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(file.path.split('/').last,
            style: const TextStyle(fontSize: 14)),
      ),
      body: Center(child: InteractiveViewer(
        child: Image.file(file, fit: BoxFit.contain),
      )),
    )));
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────

  void _showInputDialog({
    required bool isDark,
    required String title,
    required String hint,
    String? initialValue,
    required String confirm,
    required void Function(String) onConfirm,
  }) {
    final ctrl = TextEditingController(text: initialValue ?? '');
    showDialog(
      context: context,
      builder: (_) => _styledDialog(
        isDark:  isDark,
        title:   title,
        content: TextField(
          controller: ctrl,
          autofocus:  true,
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
          decoration: _inputDecoration(isDark, hint),
        ),
        actions: [
          _cancelButton(isDark),
          _confirmButton(label: confirm, onTap: () {
            onConfirm(ctrl.text);
            Navigator.pop(context);
          }),
        ],
      ),
    );
  }

  void _showAddNoteDialog(bool isDark) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => _styledDialog(
        isDark:  isDark,
        title:   "Add Note",
        content: TextField(
          controller: ctrl,
          maxLines:   4,
          autofocus:  true,
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
          decoration: _inputDecoration(isDark, "Write something…"),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.image,
                color: isDark ? Colors.white70 : Colors.black54),
            onPressed: () { Navigator.pop(context); _pickImage(); },
          ),
          IconButton(
            icon: Icon(Icons.attach_file,
                color: isDark ? Colors.white70 : Colors.black54),
            onPressed: () { Navigator.pop(context); _pickFile(); },
          ),
          _cancelButton(isDark),
          _confirmButton(label: "Add", onTap: () {
            _addNote(ctrl.text);
            Navigator.pop(context);
          }),
        ],
      ),
    );
  }

  // ── Dialog helpers ────────────────────────────────────────────────────────

  Widget _styledDialog({
    required bool isDark,
    required String title,
    required Widget content,
    required List<Widget> actions,
  }) =>
      AlertDialog(
        backgroundColor:
        isDark ? const Color(0xFF1E1E2E) : Colors.white,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black)),
        content: content,
        actionsPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        actions: actions,
      );

  InputDecoration _inputDecoration(bool isDark, String hint) =>
      InputDecoration(
        hintText:  hint,
        hintStyle: TextStyle(
            color: isDark ? Colors.white38 : Colors.black38),
        border:    const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12))),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kYellowDeep, width: 2),
        ),
        filled:    true,
        fillColor: isDark
            ? const Color(0xFF2A2A3E)
            : Colors.grey.shade100,
      );

  Widget _cancelButton(bool isDark) => TextButton(
    style: TextButton.styleFrom(
        foregroundColor: isDark ? Colors.white60 : Colors.black54),
    onPressed: () => Navigator.pop(context),
    child: const Text("Cancel"),
  );

  Widget _confirmButton({
    required String label,
    required VoidCallback onTap,
  }) =>
      ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: kYellowDeep,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
        ),
        onPressed: onTap,
        child: Text(label),
      );

  // ── Note content builder ──────────────────────────────────────────────────

  Widget _buildNoteContent(
      Map<String, dynamic> note, {
        required Color primaryText,
        required Color secondaryText,
      }) {
    final type = note['type'] as String;
    final file = note['file'] as File?;

    if (type == 'image' && file != null) {
      if (!file.existsSync()) {
        return Row(children: [
          const Icon(Icons.broken_image, color: Colors.grey),
          const SizedBox(width: 8),
          Text("Image not found", style: TextStyle(color: secondaryText)),
        ]);
      }
      return GestureDetector(
        onTap: () => _viewImage(file),
        child: Stack(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(file,
                height: 160, width: double.infinity, fit: BoxFit.cover),
          ),
          Positioned(
            bottom: 6, right: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.open_in_full, color: Colors.white, size: 12),
                  SizedBox(width: 3),
                  Text("Tap to expand",
                      style: TextStyle(color: Colors.white, fontSize: 10)),
                ],
              ),
            ),
          ),
        ]),
      );
    }

    if (type == 'file' && file != null) {
      final fileName = note['text'] as String;
      final ext      = fileName.split('.').last.toUpperCase();
      final exists   = file.existsSync();

      IconData icon; Color iconColor;
      if (ext == 'PDF')                       { icon = Icons.picture_as_pdf; iconColor = Colors.redAccent; }
      else if (['DOC','DOCX'].contains(ext))  { icon = Icons.description;    iconColor = Colors.blueAccent; }
      else if (['XLS','XLSX'].contains(ext))  { icon = Icons.table_chart;    iconColor = Colors.green; }
      else if (['PPT','PPTX'].contains(ext))  { icon = Icons.slideshow;      iconColor = Colors.orange; }
      else if (['MP4','MOV','AVI'].contains(ext)) { icon = Icons.videocam;   iconColor = Colors.purple; }
      else if (['MP3','WAV','AAC'].contains(ext)) { icon = Icons.music_note;  iconColor = Colors.teal; }
      else                                    { icon = Icons.insert_drive_file; iconColor = Colors.grey; }

      return GestureDetector(
        onTap: exists ? () => _openFile(file) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: iconColor.withOpacity(0.25)),
          ),
          child: Row(children: [
            Icon(icon, color: iconColor, size: 32),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fileName,
                    style: TextStyle(
                        color: primaryText,
                        fontWeight: FontWeight.w500, fontSize: 13),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(exists ? "Tap to open" : "File not found",
                    style: TextStyle(
                        color: exists ? iconColor : Colors.redAccent,
                        fontSize: 11)),
              ],
            )),
            Icon(Icons.open_in_new,
                color: exists ? iconColor : Colors.grey, size: 18),
          ]),
        ),
      );
    }

    return Text(note['text'] as String,
        style: TextStyle(color: primaryText, fontSize: 14));
  }

  // ── Formatting ────────────────────────────────────────────────────────────

  String _formatDate(DateTime d) => "${d.day}/${d.month}/${d.year}";

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark        = themeProvider.isDarkMode;

    final bgColor       = isDark ? const Color(0xFF0F0E17) : const Color(0xFFFFFDE7);
    final cardColor     = isDark ? const Color(0xFF1A1A2E) : Colors.white;
    final primaryText   = isDark ? Colors.white : Colors.black;
    final secondaryText = isDark ? Colors.white54 : Colors.grey.shade600;
    final borderColor   = isDark
        ? Colors.white.withOpacity(0.08)
        : kYellowDeep.withOpacity(0.15);

    if (_loading) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(child: CircularProgressIndicator(
            valueColor: const AlwaysStoppedAnimation(kYellowDeep))),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      body: Column(
        children: [
          // ── AppBar with gradient ──────────────────────────────────────────
          _buildAppBar(isDark, themeProvider),

          // ── Breadcrumb path ───────────────────────────────────────────────
          _buildBreadcrumb(isDark, primaryText, secondaryText),

          // ── Folder grid + notes list ──────────────────────────────────────
          Expanded(
            child: _buildContent(
                isDark, cardColor, primaryText, secondaryText, borderColor),
          ),
        ],
      ),
      floatingActionButton: _buildFAB(isDark),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

  Widget _buildAppBar(bool isDark, ThemeProvider themeProvider) {
    return Container(
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(
          colors: [Color(0xFF1A1A2E), Color(0xFF2C2C4E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        )
            : kYellowGradient,
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.5)
                : kYellowDeep.withOpacity(0.4),
            blurRadius: 16, offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Row(children: [
            // Back button (if not root)
            if (_breadcrumb.length > 1)
              GestureDetector(
                onTap: () => _navigateTo(_breadcrumb.length - 2),
                child: Container(
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white12
                        : Colors.black.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.arrow_back_ios_new,
                      size: 16,
                      color: isDark ? Colors.white : Colors.black),
                ),
              ),

            // Title
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _current.name,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  if (_breadcrumb.length == 1)
                    Text(
                      "Organize your thoughts ✨",
                      style: TextStyle(
                        color: isDark
                            ? Colors.white54
                            : Colors.black.withOpacity(0.55),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),

            // Theme toggle
            GestureDetector(
              onTap: themeProvider.toggleTheme,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 52, height: 28,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: isDark
                      ? const LinearGradient(
                      colors: [Color(0xFF6C63FF), Color(0xFF9B59B6)])
                      : LinearGradient(colors: [
                    Colors.grey.shade400,
                    Colors.grey.shade300
                  ]),
                  boxShadow: [
                    BoxShadow(
                      color: isDark
                          ? const Color(0xFF6C63FF).withOpacity(0.35)
                          : Colors.black.withOpacity(0.15),
                      blurRadius: 8, offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  alignment:
                  isDark ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    width: 22, height: 22,
                    decoration: const BoxDecoration(
                        color: Colors.white, shape: BoxShape.circle),
                    child: Center(
                      child: Icon(
                        isDark
                            ? Icons.dark_mode_rounded
                            : Icons.wb_sunny_rounded,
                        color: isDark
                            ? const Color(0xFF6C63FF)
                            : Colors.amber,
                        size: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Breadcrumb ────────────────────────────────────────────────────────────

  Widget _buildBreadcrumb(
      bool isDark, Color primaryText, Color secondaryText) {
    if (_breadcrumb.length <= 1) return const SizedBox.shrink();

    return Container(
      height: 40,
      color: isDark
          ? const Color(0xFF12122A)
          : kYellowLight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _breadcrumb.length,
        separatorBuilder: (_, __) => Icon(
          Icons.chevron_right,
          size: 18,
          color: isDark ? Colors.white38 : Colors.black38,
        ),
        itemBuilder: (_, i) {
          final isLast = i == _breadcrumb.length - 1;
          return GestureDetector(
            onTap: isLast ? null : () => _navigateTo(i),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    i == 0 ? Icons.home_rounded : Icons.folder_rounded,
                    size: 14,
                    color: isLast
                        ? (isDark ? kYellowAccent : kYellowDeep)
                        : secondaryText,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _breadcrumb[i].name,
                    style: TextStyle(
                      color: isLast
                          ? (isDark ? kYellowAccent : kYellowDeep)
                          : secondaryText,
                      fontSize: 13,
                      fontWeight: isLast
                          ? FontWeight.w700
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Main content ──────────────────────────────────────────────────────────

  Widget _buildContent(
      bool isDark,
      Color cardColor,
      Color primaryText,
      Color secondaryText,
      Color borderColor,
      ) {
    final folders = _current.children;
    final notes   = _current.notes;

    final isEmpty = folders.isEmpty && notes.isEmpty;
    if (isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: isDark
                    ? const LinearGradient(
                    colors: [Color(0xFF2C2C4E), Color(0xFF1A1A2E)])
                    : kYellowGradientLight,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.folder_open_rounded,
                  size: 56,
                  color: isDark ? kYellowAccent : kYellowDeep),
            ),
            const SizedBox(height: 16),
            Text(
              "This folder is empty",
              style: TextStyle(
                  color: primaryText,
                  fontSize: 17,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              "Tap + to add a note or folder",
              style: TextStyle(color: secondaryText, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        // Sub-folders grid
        if (folders.isNotEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            sliver: SliverToBoxAdapter(
              child: Text("Folders",
                  style: TextStyle(
                      color: isDark ? kYellowAccent : kYellowDeep,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 0.6)),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            sliver: SliverGrid(
              gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount:    2,
                childAspectRatio:  2.4,
                crossAxisSpacing:  10,
                mainAxisSpacing:   10,
              ),
              delegate: SliverChildBuilderDelegate(
                    (_, i) => _buildFolderTile(
                    folders[i], isDark, primaryText, secondaryText),
                childCount: folders.length,
              ),
            ),
          ),
        ],

        // Notes section header
        if (notes.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            sliver: SliverToBoxAdapter(
              child: Text("Notes",
                  style: TextStyle(
                      color: isDark ? kYellowAccent : kYellowDeep,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 0.6)),
            ),
          ),

        // Notes list
        if (notes.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                    (_, i) => _buildNoteCard(
                    i, isDark, cardColor, primaryText,
                    secondaryText, borderColor),
                childCount: notes.length,
              ),
            ),
          ),

        if (folders.isNotEmpty && notes.isEmpty)
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  // ── Folder tile ───────────────────────────────────────────────────────────

  Widget _buildFolderTile(
      FolderNode folder,
      bool isDark,
      Color primaryText,
      Color secondaryText,
      ) {
    final subCount  = folder.children.length;
    final noteCount = folder.notes.length;

    return GestureDetector(
      onTap: () => _openFolder(folder),
      child: Container(
        decoration: BoxDecoration(
          gradient: isDark
              ? const LinearGradient(
            colors: [Color(0xFF22223A), Color(0xFF1A1A2E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
              : const LinearGradient(
            colors: [Color(0xFFFFF9C4), Color(0xFFFFF176)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark
                ? kYellowDeep.withOpacity(0.18)
                : kYellowDeep.withOpacity(0.35),
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withOpacity(0.3)
                  : kYellowDeep.withOpacity(0.18),
              blurRadius: 8, offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                // Folder icon with gradient circle
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    gradient: isDark
                        ? const LinearGradient(
                        colors: [Color(0xFF3A3A5E), Color(0xFF2C2C4E)])
                        : kYellowGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    subCount > 0
                        ? Icons.folder_special_rounded
                        : Icons.folder_rounded,
                    color: isDark ? kYellowAccent : Colors.black87,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        folder.name,
                        style: TextStyle(
                          color: primaryText,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _folderSubtitle(subCount, noteCount),
                        style: TextStyle(
                            color: secondaryText, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ]),
            ),

            // Context menu
            Positioned(
              top: 0, right: 0,
              child: PopupMenuButton<String>(
                color: isDark
                    ? const Color(0xFF1E1E2E)
                    : Colors.white,
                icon: Icon(Icons.more_vert,
                    size: 16,
                    color: isDark ? Colors.white38 : Colors.black38),
                onSelected: (v) {
                  if (v == 'rename') {
                    _renameFolder(folder, isDark);
                  } else if (v == 'delete') {
                    _deleteFolder(folder);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'rename',
                    child: Row(children: [
                      Icon(Icons.edit, size: 16,
                          color: isDark ? Colors.white : Colors.black),
                      const SizedBox(width: 8),
                      Text("Rename",
                          style: TextStyle(
                              color: isDark
                                  ? Colors.white
                                  : Colors.black)),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      const Icon(Icons.delete, size: 16,
                          color: Colors.redAccent),
                      const SizedBox(width: 8),
                      const Text("Delete",
                          style: TextStyle(color: Colors.redAccent)),
                    ]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _folderSubtitle(int subFolders, int notes) {
    final parts = <String>[];
    if (subFolders > 0) parts.add("$subFolders folder${subFolders > 1 ? 's' : ''}");
    if (notes      > 0) parts.add("$notes note${notes > 1 ? 's' : ''}");
    return parts.isEmpty ? "Empty" : parts.join(" · ");
  }

  // ── Note card ─────────────────────────────────────────────────────────────

  Widget _buildNoteCard(
      int index,
      bool isDark,
      Color cardColor,
      Color primaryText,
      Color secondaryText,
      Color borderColor,
      ) {
    final note = _current.notes[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.3)
                : kYellowDeep.withOpacity(0.08),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildNoteContent(note,
              primaryText: primaryText, secondaryText: secondaryText),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                    gradient: kYellowGradient,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  "${_formatDate(note['date'] as DateTime)} · ${note['time']}",
                  style: TextStyle(color: secondaryText, fontSize: 11),
                ),
              ]),
              PopupMenuButton<String>(
                color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                icon: Icon(Icons.more_vert,
                    color: secondaryText, size: 20),
                onSelected: (v) {
                  if (v == 'edit' && note['type'] == 'text') {
                    _editNote(index, isDark);
                  } else if (v == 'delete') {
                    _deleteNote(index);
                  }
                },
                itemBuilder: (_) => [
                  if (note['type'] == 'text')
                    PopupMenuItem(
                      value: 'edit',
                      child: Text("Edit",
                          style: TextStyle(
                              color: isDark ? Colors.white : Colors.black)),
                    ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text("Delete",
                        style: TextStyle(
                            color: isDark
                                ? Colors.redAccent
                                : Colors.red)),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── FAB ───────────────────────────────────────────────────────────────────

  Widget _buildFAB(bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Add folder
        FloatingActionButton.small(
          heroTag: 'folder',
          onPressed: () => _addFolder(isDark),
          backgroundColor: isDark
              ? const Color(0xFF2C2C4E)
              : Colors.white,
          foregroundColor: isDark ? kYellowAccent : kYellowDeep,
          elevation: 4,
          child: const Icon(Icons.create_new_folder_rounded),
        ),
        const SizedBox(height: 10),
        // Add note
        FloatingActionButton(
          heroTag: 'note',
          onPressed: () => _showAddNoteDialog(isDark),
          elevation: 6,
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: isDark
                  ? const LinearGradient(
                colors: [Color(0xFF6C63FF), Color(0xFF9B59B6)],
              )
                  : kYellowGradient,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.add,
                color: isDark ? Colors.white : Colors.black,
                size: 28),
          ),
        ),
      ],
    );
  }
}
