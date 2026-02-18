import 'package:flutter/material.dart';
import 'ArchiveStorage.dart';
import 'SavedItemStorage.dart';
import 'SendDailyMessage.dart';

class SelectArchiveFolderScreen extends StatefulWidget {
  final DailyMessage message;

  const SelectArchiveFolderScreen({
    Key? key,
    required this.message,
  }) : super(key: key);

  @override
  State<SelectArchiveFolderScreen> createState() => _SelectArchiveFolderScreenState();
}

class _SelectArchiveFolderScreenState extends State<SelectArchiveFolderScreen> {
  List<ArchiveData> _archives = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadArchives();
  }

  Future<void> _loadArchives() async {
    await ArchiveStorage.loadFromStorage();
    if (mounted) {
      setState(() {
        _archives = ArchiveStorage.archives;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveToArchive(ArchiveData archive) async {
    // Save the message to the selected archive
    await SavedItemStorage.saveItem(archive.id, widget.message);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved to ${archive.name}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );

      // Close the selection screen
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black, size: 28),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text(
          'Save to Archive',
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(
        child: CircularProgressIndicator(
          color: Colors.cyan,
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _archives.length,
        itemBuilder: (context, index) {
          final archive = _archives[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GestureDetector(
              onTap: () => _saveToArchive(archive),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.cyan.withOpacity(0.3),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.cyan.withOpacity(0.1),
                      blurRadius: 8,
                      spreadRadius: 1,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.cyan.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.folder,
                        color: Colors.cyan,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            archive.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          if (archive.description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              archive.description,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.grey[400],
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}