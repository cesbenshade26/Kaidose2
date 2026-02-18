import 'package:flutter/material.dart';
import 'CreateArchive.dart';
import 'ArchiveStorage.dart';
import 'InsideArchive.dart';

class ArchivesView extends StatefulWidget {
  const ArchivesView({Key? key}) : super(key: key);

  @override
  State<ArchivesView> createState() => _ArchivesViewState();
}

class _ArchivesViewState extends State<ArchivesView> {
  List<ArchiveData> _customArchives = [];
  VoidCallback? _archiveListener;

  @override
  void initState() {
    super.initState();
    _loadArchives();

    _archiveListener = () {
      if (mounted) {
        setState(() {
          _customArchives = ArchiveStorage.archives;
        });
      }
    };

    ArchiveStorage.addListener(_archiveListener!);
  }

  @override
  void dispose() {
    if (_archiveListener != null) {
      ArchiveStorage.removeListener(_archiveListener!);
    }
    super.dispose();
  }

  Future<void> _loadArchives() async {
    await ArchiveStorage.loadFromStorage();
    if (mounted) {
      setState(() {
        _customArchives = ArchiveStorage.archives;
      });
    }
  }

  Widget _buildArchiveWidget(ArchiveData archive) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => InsideArchiveScreen(archive: archive),
            ),
          );
        },
        child: Container(
          width: double.infinity,
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
              // Folder icon
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.cyan.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.folder,
                  color: Colors.cyan,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              // Text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      archive.name,
                      style: TextStyle(
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
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              // Arrow icon
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
  }
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with title and add button
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Archives Folders:',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CreateArchiveScreen(),
                      ),
                    ).then((_) {
                      // Refresh archives when returning
                      if (mounted) {
                        _loadArchives();
                      }
                    });
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.cyan,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.cyan.withOpacity(0.3),
                          blurRadius: 8,
                          spreadRadius: 1,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.add,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Archives list - all archives treated equally
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: _customArchives.map((archive) => _buildArchiveWidget(archive)).toList(),
            ),
          ),
        ],
      ),
    );
  }
}