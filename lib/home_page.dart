import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hawa_v1/login_page.dart';
import 'package:hawa_v1/profile_page.dart';
import 'half_circle_painter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'about_us.dart';
import 'contact_us.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart' as perm;
import 'package:logger/logger.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:telephony/telephony.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter/services.dart';
import 'package:hawa_v1/staff_login.dart';
import 'package:location/location.dart';

class HomePage extends StatefulWidget {
  final String fullName;
  final String userId;
  final bool isAuthenticated;

  HomePage({required this.fullName, required this.userId, this.isAuthenticated = false});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  double _glowRadius = 10.0;
  late Timer _timer;
  List<bool> _buttonStates = [false, false, false, false];
  String _emergencyNumber = "";
  final Logger logger = Logger(); // Initialize the logger
  late CameraController _cameraController;
  late Future<void> _initializeControllerFuture;
  final Telephony telephony = Telephony.instance;
  bool _emergencyMessageSent = false;
  late StreamSubscription<GyroscopeEvent> _gyroscopeSubscription;
  bool _isAuthenticated = false;
  Completer<void>? _popupCompleter;

  static const platform = MethodChannel('com.example.tesr/location');

  @override
  void initState() {
    super.initState();
    _isAuthenticated = widget.isAuthenticated;
    _startGlowAnimation();
    _fetchEmergencyNumber();
    _initializeCamera();
    _startShakeDetection(); // Start shake detection when the home page is opened
  }

  @override
  void dispose() {
    _timer.cancel();
    _gyroscopeSubscription.cancel();
    _cameraController.dispose();
    super.dispose();
  }

  void _toggleButtonState(int index) {
    setState(() {
      _buttonStates[index] = !_buttonStates[index];
    });
  }

  void _startGlowAnimation() {
    _timer = Timer.periodic(Duration(milliseconds: 1000), (timer) {
      setState(() {
        _glowRadius = _glowRadius == 10.0 ? 15.0 : 10.0;
      });
    });
  }

  String getFirstName(String fullName) {
    return fullName.split(' ')[0];
  }

  void _fetchEmergencyNumber() async {
    logger.d('Fetching emergency contact number for user ID: ${widget.userId}');
    try {
      DocumentSnapshot documentSnapshot = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();
      if (documentSnapshot.exists) {
        logger.d('Document exists for user ID: ${widget.userId}');
        var contactNumber = documentSnapshot['contactNumber'];
        if (contactNumber != null && contactNumber is String && contactNumber.isNotEmpty) {
          setState(() {
            _emergencyNumber = contactNumber.startsWith('+') ? contactNumber : '+$contactNumber';
          });
          logger.d('Fetched emergency number: $_emergencyNumber');
        } else {
          logger.w('Contact number is null or empty');
        }
      } else {
        logger.w('Document does not exist for user ID: ${widget.userId}');
      }
    } catch (e) {
      logger.e('Error fetching emergency contact: $e');
    }
  }

