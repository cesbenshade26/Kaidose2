import 'package:flutter/material.dart';
import 'Home.dart';

class InterestDetector extends StatefulWidget {
  final VoidCallback? onComplete;
  const InterestDetector({Key? key, this.onComplete}) : super(key: key);

  @override
  _InterestDetectorState createState() => _InterestDetectorState();
}

class _InterestDetectorState extends State<InterestDetector>
    with TickerProviderStateMixin {
  late AnimationController _controller1;
  late AnimationController _controller2;
  late AnimationController _controller3;
  late AnimationController _controller4;
  late AnimationController _controller5;
  late AnimationController _controller6;
  late AnimationController _controller7;
  late AnimationController _deleteController1;
  late AnimationController _deleteController2;
  late AnimationController _cursorController;

  String _displayedText1 = "";
  String _displayedText2 = "";
  String _displayedText3 = "";
  String _displayedText4 = "";
  String _displayedText5 = "";
  String _displayedText6 = "";
  String _displayedText7 = "";
  bool _showCursor1 = false;
  bool _showCursor2 = false;
  bool _showCursor3 = false;
  bool _showCursor4 = false;
  bool _showCursor5 = false;
  bool _showCursor6 = false;
  bool _showCursor7 = false;
  bool _showInterestsScreen = false;
  bool _showPeopleScreen = false;

  final String _fullText1 = "Welcome to Kaidose";
  final String _fullText2 = "We're glad you're here";
  final String _fullText3 = "Let us get to know you";
  final String _fullText4 = "Any interests you can tell us?";
  final String _fullText5 = "It's ok if not";
  final String _fullText6 = "Find some People!";
  final String _fullText7 = "You can always find them later";

  final TextEditingController _interestsSearchController = TextEditingController();
  final TextEditingController _peopleSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();

    _controller1 = AnimationController(
      duration: Duration(milliseconds: _fullText1.length * 80),
      vsync: this,
    );

    _controller2 = AnimationController(
      duration: Duration(milliseconds: _fullText2.length * 80),
      vsync: this,
    );

    _controller3 = AnimationController(
      duration: Duration(milliseconds: _fullText3.length * 80),
      vsync: this,
    );

    _controller4 = AnimationController(
      duration: Duration(milliseconds: _fullText4.length * 80),
      vsync: this,
    );

    _controller5 = AnimationController(
      duration: Duration(milliseconds: _fullText5.length * 80),
      vsync: this,
    );

    _controller6 = AnimationController(
      duration: Duration(milliseconds: _fullText6.length * 80),
      vsync: this,
    );

    _controller7 = AnimationController(
      duration: Duration(milliseconds: _fullText7.length * 80),
      vsync: this,
    );

    // Delete controller for first two texts
    _deleteController1 = AnimationController(
      duration: Duration(milliseconds: (_fullText1.length + _fullText2.length) * 40),
      vsync: this,
    );

    // Delete controller for third text
    _deleteController2 = AnimationController(
      duration: Duration(milliseconds: _fullText3.length * 40),
      vsync: this,
    );

    _cursorController = AnimationController(
      duration: Duration(milliseconds: 500),
      vsync: this,
    );

    _cursorController.repeat(reverse: true);
    _startFirstAnimation();
  }

  void _startFirstAnimation() {
    setState(() {
      _showCursor1 = true;
    });

    _controller1.addListener(_updateText1);
    _controller1.forward().then((_) {
      setState(() {
        _showCursor1 = false;
      });
      Future.delayed(Duration(milliseconds: 300), () {
        _startSecondAnimation();
      });
    });
  }

  void _updateText1() {
    setState(() {
      int currentLength = (_controller1.value * _fullText1.length).floor();
      _displayedText1 = _fullText1.substring(0, currentLength);
    });
  }

  void _startSecondAnimation() {
    setState(() {
      _showCursor2 = true;
    });

    _controller2.addListener(_updateText2);
    _controller2.forward().then((_) {
      setState(() {
        _showCursor2 = false;
      });
      Future.delayed(Duration(milliseconds: 1000), () {
        _startFirstDeleteAnimation();
      });
    });
  }

  void _updateText2() {
    setState(() {
      int currentLength = (_controller2.value * _fullText2.length).floor();
      _displayedText2 = _fullText2.substring(0, currentLength);
    });
  }

  void _startFirstDeleteAnimation() {
    final totalLength = _fullText1.length + _fullText2.length;

    _deleteController1.addListener(() {
      setState(() {
        int deletedChars = (_deleteController1.value * totalLength).floor();

        if (deletedChars <= _fullText2.length) {
          _displayedText2 = _fullText2.substring(0, _fullText2.length - deletedChars);
        } else {
          _displayedText2 = "";
          int firstTextDeleted = deletedChars - _fullText2.length;
          _displayedText1 = _fullText1.substring(0, _fullText1.length - firstTextDeleted);
        }
      });
    });

    _deleteController1.forward().then((_) {
      setState(() {
        _displayedText1 = "";
        _displayedText2 = "";
      });
      _startThirdAnimation();
    });
  }

  void _startThirdAnimation() {
    setState(() {
      _showCursor3 = true;
    });

    _controller3.addListener(_updateText3);
    _controller3.forward().then((_) {
      setState(() {
        _showCursor3 = false;
      });
      Future.delayed(Duration(milliseconds: 1000), () {
        _startThirdDeleteAnimation();
      });
    });
  }

  void _updateText3() {
    setState(() {
      int currentLength = (_controller3.value * _fullText3.length).floor();
      _displayedText3 = _fullText3.substring(0, currentLength);
    });
  }

  void _startThirdDeleteAnimation() {
    _deleteController2.addListener(() {
      setState(() {
        int deletedChars = (_deleteController2.value * _fullText3.length).floor();
        _displayedText3 = _fullText3.substring(0, _fullText3.length - deletedChars);
      });
    });

    _deleteController2.forward().then((_) {
      setState(() {
        _displayedText3 = "";
        _showInterestsScreen = true;
      });
      _startFourthAnimation();
    });
  }

  void _startFourthAnimation() {
    setState(() {
      _showCursor4 = true;
    });

    _controller4.addListener(_updateText4);
    _controller4.forward().then((_) {
      setState(() {
        _showCursor4 = false;
      });
      Future.delayed(Duration(milliseconds: 300), () {
        _startFifthAnimation();
      });
    });
  }

  void _updateText4() {
    setState(() {
      int currentLength = (_controller4.value * _fullText4.length).floor();
      _displayedText4 = _fullText4.substring(0, currentLength);
    });
  }

  void _startFifthAnimation() {
    setState(() {
      _showCursor5 = true;
    });

    _controller5.addListener(_updateText5);
    _controller5.forward().then((_) {
      setState(() {
        _showCursor5 = false;
      });
      // Interests screen text stays permanent - no deletion
    });
  }

  void _updateText5() {
    setState(() {
      int currentLength = (_controller5.value * _fullText5.length).floor();
      _displayedText5 = _fullText5.substring(0, currentLength);
    });
  }

  void _navigateToPeopleScreen() {
    setState(() {
      _showInterestsScreen = false;
      _showPeopleScreen = true;
      _displayedText4 = "";
      _displayedText5 = "";
    });
    _startSixthAnimation();
  }

  void _startSixthAnimation() {
    setState(() {
      _showCursor6 = true;
    });

    _controller6.addListener(_updateText6);
    _controller6.forward().then((_) {
      setState(() {
        _showCursor6 = false;
      });
      Future.delayed(Duration(milliseconds: 300), () {
        _startSeventhAnimation();
      });
    });
  }

  void _updateText6() {
    setState(() {
      int currentLength = (_controller6.value * _fullText6.length).floor();
      _displayedText6 = _fullText6.substring(0, currentLength);
    });
  }

  void _startSeventhAnimation() {
    setState(() {
      _showCursor7 = true;
    });

    _controller7.addListener(_updateText7);
    _controller7.forward().then((_) {
      setState(() {
        _showCursor7 = false;
      });
      // People screen text stays permanent - no deletion
    });
  }

  void _updateText7() {
    setState(() {
      int currentLength = (_controller7.value * _fullText7.length).floor();
      _displayedText7 = _fullText7.substring(0, currentLength);
    });
  }

  void _navigateToMainScreen() {
    if (widget.onComplete != null) {
      widget.onComplete!();
    }
  }

  @override
  void dispose() {
    _controller1.removeListener(_updateText1);
    _controller2.removeListener(_updateText2);
    _controller3.removeListener(_updateText3);
    _controller4.removeListener(_updateText4);
    _controller5.removeListener(_updateText5);
    _controller6.removeListener(_updateText6);
    _controller7.removeListener(_updateText7);

    _controller1.dispose();
    _controller2.dispose();
    _controller3.dispose();
    _controller4.dispose();
    _controller5.dispose();
    _controller6.dispose();
    _controller7.dispose();
    _deleteController1.dispose();
    _deleteController2.dispose();
    _cursorController.dispose();
    _interestsSearchController.dispose();
    _peopleSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: (_showInterestsScreen || _showPeopleScreen) ? null : AppBar(
        title: Text(
          'Kaidose',
          style: TextStyle(
            fontFamily: 'Slackey',
            fontSize: 24,
            color: Colors.black,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: _showPeopleScreen
          ? _buildPeopleScreen()
          : _showInterestsScreen
          ? _buildInterestsScreen()
          : _buildWelcomeScreen(),
    );
  }

  Widget _buildWelcomeScreen() {
    return Center(
      child: Padding(
        padding: EdgeInsets.only(bottom: 200),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_displayedText1.isNotEmpty || _displayedText2.isNotEmpty)
              Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          _displayedText1,
                          style: TextStyle(
                            fontFamily: 'Slackey',
                            fontSize: 32,
                            color: Colors.black,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      if (_showCursor1)
                        AnimatedBuilder(
                          animation: _cursorController,
                          builder: (context, child) {
                            return Opacity(
                              opacity: _cursorController.value,
                              child: Text(
                                '|',
                                style: TextStyle(
                                  fontFamily: 'Slackey',
                                  fontSize: 32,
                                  color: Colors.black,
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                  SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          _displayedText2,
                          style: TextStyle(
                            fontFamily: 'Slackey',
                            fontSize: 24,
                            color: Colors.black,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      if (_showCursor2)
                        AnimatedBuilder(
                          animation: _cursorController,
                          builder: (context, child) {
                            return Opacity(
                              opacity: _cursorController.value,
                              child: Text(
                                '|',
                                style: TextStyle(
                                  fontFamily: 'Slackey',
                                  fontSize: 24,
                                  color: Colors.black,
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ],
              ),

            if (_displayedText3.isNotEmpty)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      _displayedText3,
                      style: TextStyle(
                        fontFamily: 'Slackey',
                        fontSize: 28,
                        color: Colors.black,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (_showCursor3)
                    AnimatedBuilder(
                      animation: _cursorController,
                      builder: (context, child) {
                        return Opacity(
                          opacity: _cursorController.value,
                          child: Text(
                            '|',
                            style: TextStyle(
                              fontFamily: 'Slackey',
                              fontSize: 28,
                              color: Colors.black,
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInterestsScreen() {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(20, 60, 20, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      _displayedText4,
                      style: TextStyle(
                        fontFamily: 'Slackey',
                        fontSize: 28,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  if (_showCursor4)
                    AnimatedBuilder(
                      animation: _cursorController,
                      builder: (context, child) {
                        return Opacity(
                          opacity: _cursorController.value,
                          child: Text(
                            '|',
                            style: TextStyle(
                              fontFamily: 'Slackey',
                              fontSize: 28,
                              color: Colors.black,
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
              SizedBox(height: 15),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      _displayedText5,
                      style: TextStyle(
                        fontFamily: 'Slackey',
                        fontSize: 20,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                  if (_showCursor5)
                    AnimatedBuilder(
                      animation: _cursorController,
                      builder: (context, child) {
                        return Opacity(
                          opacity: _cursorController.value,
                          child: Text(
                            '|',
                            style: TextStyle(
                              fontFamily: 'Slackey',
                              fontSize: 20,
                              color: Colors.grey[600],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ],
          ),
        ),

        Container(
          height: 1,
          color: Colors.grey[300],
          margin: EdgeInsets.symmetric(horizontal: 20),
        ),

        Expanded(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: TextField(
                    controller: _interestsSearchController,
                    decoration: InputDecoration(
                      hintText: 'Search interests...',
                      hintStyle: TextStyle(
                        fontFamily: 'Slackey',
                        fontSize: 16,
                        color: Colors.grey[500],
                      ),
                      prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                    ),
                    style: TextStyle(
                      fontFamily: 'Slackey',
                      fontSize: 16,
                      color: Colors.black,
                    ),
                  ),
                ),
                SizedBox(height: 30),
                Text(
                  'Example interests',
                  style: TextStyle(
                    fontFamily: 'Slackey',
                    fontSize: 18,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ),

        Container(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 40),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: TextButton(
                  onPressed: () {
                    _navigateToPeopleScreen();
                  },
                  child: Text(
                    'Skip for now',
                    style: TextStyle(
                      fontFamily: 'Slackey',
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              ),
              SizedBox(width: 10),
              ElevatedButton(
                onPressed: () {
                  _navigateToPeopleScreen();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  'Next',
                  style: TextStyle(
                    fontFamily: 'Slackey',
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPeopleScreen() {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(20, 60, 20, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      _displayedText6,
                      style: TextStyle(
                        fontFamily: 'Slackey',
                        fontSize: 28,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  if (_showCursor6)
                    AnimatedBuilder(
                      animation: _cursorController,
                      builder: (context, child) {
                        return Opacity(
                          opacity: _cursorController.value,
                          child: Text(
                            '|',
                            style: TextStyle(
                              fontFamily: 'Slackey',
                              fontSize: 28,
                              color: Colors.black,
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
              SizedBox(height: 15),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      _displayedText7,
                      style: TextStyle(
                        fontFamily: 'Slackey',
                        fontSize: 20,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                  if (_showCursor7)
                    AnimatedBuilder(
                      animation: _cursorController,
                      builder: (context, child) {
                        return Opacity(
                          opacity: _cursorController.value,
                          child: Text(
                            '|',
                            style: TextStyle(
                              fontFamily: 'Slackey',
                              fontSize: 20,
                              color: Colors.grey[600],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ],
          ),
        ),

        Container(
          height: 1,
          color: Colors.grey[300],
          margin: EdgeInsets.symmetric(horizontal: 20),
        ),

        Expanded(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: TextField(
                    controller: _peopleSearchController,
                    decoration: InputDecoration(
                      hintText: 'Search people...',
                      hintStyle: TextStyle(
                        fontFamily: 'Slackey',
                        fontSize: 16,
                        color: Colors.grey[500],
                      ),
                      prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                    ),
                    style: TextStyle(
                      fontFamily: 'Slackey',
                      fontSize: 16,
                      color: Colors.black,
                    ),
                  ),
                ),
                SizedBox(height: 30),
                Text(
                  'Example people',
                  style: TextStyle(
                    fontFamily: 'Slackey',
                    fontSize: 18,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ),

        Container(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 40),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: TextButton(
                  onPressed: () {
                    _navigateToMainScreen();
                  },
                  child: Text(
                    'Skip for now',
                    style: TextStyle(
                      fontFamily: 'Slackey',
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              ),
              SizedBox(width: 10),
              ElevatedButton(
                onPressed: () {
                  _navigateToMainScreen();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  'Next',
                  style: TextStyle(
                    fontFamily: 'Slackey',
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}