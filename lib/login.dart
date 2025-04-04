import 'package:flutter/material.dart';

void main() {
  runApp(LoginApp());
}

class LoginApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.light(),
      debugShowCheckedModeBanner: false, 
      home: LoginPage(
        onLoginComplete: (username) {
          runApp(MyApp(username: username));
        },
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  final Function(String) onLoginComplete;
  LoginPage({required this.onLoginComplete});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: Colors.white,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      filled: true,
                      fillColor: Colors.white,
                      labelStyle: TextStyle(color: Colors.black),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your username';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 22.0),
                  ElevatedButton(
                    child: Text('Enter'),
                    onPressed: () {
                      if (_formKey.currentState!.validate()) {
                        widget.onLoginComplete(_usernameController.text);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  final String username;
  MyApp({required this.username});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.light(),
      home: BleHome(username: username),
      debugShowCheckedModeBanner: false, 
    );
  }
}

class BleHome extends StatefulWidget {
  final String username;
  BleHome({required this.username});
  @override
  _BleHomeState createState() => _BleHomeState();
}

class _BleHomeState extends State<BleHome> {
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
