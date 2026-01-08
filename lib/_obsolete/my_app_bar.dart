import 'package:flutter/material.dart';
import 'package:flash_forward/themes/app_text_styles.dart';

class MyAppBar extends StatelessWidget implements PreferredSizeWidget {
  const MyAppBar({super.key, required this.title});

  final String title;

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(title: Text(title, style: context.h4), centerTitle: true);
  }
}
