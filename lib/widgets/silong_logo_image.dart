import 'package:flutter/material.dart';

import 'silong_logo_image_stub.dart'
    if (dart.library.io) 'silong_logo_image_io.dart';

class SilongLogoImage extends StatelessWidget {
  const SilongLogoImage({
    super.key,
    required this.width,
    required this.height,
    this.padding = EdgeInsets.zero,
  });

  final double width;
  final double height;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: buildSilongLogoImage(
        width: width,
        height: height,
        fit: BoxFit.contain,
      ),
    );
  }
}
