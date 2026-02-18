import 'package:flutter/material.dart';
import 'dart:io';
import 'ArchiveStorage.dart';
import 'SavedItemStorage.dart';
import 'SendDailyMessage.dart';
import 'SavedItemViewer.dart';

class InsideArchiveScreen extends StatefulWidget {
  final ArchiveData archive;

  const InsideArchiveScreen({
    Key? key,
    required this.archive,
  }) : super(key: key);

  @override
  State<InsideArchiveScreen> createState() => _InsideArchiveScreenState();
}

class _InsideArchiveScreenState extends State<InsideArchiveScreen> {
  List<DailyMessage> _savedItems = [];
  bool _isLoading = true;
  VoidCallback? _savedItemsListener;

  @override
  void initState() {
    super.initState();
    _loadSavedItems();

    _savedItemsListener = () {
      if (mounted) {
        setState(() {
          _savedItems = SavedItemStorage.getSavedItems(widget.archive.id);
        });
      }
    };

    SavedItemStorage.addListener(_savedItemsListener!);
  }

  @override
  void dispose() {
    if (_savedItemsListener != null) {
      SavedItemStorage.removeListener(_savedItemsListener!);
    }
    super.dispose();
  }

  Future<void> _loadSavedItems() async {
    await SavedItemStorage.loadItemsForArchive(widget.archive.id);
    if (mounted) {
      setState(() {
        _savedItems = SavedItemStorage.getSavedItems(widget.archive.id);
        _isLoading = false;
      });
    }
  }

  Widget _buildGridItem(DailyMessage message, int index) {
    final hasImage = message.imagePath != null && message.imagePath!.isNotEmpty;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SavedItemViewer(
              items: _savedItems,
              initialIndex: index,
            ),
          ),
        );
      },
      child: hasImage
          ? Image.file(
        File(message.imagePath!),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: Colors.grey[200],
            child: Icon(
              Icons.broken_image,
              color: Colors.grey[400],
              size: 40,
            ),
          );
        },
      )
          : Container(
        color: Colors.grey[100],
        alignment: Alignment.center,
        padding: const EdgeInsets.all(8),
        child: Text(
          message.text ?? '',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 12,
            height: 1.3,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 8,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black, size: 28),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: Text(
          widget.archive.name,
          style: const TextStyle(
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
          : _savedItems.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bookmark_border,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No Saved Items',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Save messages from your dailies to see them here',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      )
          : GridView.builder(
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 0,
          mainAxisSpacing: 0,
          childAspectRatio: 1,
        ),
        itemCount: _savedItems.length,
        itemBuilder: (context, index) {
          return _buildGridItem(_savedItems[index], index);
        },
      ),
    );
  }
}