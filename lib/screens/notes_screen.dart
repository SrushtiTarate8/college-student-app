import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  Map<String, List<Map<String, dynamic>>> folders = {"General": []};

  String selectedFolder = "General";

  void addNote(String text) {
    final time = TimeOfDay.now().format(context);

    setState(() {
      folders[selectedFolder]!.add({
        "text": text,
        "type": "text",
        "time": time,
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
      builder: (context) {
        return AlertDialog(
          title: const Text("Edit Note"),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  setState(() {
                    folders[selectedFolder]![index]["text"] = controller.text;
                  });
                }
                Navigator.pop(context);
              },
              child: const Text("Update"),
            ),
          ],
        );
      },
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
        });
      });
    }
  }

  void addFolder() {
    TextEditingController controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("New Folder"),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: "Folder name"),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
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
        );
      },
    );
  }

  void showAddNoteDialog() {
    TextEditingController controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Add Note"),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: "Write something...",
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
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  addNote(controller.text);
                }
                Navigator.pop(context);
              },
              child: const Text("Add"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final notes = folders[selectedFolder]!;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("My Notes"),
        backgroundColor: Colors.deepPurple,
        elevation: 0,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              "Organize your thoughts ✨",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
          ),

          // 🔹 Folder Chips
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
                        });
                      },
                      selectedColor: Colors.deepPurple,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Colors.black,
                      ),
                    ),
                  );
                }),
                IconButton(icon: const Icon(Icons.add), onPressed: addFolder),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // 🔹 Notes
          Expanded(
            child: notes.isEmpty
                ? const Center(
                    child: Text(
                      "No notes yet 📝",
                      style: TextStyle(color: Colors.grey),
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
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.file(
                                      note["file"],
                                      height: 150,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : Text(
                                    note["text"],
                                    style: const TextStyle(fontSize: 16),
                                  ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  note["time"],
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
                                  itemBuilder: (context) => [
                                    if (note["type"] == "text")
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
        backgroundColor: Colors.deepPurple,
        child: const Icon(Icons.add),
      ),
    );
  }
}
