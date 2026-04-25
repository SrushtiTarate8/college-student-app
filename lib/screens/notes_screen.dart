import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

// ✅ added color
const Color notesYellow = Color(0xFFFFF59D);

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  Map<String, List<Map<String, dynamic>>> folders = {"General": []};

  String selectedFolder = "General";
  String? selectedDate;

  String formatDate(DateTime date) {
    return "${date.day}/${date.month}/${date.year}";
  }

  void addNote(String text) {
    setState(() {
      folders[selectedFolder]!.add({
        "text": text,
        "type": "text",
        "time": TimeOfDay.now().format(context),
        "date": DateTime.now(),
      });
    });
  }

  void deleteNote(int index) {
    setState(() {
      folders[selectedFolder]!.removeAt(index);
    });
  }

  void editNote(int index) {
    TextEditingController controller = TextEditingController(
      text: folders[selectedFolder]![index]["text"],
    );

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Edit Note"),
        content: TextField(controller: controller),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                folders[selectedFolder]![index]["text"] = controller.text;
                folders[selectedFolder]![index]["date"] = DateTime.now();
              });
              Navigator.pop(context);
            },
            child: const Text("Update"),
          ),
        ],
      ),
    );
  }

  Future<void> pickImage() async {
    final picker = ImagePicker();
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
    FilePickerResult? result = await FilePicker.platform.pickFiles();

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
    }
  }

  void addFolder() {
    TextEditingController controller = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "New Folder",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: "Enter folder name",
            border: OutlineInputBorder(),
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.black, // ✅ make text black
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: notesYellow, // ✅ changed
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            onPressed: () {
              if (controller.text.isNotEmpty) {
                setState(() {
                  folders[controller.text] = [];
                  selectedFolder = controller.text;
                });
              }
              Navigator.pop(context);
            },
            child: const Text("Create"),
          ),
        ],
      ),
    );
  }

  void showAddNoteDialog() {
    TextEditingController controller = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Add Note"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: "Write something...",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.image),
            onPressed: () {
              Navigator.pop(context);
              pickImage();
            },
          ),
          IconButton(
            icon: const Icon(Icons.attach_file),
            onPressed: () {
              Navigator.pop(context);
              pickFile();
            },
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.black, // ✅ add this
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

  @override
  Widget build(BuildContext context) {
    final allNotes = folders[selectedFolder]!;

    final dates = allNotes
        .map((note) => formatDate(note["date"]))
        .toSet()
        .toList();

    final notes = selectedDate == null
        ? allNotes
        : allNotes
        .where((note) => formatDate(note["date"]) == selectedDate)
        .toList();

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("My Notes"),
        backgroundColor: notesYellow, // ✅ changed
        foregroundColor: Colors.black, // ✅ for visibility
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              "Organize your thoughts ✨",
              style: TextStyle(fontSize: 18),
            ),
          ),

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
                      onSelected: (_) {
                        setState(() {
                          selectedFolder = folder;
                          selectedDate = null;
                        });
                      },
                      selectedColor: notesYellow, // ✅ changed
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.black : Colors.black,
                      ),
                    ),
                  );
                }),
                IconButton(icon: const Icon(Icons.add), onPressed: addFolder),
              ],
            ),
          ),

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
                    selectedColor: notesYellow, // ✅ add this
                    labelStyle: TextStyle(
                      color: selectedDate == null ? Colors.black : Colors.black,
                    ),
                    onSelected: (_) {
                      setState(() {
                        selectedDate = null;
                      });
                    },
                  ),
                ),
                ...dates.map((date) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: ChoiceChip(
                      label: Text(date),
                      selected: selectedDate == date,
                      selectedColor: notesYellow, // ✅ THIS LINE ADDED
                      labelStyle: TextStyle(
                        color: selectedDate == date
                            ? Colors.black
                            : Colors.black,
                      ),
                      onSelected: (_) {
                        setState(() {
                          selectedDate = date;
                        });
                      },
                    ),
                  );
                }),
              ],
            ),
          ),

          const SizedBox(height: 10),

          Expanded(
            child: notes.isEmpty
                ? const Center(child: Text("No notes yet"))
                : ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: notes.length,
              itemBuilder: (context, index) {
                final note = notes[index];

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 6),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      note["type"] == "image"
                          ? Image.file(note["file"], height: 150)
                          : Text(note["text"]),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "${formatDate(note["date"])} • ${note["time"]}",
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                          PopupMenuButton(
                            onSelected: (value) {
                              if (value == "edit" &&
                                  note["type"] == "text") {
                                editNote(index);
                              } else if (value == "delete") {
                                deleteNote(index);
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: "edit",
                                child: Text("Edit"),
                              ),
                              const PopupMenuItem(
                                value: "delete",
                                child: Text("Delete"),
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
        onPressed: showAddNoteDialog,
        backgroundColor: notesYellow, // ✅ changed
        foregroundColor: Colors.black,
        child: const Icon(Icons.add),
      ),
    );
  }
}