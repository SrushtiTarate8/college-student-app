import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'theme_provider.dart';

const Color notesYellow = Color(0xFFFFF59D);

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  Map<String, List<Map<String, dynamic>>> folders = {"General": []};

  String  selectedFolder = "General";
  String? selectedDate;
  bool    _loading       = true;

  // ── Persistence ──────────────────────────────────────────────────────────────

  Future<void> _saveNotes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serialisable = folders.map((folderName, notes) {
        final serNotes = notes
            .where((n) => n['type'] != 'image')
            .map((n) => {
          'text': n['text'] as String,
          'type': n['type'] as String,
          'time': n['time'] as String,
          'date': (n['date'] as DateTime).toIso8601String(),
        })
            .toList();
        return MapEntry(folderName, serNotes);
      });
      await prefs.setString('notes_data', jsonEncode(serialisable));
    } catch (_) {}
  }

  Future<void> _loadNotes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString('notes_data');
      if (raw != null) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final loaded  = <String, List<Map<String, dynamic>>>{};
        decoded.forEach((folder, notesList) {
          loaded[folder] = (notesList as List).map((n) {
            return {
              'text': n['text'] as String,
              'type': n['type'] as String,
              'time': n['time'] as String,
              'date': DateTime.parse(n['date'] as String),
            };
          }).toList();
        });
        loaded.putIfAbsent("General", () => []);
        setState(() {
          folders = loaded;
          if (!folders.containsKey(selectedFolder)) {
            selectedFolder = folders.keys.first;
          }
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  // ── Utilities ─────────────────────────────────────────────────────────────────

  String formatDate(DateTime date) =>
      "${date.day}/${date.month}/${date.year}";

  // ── CRUD ──────────────────────────────────────────────────────────────────────

  void addNote(String text) {
    if (text.trim().isEmpty) return;
    setState(() {
      folders[selectedFolder]!.add({
        "text": text,
        "type": "text",
        "time": TimeOfDay.now().format(context),
        "date": DateTime.now(),
      });
    });
    _saveNotes();
  }

  void deleteNote(int index) {
    setState(() => folders[selectedFolder]!.removeAt(index));
    _saveNotes();
  }

  void editNote(int index, {required bool isDark}) {
    final controller = TextEditingController(
      text: folders[selectedFolder]![index]["text"] as String,
    );

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        title: Text(
          "Edit Note",
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
        ),
        content: TextField(
          controller: controller,
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            filled: true,
            fillColor:
            isDark ? const Color(0xFF2A2A3E) : Colors.grey[100],
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
                foregroundColor:
                isDark ? Colors.white70 : Colors.black),
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: notesYellow,
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              setState(() {
                folders[selectedFolder]![index]["text"] = controller.text;
                folders[selectedFolder]![index]["date"] = DateTime.now();
              });
              _saveNotes();
              Navigator.pop(context);
            },
            child: const Text("Update"),
          ),
        ],
      ),
    );
  }

  // ── Media picks ───────────────────────────────────────────────────────────────

  Future<void> pickImage() async {
    final picker     = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        folders[selectedFolder]!.add({
          "text": "Image",
          "file": File(pickedFile.path),
          "type": "image",
          "time": TimeOfDay.now().format(context),
          "date": DateTime.now(),
        });
      });
    }
  }

  Future<void> pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null) {
      setState(() {
        folders[selectedFolder]!.add({
          "text": result.files.single.name,
          "file": File(result.files.single.path!),
          "type": "file",
          "time": TimeOfDay.now().format(context),
          "date": DateTime.now(),
        });
      });
      _saveNotes();
    }
  }

  // ── Folder dialog ─────────────────────────────────────────────────────────────

  void addFolder({required bool isDark}) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          "New Folder",
          style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black),
        ),
        content: TextField(
          controller: controller,
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
          decoration: InputDecoration(
            hintText: "Enter folder name",
            hintStyle: TextStyle(
                color: isDark ? Colors.white38 : Colors.black38),
            border: const OutlineInputBorder(),
            filled: true,
            fillColor:
            isDark ? const Color(0xFF2A2A3E) : Colors.grey[100],
          ),
        ),
        actionsPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
                foregroundColor:
                isDark ? Colors.white70 : Colors.black),
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: notesYellow,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                setState(() {
                  folders[controller.text.trim()] = [];
                  selectedFolder = controller.text.trim();
                  selectedDate   = null;
                });
                _saveNotes();
              }
              Navigator.pop(context);
            },
            child: const Text("Create"),
          ),
        ],
      ),
    );
  }

  // ── Add note dialog ───────────────────────────────────────────────────────────

  void showAddNoteDialog({required bool isDark}) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        title: Text(
          "Add Note",
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
        ),
        content: TextField(
          controller: controller,
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
          decoration: InputDecoration(
            hintText: "Write something...",
            hintStyle: TextStyle(
                color: isDark ? Colors.white38 : Colors.black38),
            border: const OutlineInputBorder(),
            filled: true,
            fillColor:
            isDark ? const Color(0xFF2A2A3E) : Colors.grey[100],
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.image,
                color: isDark ? Colors.white70 : Colors.black87),
            onPressed: () {
              Navigator.pop(context);
              pickImage();
            },
          ),
          IconButton(
            icon: Icon(Icons.attach_file,
                color: isDark ? Colors.white70 : Colors.black87),
            onPressed: () {
              Navigator.pop(context);
              pickFile();
            },
          ),
          TextButton(
            style: TextButton.styleFrom(
                foregroundColor:
                isDark ? Colors.white70 : Colors.black),
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.black,
              backgroundColor: notesYellow,
            ),
            onPressed: () {
              addNote(controller.text);
              Navigator.pop(context);
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Read ThemeProvider — same pattern as HomeScreen, PlannerScreen, ResultScreen
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark        = themeProvider.isDarkMode;

    // Colour tokens that mirror the rest of the app
    final bgColor       = isDark ? const Color(0xFF0F0E17) : Colors.grey[100]!;
    final cardColor     = isDark ? const Color(0xFF1A1A2E) : Colors.white;
    final primaryText   = isDark ? Colors.white : Colors.black;
    final secondaryText = isDark ? Colors.white54 : Colors.grey;
    final borderColor   = isDark
        ? Colors.white.withOpacity(0.08)
        : Colors.black.withOpacity(0.06);
    final appBarBg      = isDark ? const Color(0xFF1A1A2E) : notesYellow;
    final appBarFg      = isDark ? Colors.white : Colors.black;
    final chipSelected  = isDark ? const Color(0xFF2C2C4E) : notesYellow;
    final chipUnselBg   =
    isDark ? const Color(0xFF1E1E2E) : Colors.grey[200]!;
    final chipBorder    =
    isDark ? Colors.white24 : Colors.transparent;

    if (_loading) {
      return Scaffold(
        backgroundColor: bgColor,
        body: const Center(
            child: CircularProgressIndicator(color: notesYellow)),
      );
    }

    final allNotes = folders[selectedFolder] ?? [];

    final dates = allNotes
        .map((note) => formatDate(note["date"] as DateTime))
        .toSet()
        .toList();

    final notes = selectedDate == null
        ? allNotes
        : allNotes
        .where((note) =>
    formatDate(note["date"] as DateTime) == selectedDate)
        .toList();

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text("My Notes", style: TextStyle(color: appBarFg)),
        backgroundColor: appBarBg,
        foregroundColor: appBarFg,
        elevation: isDark ? 0 : 2,
        actions: [
          // ── Dark-mode toggle (same style as HomeScreen) ─────────────────
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: GestureDetector(
                onTap: () => themeProvider.toggleTheme(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 52,
                  height: 28,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: isDark
                        ? const LinearGradient(colors: [
                      Color(0xFF6C63FF),
                      Color(0xFF9B59B6),
                    ])
                        : LinearGradient(colors: [
                      Colors.grey.shade400,
                      Colors.grey.shade300,
                    ]),
                    boxShadow: [
                      BoxShadow(
                        color: isDark
                            ? const Color(0xFF6C63FF).withOpacity(0.35)
                            : Colors.black.withOpacity(0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    alignment: isDark
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      width: 22,
                      height: 22,
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
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Subtitle ───────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              "Organize your thoughts ✨",
              style: TextStyle(fontSize: 18, color: primaryText),
            ),
          ),

          // ── Folder chips ───────────────────────────────────────────────────
          SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ...folders.keys.map((folder) {
                  final isSelected = folder == selectedFolder;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: ChoiceChip(
                      label: Text(folder),
                      selected: isSelected,
                      onSelected: (_) => setState(() {
                        selectedFolder = folder;
                        selectedDate   = null;
                      }),
                      selectedColor: chipSelected,
                      backgroundColor: chipUnselBg,
                      side: BorderSide(color: chipBorder),
                      labelStyle: TextStyle(
                        color: isSelected
                            ? (isDark ? Colors.white : Colors.black)
                            : secondaryText,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  );
                }),
                IconButton(
                  icon: Icon(Icons.add, color: primaryText),
                  onPressed: () => addFolder(isDark: isDark),
                ),
              ],
            ),
          ),

          // ── Date filter chips ──────────────────────────────────────────────
          SizedBox(
            height: 45,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: ChoiceChip(
                    label: const Text("All"),
                    selected: selectedDate == null,
                    selectedColor: chipSelected,
                    backgroundColor: chipUnselBg,
                    side: BorderSide(color: chipBorder),
                    labelStyle: TextStyle(
                      color: selectedDate == null
                          ? (isDark ? Colors.white : Colors.black)
                          : secondaryText,
                      fontWeight: selectedDate == null
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                    onSelected: (_) => setState(() => selectedDate = null),
                  ),
                ),
                ...dates.map((date) {
                  final isSelected = selectedDate == date;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: ChoiceChip(
                      label: Text(date),
                      selected: isSelected,
                      selectedColor: chipSelected,
                      backgroundColor: chipUnselBg,
                      side: BorderSide(color: chipBorder),
                      labelStyle: TextStyle(
                        color: isSelected
                            ? (isDark ? Colors.white : Colors.black)
                            : secondaryText,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                      onSelected: (_) =>
                          setState(() => selectedDate = date),
                    ),
                  );
                }),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ── Notes list ─────────────────────────────────────────────────────
          Expanded(
            child: notes.isEmpty
                ? Center(
              child: Text(
                "No notes yet",
                style:
                TextStyle(color: secondaryText, fontSize: 15),
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: notes.length,
              itemBuilder: (context, index) {
                final note = notes[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: borderColor),
                    boxShadow: [
                      BoxShadow(
                        color: isDark
                            ? Colors.black.withOpacity(0.3)
                            : Colors.black12,
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Content
                      if (note["type"] == "image")
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            note["file"] as File,
                            height: 150,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        )
                      else
                        Text(
                          note["text"] as String,
                          style: TextStyle(
                              color: primaryText, fontSize: 14),
                        ),

                      const SizedBox(height: 8),

                      // Footer
                      Row(
                        mainAxisAlignment:
                        MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "${formatDate(note["date"] as DateTime)} • ${note["time"]}",
                            style: TextStyle(
                                color: secondaryText, fontSize: 12),
                          ),
                          PopupMenuButton<String>(
                            color: cardColor,
                            icon: Icon(Icons.more_vert,
                                color: secondaryText, size: 20),
                            onSelected: (value) {
                              final realIndex =
                              allNotes.indexOf(note);
                              if (realIndex == -1) return;
                              if (value == "edit" &&
                                  note["type"] == "text") {
                                editNote(realIndex, isDark: isDark);
                              } else if (value == "delete") {
                                deleteNote(realIndex);
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: "edit",
                                child: Text("Edit",
                                    style: TextStyle(
                                        color: primaryText)),
                              ),
                              PopupMenuItem(
                                value: "delete",
                                child: Text(
                                  "Delete",
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.redAccent
                                        : Colors.red,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showAddNoteDialog(isDark: isDark),
        backgroundColor:
        isDark ? const Color(0xFF2C2C4E) : notesYellow,
        foregroundColor: isDark ? Colors.white : Colors.black,
        child: const Icon(Icons.add),
      ),
    );
  }
}
