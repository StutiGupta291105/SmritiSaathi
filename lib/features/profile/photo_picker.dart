import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/strings.dart';

/// Lets the person take or choose a photo, shrunk to 512 px. The bytes go
/// straight into the encrypted database; the temporary file the picker leaves
/// in the app cache is deleted so no unencrypted copy stays on the phone.
Future<Uint8List?> pickPhoto(BuildContext context, String lang) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera, size: 32),
            title: Text(tr(lang, 'fromCamera'),
                style: const TextStyle(fontSize: 17)),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library, size: 32),
            title: Text(tr(lang, 'fromGallery'),
                style: const TextStyle(fontSize: 17)),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;
  try {
    final picked = await ImagePicker().pickImage(
        source: source, maxWidth: 512, maxHeight: 512, imageQuality: 80);
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    try {
      await File(picked.path).delete();
    } catch (_) {}
    return bytes;
  } catch (_) {
    return null;
  }
}

/// Round photo, or an icon when there is none.
class Avatar extends StatelessWidget {
  const Avatar({super.key, this.photo, this.radius = 28, this.icon = Icons.person});
  final List<int>? photo;
  final double radius;
  final IconData icon;

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: radius,
        backgroundImage:
            photo == null ? null : MemoryImage(Uint8List.fromList(photo!)),
        child: photo == null ? Icon(icon, size: radius) : null,
      );
}
