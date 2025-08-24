import 'package:flutter/material.dart';
import 'BioManager.dart';

// Bio Screen with ALL formatting options - FIXED
class BioScreen extends StatefulWidget {
  const BioScreen({Key? key}) : super(key: key);

  @override
  State<BioScreen> createState() => _BioScreenState();
}

class _BioScreenState extends State<BioScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _isBold = false;
  bool _isItalic = false;
  bool _isUnderlined = false;
  TextAlign _textAlign = TextAlign.center;
  Color _textColor = Colors.black;
  bool _isLoading = true; // Add loading state

  final List<Color> _colorOptions = [
    Colors.black, Colors.grey[700]!, Colors.blue, Colors.red,
    Colors.green, Colors.purple, Colors.orange, Colors.pink
  ];

  @override
  void initState() {
    super.initState();
    _loadBioData();
  }

  // Load bio data from BioManager
  Future<void> _loadBioData() async {
    try {
      // Ensure bio is loaded from storage first
      await BioManager.loadBioFromStorage();

      // Then update the UI with the loaded data
      if (mounted) {
        setState(() {
          _controller.text = BioManager.globalBioText ?? '';
          _isBold = BioManager.globalBold;
          _isItalic = BioManager.globalItalic;
          _isUnderlined = BioManager.globalUnderlined;
          _textAlign = BioManager.globalAlign;
          _textColor = BioManager.globalColor;
          _isLoading = false; // Set loading to false
        });
      }

      print('Bio loaded in BioScreen: "${_controller.text}"');
    } catch (e) {
      print('Error loading bio data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showConfirmDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Confirm Bio'),
        content: const Text('The entered text will be saved as your profile\'s bio'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(); // Close dialog only
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              print('Confirm pressed - saving bio: "${_controller.text}"');

              try {
                // Save the bio
                BioManager.setBio(_controller.text, _isBold, _isItalic, _isUnderlined, _textAlign, _textColor);

                // Close dialog first
                Navigator.of(dialogContext).pop();

                // Show success message
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('New Bio Set!'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 1),
                    ),
                  );

                  // Wait a brief moment for the snackbar to show, then navigate back
                  await Future.delayed(const Duration(milliseconds: 800));

                  // Navigate back to profile
                  Navigator.of(context).pop();
                }
              } catch (e) {
                print('Error saving bio: $e');
                // Close dialog even if there's an error
                Navigator.of(dialogContext).pop();

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Error saving bio'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              }
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Show loading indicator while data is being loaded
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Edit Bio'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Bio'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: Column(
        children: [
          // Formatting controls
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[100],
            child: Column(
              children: [
                // Style buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStyleButton(Icons.format_bold, _isBold, () => setState(() => _isBold = !_isBold)),
                    _buildStyleButton(Icons.format_italic, _isItalic, () => setState(() => _isItalic = !_isItalic)),
                    _buildStyleButton(Icons.format_underlined, _isUnderlined, () => setState(() => _isUnderlined = !_isUnderlined)),
                  ],
                ),
                const SizedBox(height: 16),
                // Alignment buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildAlignButton(Icons.format_align_left, TextAlign.left),
                    _buildAlignButton(Icons.format_align_center, TextAlign.center),
                    _buildAlignButton(Icons.format_align_right, TextAlign.right),
                  ],
                ),
                const SizedBox(height: 16),
                // Color options
                Wrap(
                  spacing: 8,
                  children: _colorOptions.map((color) => GestureDetector(
                    onTap: () => setState(() => _textColor = color),
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: color, shape: BoxShape.circle,
                        border: Border.all(
                          color: _textColor == color ? Colors.blue : Colors.grey,
                          width: _textColor == color ? 3 : 1,
                        ),
                      ),
                    ),
                  )).toList(),
                ),
              ],
            ),
          ),

          // Text input
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlign: _textAlign,
                style: TextStyle(
                  fontSize: 16,
                  color: _textColor,
                  fontWeight: _isBold ? FontWeight.bold : FontWeight.normal,
                  fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
                  decoration: _isUnderlined ? TextDecoration.underline : TextDecoration.none,
                ),
                decoration: const InputDecoration(
                  hintText: 'Enter your bio here...',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.all(16),
                ),
              ),
            ),
          ),

          // Save button
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _showConfirmDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Save Bio', style: TextStyle(fontSize: 18)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStyleButton(IconData icon, bool isActive, VoidCallback onPressed) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 48, height: 48,
        decoration: BoxDecoration(
          color: isActive ? Colors.blue : Colors.white,
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: isActive ? Colors.white : Colors.grey[700]),
      ),
    );
  }

  Widget _buildAlignButton(IconData icon, TextAlign alignment) {
    bool isActive = _textAlign == alignment;
    return GestureDetector(
      onTap: () => setState(() => _textAlign = alignment),
      child: Container(
        width: 48, height: 48,
        decoration: BoxDecoration(
          color: isActive ? Colors.blue : Colors.white,
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: isActive ? Colors.white : Colors.grey[700]),
      ),
    );
  }
}