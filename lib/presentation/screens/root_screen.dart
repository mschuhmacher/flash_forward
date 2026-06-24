import 'package:flash_forward/core/settings_provider.dart';
import 'package:flash_forward/features/catalog/catalog_provider.dart';
import 'package:flash_forward/presentation/screens/session_flow/home_screen.dart';
import 'package:flash_forward/presentation/screens/profile_flow/profile_screen.dart';
import 'package:flash_forward/presentation/screens/profile_flow/settings_drawer.dart';
import 'package:flash_forward/presentation/screens/catalog_flow/new_exercise_screen.dart';
import 'package:flash_forward/presentation/screens/catalog_flow/new_session_screen.dart';
import 'package:flash_forward/presentation/screens/catalog_flow/new_workout_screen.dart';
import 'package:flash_forward/presentation/screens/catalog_flow/catalog_screen.dart';
import 'package:flash_forward/features/auth/auth_provider.dart';
import 'package:flash_forward/presentation/widgets/onboarding_skip_button.dart';
import 'package:flash_forward/presentation/widgets/onboarding_targets.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_shadow.dart';
import 'package:flash_forward/themes/app_text_theme.dart';

import 'package:flutter/material.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import 'package:provider/provider.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen>
    with SingleTickerProviderStateMixin {
  late final List<Widget> destinationScreens;
  int _selectedScreenIndex = 0;
  late final TabController _tabController;

  late TutorialCoachMark tutorialCoachMark;
  GlobalKey keyTabNavigation = GlobalKey();
  GlobalKey keyListItem = GlobalKey();
  GlobalKey keyCatalogSearchFilter = GlobalKey();
  GlobalKey keyExerciseList = GlobalKey();
  late final Map<String, GlobalKey> onboardingKeys;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    onboardingKeys = {
      'tabNavigation': keyTabNavigation,
      'catalogSearchFilter': keyCatalogSearchFilter,
      'listItem': keyListItem,
      'exerciseList': keyExerciseList,
    };
    destinationScreens = [
      HomeScreen(),
      CatalogScreen(
        tabController: _tabController,
        onboardingKeys: onboardingKeys,
      ),
      ProfileScreen(),
    ];
    if (!context.read<SettingsProvider>().onboardingCatalogComplete &&
        _selectedScreenIndex == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) => createTutorial());
      Future.delayed(Duration(milliseconds: 300), showTutorial);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          _selectedScreenIndex == 1
              ? AppBar(
                title: TabBar(
                  key: keyTabNavigation,
                  controller: _tabController,
                  labelStyle: context.titleLarge.copyWith(
                    color: context.colorScheme.primary,
                  ),
                  tabs: [
                    Tab(text: 'Sessions'),
                    Tab(text: 'Workouts'),
                    Tab(text: 'Exercises'),
                  ],
                ),
                surfaceTintColor:
                    Colors
                        .transparent, //disables Material3 overlay. I.e. doesn't change the color of the appBar when the ListView scrolls
              )
              : null,
      body: SafeArea(child: destinationScreens[_selectedScreenIndex]),
      floatingActionButton:
          _selectedScreenIndex == 1
              ? FloatingActionButton(
                onPressed: () {
                  switch (_tabController.index) {
                    case 0:
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (_) => NewSessionScreen(
                                mode: NewSessionScreenMode.create,
                              ),
                        ),
                      );
                    case 1:
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (_) => NewWorkoutScreen(persistToProvider: true),
                        ),
                      );
                    case 2:
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (_) => NewExerciseScreen(persistToProvider: true),
                        ),
                      );
                  }
                },
                child: Icon(Icons.add),
              )
              : null,
      endDrawer: _selectedScreenIndex == 2 ? SettingsDrawer() : null,
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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
                    tabs: [
                      GButton(icon: Icons.home_rounded, text: 'Home'),
                      GButton(icon: Icons.event_note_rounded, text: 'Catalog'),
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
                      if (index == 1 &&
                          !context
                              .read<SettingsProvider>()
                              .onboardingCatalogComplete) {
                        // AppBar/TabBar for Catalog only builds during this frame —
                        // wait for it to be laid out before measuring target positions.
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          createTutorial();
                          showTutorial();
                        });
                      }
                    },
                  ),
            ),
          ),
        ),
      ),
    );
  }

  void showTutorial() {
    if (!mounted) return;
    tutorialCoachMark.show(context: context);
  }

  void createTutorial() {
    tutorialCoachMark = TutorialCoachMark(
      targets: createCatalogOnboardingTargets(onboardingKeys: onboardingKeys),
      colorShadow: context.colorScheme.primary,
      skipWidget: SkipOnboarding(),
      paddingFocus: 20,
      opacityShadow: 0.7,
      onClickTarget: (target) {
        if (target.identify == "keyTabNavigation") {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _tabController.animateTo(1),
          );
        }
        if (target.identify == "keyListItem") {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => Navigator.push(
              context,
              MaterialPageRoute(
                builder:
                    (context) => NewWorkoutScreen(
                      workout:
                          context.read<CatalogProvider>().presetWorkouts[0],
                      persistToProvider: true,
                      onboardingKeys: onboardingKeys,
                    ),
              ),
            ),
          );
        }
      },
      onFinish: () {
        // context.read<SettingsProvider>().markOnboardingCatalogComplete();
        Navigator.pop(context);
      },
      onSkip: () {
        context.read<SettingsProvider>().markOnboardingCatalogComplete();
        return true;
      },
    );
  }

}
