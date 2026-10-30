import 'package:flutter/material.dart';

import 'api.dart';
import 'screens/login.dart';
import 'screens/shell.dart';
import 'ui.dart';

void main() => runApp(const AdminApp());

class AdminApp extends StatefulWidget {
  const AdminApp({super.key, this.apiFactory});

  /// Lets tests supply a fake server.
  final AdminApi Function(String baseUrl)? apiFactory;

  @override
  State<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends State<AdminApp> {
  AdminApi? _api;
  String _notice = '';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smriti Sathi Admin',
      debugShowCheckedModeBanner: false,
      theme: adminTheme(),
      home: _api == null
          ? LoginScreen(
              notice: _notice,
              apiFactory: widget.apiFactory ?? AdminApi.new,
              onSignedIn: (api) => setState(() {
                _api = api;
                _notice = '';
              }),
            )
          : Shell(
              api: _api!,
              onSignedOut: ([String? why]) => setState(() {
                _api?.signOut();
                _api = null;
                _notice = why ?? '';
              }),
            ),
    );
  }
}