  Future<void> _showLoginRequiredDialog() async {
    _popupCompleter = Completer<void>();
    await showDialog<void>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Feature Locked'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('This feature is locked.'),
                Text('Please log in or sign up to access it.'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Login'),
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (context) => LoginPage())).then((_) {
                  if (!_popupCompleter!.isCompleted) {
                    _popupCompleter!.complete();
                  }
                });
              },
            ),
            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
                if (!_popupCompleter!.isCompleted) {
                  _popupCompleter!.complete();
                }
              },
            ),
          ],
        );
      },
    );
    await _popupCompleter!.future;
  }

  Future<void> _initiateCall() async {
    if (!_isAuthenticated) {
      await _showLoginRequiredDialog();
      return;
    }

    if (_emergencyNumber.isNotEmpty) {
      final Uri url = Uri(scheme: 'tel', path: _emergencyNumber);
      logger.d('Attempting to launch $url');
      var status = await perm.Permission.phone.status;
      if (status.isDenied || status.isRestricted || status.isPermanentlyDenied) {
        logger.d('Phone permission not granted. Requesting permission.');
        status = await perm.Permission.phone.request();
      }
      if (status.isGranted) {
        logger.d('Phone permission granted.');
        if (await canLaunchUrl(url)) {
          await launchUrl(url);
          logger.d('Launched $url successfully.');
        } else {
          logger.e('Could not launch $url');
        }
      } else {
        logger.w('Phone call permission not granted.');
      }
    } else {
      logger.w('Emergency number is empty.');
    }
  }

  void _initializeCamera() async {
    final cameras = await availableCameras();
    final firstCamera = cameras.first;
    _cameraController = CameraController(firstCamera, ResolutionPreset.high);
    _initializeControllerFuture = _cameraController.initialize();
  }

  Future<void> _takePicture() async {
    if (!_isAuthenticated) {
      await _showLoginRequiredDialog();
      return;
    }

    try {
      await _initializeControllerFuture;
      final image = await _cameraController.takePicture();
      final directory = await getApplicationDocumentsDirectory();
      final imagePath = path.join(directory.path, '${DateTime.now()}.png');
      await image.saveTo(imagePath);
      logger.d('Picture saved to $imagePath');
      final imageUrl = await _uploadImageToCloudStorage(imagePath);
      logger.d('Image uploaded to $imageUrl');
      await _sendSMSWithPictureAndLocation(imageUrl);
    } catch (e) {
      logger.e('Error taking picture: $e');
    }
  }

  Future<String> _uploadImageToCloudStorage(String imagePath) async {
    File file = File(imagePath);
    String fileName = path.basename(file.path);
    Reference storageReference = FirebaseStorage.instance.ref().child('images/$fileName');
    UploadTask uploadTask = storageReference.putFile(file);
    await uploadTask;
    String returnURL = await storageReference.getDownloadURL();
    return returnURL;
  }

  Future<void> _sendSMSWithPictureAndLocation(String imageUrl) async {
    if (!_isAuthenticated) {
      await _showLoginRequiredDialog();
      return;
    }

    bool? permissionsGranted = await telephony.requestPhoneAndSmsPermissions;
    if (permissionsGranted ?? false) {
      Location location = new Location();

      bool _serviceEnabled;
      PermissionStatus _permissionGranted;
      LocationData _locationData;

      _serviceEnabled = await location.serviceEnabled();
      if (!_serviceEnabled) {
        _serviceEnabled = await location.requestService();
        if (!_serviceEnabled) {
          return;
        }
      }

      _permissionGranted = await location.hasPermission();
      if (_permissionGranted == PermissionStatus.denied) {
        _permissionGranted = await location.requestPermission();
        if (_permissionGranted != PermissionStatus.granted) {
          return;
        }
      }

      _locationData = await location.getLocation();

      telephony.sendSms(
        to: _emergencyNumber,
        message: 'Emergency! Here is the picture: $imageUrl\nLocation: https://www.google.com/maps/search/?api=1&query=${_locationData.latitude},${_locationData.longitude}',
      ).then((_) {
        logger.d('SMS sent successfully with image URL and location: $imageUrl');
      }).catchError((error) {
        logger.e('Failed to send SMS: $error');
      });
    } else {
      logger.w('SMS permission not granted.');
    }
  }

  Future<void> _callEmergencyNumber() async {
    final Uri emergencyUri = Uri(scheme: 'tel', path: '999');
    if (await canLaunchUrl(emergencyUri)) {
      await launchUrl(emergencyUri);
    } else {
      logger.e('Could not launch $emergencyUri');
    }
  }

  void _startShakeDetection() {
    _gyroscopeSubscription = gyroscopeEvents.listen((GyroscopeEvent event) {
      final double shakeThreshold = 2.5; // Adjust this value based on your requirements
      if (!_emergencyMessageSent && (event.x.abs() > shakeThreshold || event.y.abs() > shakeThreshold || event.z.abs() > shakeThreshold)) {
        _sendEmergencyMessage();
        _emergencyMessageSent = true;
      }
    });
  }

  void _sendEmergencyMessage() async {
    if (!_isAuthenticated) {
      await _showLoginRequiredDialog();
      return;
    }

    bool? permissionsGranted = await telephony.requestPhoneAndSmsPermissions;
    if (permissionsGranted ?? false) {
      telephony.sendSms(
        to: _emergencyNumber,
        message: "Emergency! This is Hawa Emergency Services. A large movement was detected from " + getFirstName(widget.fullName) +", indicating a potential emergency. Please contact me immediately.",
      ).then((_) {
        logger.d('Emergency SMS sent successfully.');
      }).catchError((error) {
        logger.e('Failed to send emergency SMS: $error');
      });
    } else {
      logger.w('SMS permission not granted.');
    }
  }

  @override
  Widget build(BuildContext context) {
    String firstName = getFirstName(widget.fullName);

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 10, 38, 39),
      appBar: AppBar(
        backgroundColor: Colors.teal[700],
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: Image.asset(
          'assets/images/hawa_name.png',
          height: 200,
          width: 200,
        ),
      ),
      drawer: AppDrawer(),
      body: Builder(
        builder: (context) => Stack(
          children: [
            CustomPaint(
              size: Size(MediaQuery.of(context).size.width, 250),
              painter: HalfCirclePainter(Colors.teal[700]!),
            ),
            Row(
              children: [
                Padding(
                  padding: EdgeInsets.only(left: 20),
                  child: GestureDetector(
                    onTap: () {
                      Scaffold.of(context).openDrawer();
                    },
                    child: Icon(Icons.menu_rounded, color: Color.fromARGB(255, 10, 38, 39), size: 40),
                  ),
                ),
                Spacer(),
                Padding(
                  padding: EdgeInsets.only(right: 20),
                  child: IconButton(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => ProfilePage(userId: widget.userId, isAuthenticated: widget.isAuthenticated,)));
                    },
                    icon: Icon(Icons.account_circle_rounded, size: 40, color: Color.fromARGB(255, 10, 38, 39)),
                  ),
                ),
              ],
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                SizedBox(height: 70), // Adjust the height accordingly
                Center(
                  child: AnimatedContainer(
                    duration: Duration(milliseconds: 1000),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color.fromARGB(255, 80, 190, 179).withOpacity(0.6),
                          spreadRadius: _glowRadius,
                          blurRadius: _glowRadius,
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: () async {
                        if (!_isAuthenticated) {
                          await _showLoginRequiredDialog();
                        } else {
                          // SOS button action
                        }
                      },
                      child: Text(
                        'S.O.S',
                        style: GoogleFonts.quicksand(
                          textStyle: TextStyle(
                            color: Colors.teal[900], 
                            fontWeight: FontWeight.w900,
                            fontSize: 60, 
                          ),
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        shape: CircleBorder(),
                        backgroundColor: Colors.teal[200],
                        padding: EdgeInsets.all(83),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 60),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Center(
                      child: Text(
                        "Welcome, $firstName",
                        style: GoogleFonts.quicksand(
                          textStyle: TextStyle(
                            fontSize: 30,
                            color: const Color.fromARGB(255, 255, 255, 255),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 60),
                    Wrap(
                      spacing: 15,
                      runSpacing: 15,
                      children: [
                        ElevatedButton(
                        onPressed: () => _initiateCall(),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.phone, size: 48),
                            SizedBox(height: 4), // Add some space between the icon and the text
                            Text(
                              "Call\nEmergency\nContact",
                              style: TextStyle(fontSize: 16),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _buttonStates[0] ? Color.fromARGB(255, 255, 255, 255) : Color.fromARGB(255, 10, 38, 39),
                          foregroundColor: _buttonStates[0] ? Color.fromARGB(255, 10, 38, 39) : Color.fromARGB(255, 255, 255, 255),
                          minimumSize: Size(100, 150),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(color: Color.fromARGB(255, 255, 255, 255)),
                          ),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () => _takePicture(),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.camera_alt, size: 48),
                            SizedBox(height: 4), // Add some space between the icon and the text
                            Text(
                              "Take\nPicture",
                              style: TextStyle(fontSize: 16),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _buttonStates[1] ? Color.fromARGB(255, 255, 255, 255) : Color.fromARGB(255, 10, 38, 39),
                          foregroundColor: _buttonStates[1] ? Color.fromARGB(255, 10, 38, 39) : Color.fromARGB(255, 255, 255, 255),
                          minimumSize: Size(128, 150),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(color: Color.fromARGB(255, 255, 255, 255)),
                          ),
                        ),
                      ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class AppDrawer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Color.fromARGB(255, 45, 45, 45),
      child: ListView(
        children: <Widget>[
          SizedBox(height: 30,),
          ListTile(
            contentPadding: EdgeInsets.only(left: 230),
            leading: Icon(Icons.close_rounded, size: 30, color: Color.fromRGBO(255, 255, 255, 1),),
            onTap: () {
              Navigator.pop(context);  
            },
          ),
          SizedBox(height: 100,),
          ListTile(
            contentPadding: EdgeInsets.only(left: 50),
            title: Text('About Us', style: TextStyle(fontSize: 20, color: Color.fromRGBO(255, 255, 255, 1), fontWeight: FontWeight.w500),),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => AboutUsPage()));
            },
          ),
          SizedBox(height: 20,),
          ListTile(
            contentPadding: EdgeInsets.only(left: 50),
            title: Text('Contact Us', style: TextStyle(fontSize: 20, color: Color.fromRGBO(255, 255, 255, 1), fontWeight: FontWeight.w500),),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => ContactUsPage()));
            },
          ),
          SizedBox(height: 300,),
          ListTile(
            leading: Icon(Icons.logout_rounded, size: 25, color: Color.fromRGBO(255, 255, 255, 1),),
            contentPadding: EdgeInsets.only(left: 50),
            title: Text('Logout', style: TextStyle(fontSize: 20, color: Color.fromRGBO(255, 255, 255, 1),),),
            onTap: () {
              // Sign out the user
              FirebaseAuth.instance.signOut().then((_) {
                // Navigate to HomePage with limited functionalities
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => HomePage(isAuthenticated: false, fullName: 'Guest', userId: '',)),
                  (route) => false, // Remove all previous routes
                );
              });
            },
          ),
          
        ],
      ),
    );
  }
}
