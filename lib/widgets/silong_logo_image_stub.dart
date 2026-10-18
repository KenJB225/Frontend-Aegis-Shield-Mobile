import 'package:flutter/material.dart';

Widget buildSilongLogoImage({
  required double width,
  required double height,
  required BoxFit fit,
}) {
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
