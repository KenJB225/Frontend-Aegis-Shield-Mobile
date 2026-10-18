import 'dart:io';

import 'package:flutter/material.dart';

Widget buildSilongLogoImage({
  required double width,
  required double height,
  required BoxFit fit,
}) {
  final file = _findSilongLogoFile();
  if (file != null) {
    return Image.file(
      file,
      width: width,
      height: height,
      fit: fit,
      filterQuality: FilterQuality.high,
    );
  }

  return Image.asset(
    'SILONG_LOGO.jpg',
    width: width,
    height: height,
    fit: fit,
    filterQuality: FilterQuality.high,
    errorBuilder: (context, error, stackTrace) {
      return Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFD7E0EA)),
        ),
        child: const Text(
          'SILONG',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF169A92),
            fontWeight: FontWeight.w800,
            letterSpacing: 6,
          ),
        ),
      );
    },
  );
}

File? _findSilongLogoFile() {
  final starts = <Directory>{
    Directory.current,
    File(Platform.resolvedExecutable).parent,
  };

  for (final start in starts) {
    var current = start;
    for (var i = 0; i < 12; i++) {
      final candidate = File(
        '${current.path}${Platform.pathSeparator}SILONG_LOGO.jpg',
      );
      if (candidate.existsSync()) {
        return candidate;
      }

      final parent = current.parent;
      if (parent.path == current.path) {
        break;
      }
      current = parent;
    }
  }

  return null;
}
