import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hawa_v1/home_page.dart';
import 'package:hawa_v1/signup_page.dart';

TextEditingController emailController = TextEditingController();
TextEditingController passwordController = TextEditingController();

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String errorMessage = '';

  Future<void> signIn() async {
    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: emailController.text,
        password: passwordController.text,
      );
      User? user = userCredential.user;

      if (user != null) {
        DocumentSnapshot userData = await _firestore.collection('users').doc(user.uid).get();
        String fullName = userData['fullName'];

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => HomePage(
              fullName: fullName,
              userId: user.uid,
              isAuthenticated: true, // ensure isAuthenticated is true after login
            ),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        switch (e.code) {
          case 'user-not-found':
            errorMessage = 'No user found for that email.';
            break;
          case 'wrong-password':
            errorMessage = 'Wrong password provided for that user.';
            break;
          case 'invalid-email':
            errorMessage = 'The email address is badly formatted.';
            break;
          case 'user-disabled':
            errorMessage = 'The user account has been disabled.';
            break;
          case 'too-many-requests':
            errorMessage = 'Too many requests. Try again later.';
            break;
          case 'invalid-credential':
            errorMessage = "Incorrect email or password";
            break;
          default:
            errorMessage = 'An unknown error occurred: ${e.message}';
        }
      });
    } catch (e) {
      print("General exception: ${e.toString()}");
      setState(() {
        errorMessage = 'An error occurred. Please try again. ${e.toString()}';
      });
    }
  }

  void navigateToSignUp() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => SignUp()), // Change to sign up page later
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: const Color.fromARGB(255, 10, 38, 39),
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          leading: IconButton(
            icon: Image.asset('assets/images/backArrow.png'),
            onPressed: () {
              Navigator.pop(context, 'from_login_page');
            },
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Container(
          width: double.maxFinite,
          padding: EdgeInsets.symmetric(vertical: 10.0, horizontal: 20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 300.0,
                  child: RichText(
                    text: TextSpan(
                      children: [
                        WidgetSpan(
                          child: Padding(
                            padding: EdgeInsets.only(left: 30, bottom: 0),
                            child: Text(
                              "Login\n",
                              style: TextStyle(
                                fontFamily: 'Roboto',
                                fontWeight: FontWeight.w700,
                                fontSize: 30.0,
                                color: Color.fromRGBO(255, 255, 255, 1),
                              ),
                            ),
                          ),
                        ),
                        WidgetSpan(
                          child: Padding(
                            padding: EdgeInsets.only(left: 30, top: 0),
                            child: Text(
                              "Login to continue using the application",
                              style: TextStyle(
                                fontFamily: 'Roboto',
                                fontWeight: FontWeight.w300,
                                fontSize: 14.0,
                                color: Color.fromRGBO(255, 255, 255, 1),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.left,
                  ),
                ),
              ),
              SizedBox(height: 30.0),
              _buildEmailSection(context),
              SizedBox(height: 20,),
              _buildPasswordSection(context),
              SizedBox(height: 30.0),
              if (errorMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20.0, left: 50, right: 35),
                  child: Text(
                    errorMessage,
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              Container(
                width: 200.0,
                decoration: BoxDecoration(
                  color: Color(0xFF9CE1CF),
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(color: Color.fromARGB(255, 122, 185, 168)),
                ),
                child: OutlinedButton(
                  onPressed: signIn,
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    side: BorderSide(color: Colors.transparent),
                  ),
                  child: Text(
                    "Login",
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w700,
                      fontSize: 16.0,
                      color: Color.fromRGBO(37, 37, 37, 1),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(top: 20),
                child: GestureDetector(
                  onTap: navigateToSignUp,
                  child: Text(
                    "Create an account",
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontWeight: FontWeight.w300,
                      fontSize: 14,
                      decoration: TextDecoration.underline,
                      decorationColor: Color.fromRGBO(198, 205, 250, 1),
                      color: Color.fromRGBO(198, 205, 250, 1),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmailSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Email",
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white),
        ),
        SizedBox(height: 10.0),
        _buildTextFormField(
          controller: emailController,
          prefixIcon: Icon(Icons.email_outlined, color: Color(0xFF9CE1CF)),
          hintText: "Enter email",
          obscureText: false,
        ),
      ],
    );
  }

  Widget _buildPasswordSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Password",
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white),
        ),
        SizedBox(height: 10.0),
        _buildTextFormField(
          controller: passwordController,
          prefixIcon: Icon(Icons.password_outlined, color: Color(0xFF9CE1CF)),
          hintText: "Enter password",
          obscureText: true,
        ),
      ],
    );
  }

  Widget _buildTextFormField({
    required TextEditingController controller,
    required String hintText,
    bool obscureText = false,
    Widget? prefixIcon,
  }) {
    return SizedBox(
      width: 300.0,
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        style: TextStyle(color: Color.fromARGB(255, 255, 255, 255)),
        decoration: InputDecoration(
          prefixIcon: prefixIcon,
          hintText: hintText,
          hintStyle: TextStyle(color: Color.fromRGBO(195, 195, 195, 1), fontFamily: 'Roboto', fontWeight: FontWeight.w300),
          filled: true,
          fillColor: Color.fromARGB(255, 52, 81, 82),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8.0),
            borderSide: BorderSide(color: Color.fromARGB(255, 52, 81, 82)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8.0),
            borderSide: BorderSide(color: const Color.fromARGB(255, 33, 215, 243)),
          ),
          contentPadding: EdgeInsets.symmetric(vertical: 10.0, horizontal: 10.0),
        ),
      ),
    );
  }
}
