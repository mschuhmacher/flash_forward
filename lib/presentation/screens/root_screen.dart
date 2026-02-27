import 'package:flash_forward/presentation/screens/add_item_screen.dart';
import 'package:flash_forward/presentation/screens/home_screen.dart';
import 'package:flash_forward/presentation/screens/profile_screen.dart';
import 'package:flash_forward/providers/auth_provider.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_shadow.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flutter/material.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import 'package:provider/provider.dart';

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  final List<Widget> destinationScreens = <Widget>[
    HomeScreen(),
    AddItemScreen(itemName: 'session'),
    ProfileScreen(),
  ];
  int _selectedScreenIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          _selectedScreenIndex == 1
              ? AppBar(
                title: Text(
                  'New Session',
                  style: context.h4,
                ), //TODO: make changeable
                surfaceTintColor:
                    Colors
                        .transparent, //disables Material3 overlay. I.e. doesn't change the color of the appBar when the ListView scrolls
              )
              : null,
      body: SafeArea(child: destinationScreens[_selectedScreenIndex]),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: context.colorScheme.surface,
          boxShadow: context.shadowLarge,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(32),
            topRight: Radius.circular(32),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16, 16, 0),
            child: Consumer<AuthProvider>(
              builder:
                  (context, authProvider, child) => GNav(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    // rippleColor: context.colorScheme.primary.withAlpha(50),
                    gap: 8,
                    iconSize: 24,
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    duration: Duration(milliseconds: 400),
                    activeColor: context.colorScheme.primary,
                    color: context.colorScheme.primary,
                    // tabBackgroundColor: context.colorScheme.surfaceDim,
                    textStyle: context.bodyLarge.copyWith(
                      color: context.colorScheme.primary,
                    ),
                    tabActiveBorder: Border.all(
                      color: context.colorScheme.primary,
                      width: 1,
                    ),
                    // tabShadow: context.shadowMedium,
                    // tabBorder: Border.all(
                    //   color: context.colorScheme.secondary,
                    //   width: 1,
                    // ),
                    tabs: [
                      GButton(icon: Icons.home_rounded, text: 'Home'),
                      GButton(icon: Icons.event_note_rounded, text: 'Schedule'),
                      GButton(
                        icon: Icons.person_rounded,
                        text:
                            authProvider.userProfile?.firstName.isNotEmpty ==
                                    true
                                ? authProvider.userProfile!.firstName
                                : "Climber",
                      ),
                    ],
                    selectedIndex: _selectedScreenIndex,
                    onTabChange: (index) {
                      setState(() {
                        _selectedScreenIndex = index;
                      });
                    },
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
