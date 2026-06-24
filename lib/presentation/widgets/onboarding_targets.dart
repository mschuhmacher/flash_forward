import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_text_theme.dart';

List<TargetFocus> createSessionSelectOnboardingTargets({
  required Map<String, GlobalKey> onboardingKeys,
}) {
  List<TargetFocus> targets = [];
  targets.add(
    TargetFocus(
      identify: "keySessionList",
      keyTarget: onboardingKeys['sessionListItem'],
      alignSkip: Alignment.bottomLeft,
      shape: ShapeLightFocus.RRect,
      radius: 40,
      contents: [
        TargetContent(
          align: ContentAlign.bottom,
          builder: (context, controller) {
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                color: context.colorScheme.surfaceBright,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Text(
                      "Select a session and tap the arrow to view its details",
                      style: context.titleLarge,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    ),
  );
  targets.add(
    TargetFocus(
      identify: "keyFAB",
      keyTarget: onboardingKeys['sessionSelectFAB'],
      alignSkip: Alignment.bottomLeft,
      shape: ShapeLightFocus.RRect,
      radius: 25,
      contents: [
        TargetContent(
          align: ContentAlign.top,
          builder: (context, controller) {
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                color: context.colorScheme.surfaceBright,
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      "Tap here to make some quick edits before starting the session.",
                      style: context.titleLarge,
                    ),
                    SizedBox(height: 16),
                    Text(
                      "Add, change, or remove exercises based on how you feel today",
                      style: context.bodyLarge,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    ),
  );
  return targets;
}

List<TargetFocus> createSessionActiveOnboardingTargets({
  required Map<String, GlobalKey> onboardingKeys,
}) {
  List<TargetFocus> targets = [];
  targets.add(
    TargetFocus(
      identify: "keyPauseResumeOvertime",
      keyTarget: onboardingKeys['pauseResumeOvertimeButton'],
      alignSkip: Alignment.bottomLeft,
      shape: ShapeLightFocus.RRect,
      radius: 25,
      contents: [
        TargetContent(
          align: ContentAlign.top,
          builder: (context, controller) {
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                color: context.colorScheme.surfaceBright,
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      "Tap to pause, hold to enter overtime",
                      style: context.titleLarge,
                    ),
                    SizedBox(height: 16),
                    Text(
                      "Enter overtime to start a longer rest than initially planned. The timer starts counting up, and once you're ready, just tap to get back in.",
                      style: context.bodyMedium,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    ),
  );
  targets.add(
    TargetFocus(
      identify: "keyEditButton",
      keyTarget: onboardingKeys['editButton'],
      alignSkip: Alignment.bottomLeft,
      shape: ShapeLightFocus.RRect,
      radius: 25,
      contents: [
        TargetContent(
          align: ContentAlign.top,
          builder: (context, controller) {
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                color: context.colorScheme.surfaceBright,
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      "You can edit this exercise from here.",
                      style: context.titleLarge,
                    ),
                    SizedBox(height: 16),
                    Text(
                      "Change the reps, sets, load, rest or active periods. But you can also access the menu to change your whole session from there.",
                      style: context.bodyLarge,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    ),
  );
  targets.add(
    TargetFocus(
      identify: "keyActiveSessionEditButton",
      keyTarget: onboardingKeys['activeSessionEditButton'],
      alignSkip: Alignment.bottomLeft,
      shape: ShapeLightFocus.RRect,
      radius: 25,
      contents: [
        TargetContent(
          align: ContentAlign.bottom,
          builder: (context, controller) {
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                color: context.colorScheme.surfaceBright,
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      "Use this button to edit the entire session.",
                      style: context.titleLarge,
                    ),
                    SizedBox(height: 16),
                    Text(
                      "You can add, change, remove workouts and exercises from the current session.",
                      style: context.bodyLarge,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    ),
  );
  // targets.add(
  //   TargetFocus(
  //     identify: "keyNavigationBar",
  //     keyTarget: onboardingKeys['navigationBar'],
  //     alignSkip: Alignment.bottomLeft,
  //     shape: ShapeLightFocus.RRect,
  //     radius: 25,
  //     contents: [
  //       TargetContent(
  //         align: ContentAlign.top,
  //         builder: (context, controller) {
  //           return Container(
  //             decoration: BoxDecoration(
  //               borderRadius: BorderRadius.circular(25),
  //               color: context.colorScheme.surfaceBright,
  //             ),
  //             child: Padding(
  //               padding: const EdgeInsets.all(20.0),
  //               child: Column(
  //                 mainAxisSize: MainAxisSize.min,
  //                 crossAxisAlignment: CrossAxisAlignment.start,
  //                 children: <Widget>[
  //                   Text(
  //                     "Jump to the next or previous exercise.",
  //                     style: context.titleLarge,
  //                   ),
  //                   SizedBox(height: 16),
  //                   Text(
  //                     "And see which exercise is coming up.",
  //                     style: context.bodyLarge,
  //                   ),
  //                 ],
  //               ),
  //             ),
  //           );
  //         },
  //       ),
  //     ],
  //   ),
  // );
  return targets;
}

List<TargetFocus> createCatalogOnboardingTargets({
  required Map<String, GlobalKey> onboardingKeys,
}) {
  final List<TargetFocus> targets = [];
  targets.add(
    TargetFocus(
      identify: "keyTabNavigation",
      keyTarget: onboardingKeys['tabNavigation'],
      alignSkip: Alignment.bottomLeft,
      shape: ShapeLightFocus.RRect,
      radius: 25,
      contents: [
        TargetContent(
          align: ContentAlign.bottom,
          builder: (context, controller) {
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                color: context.colorScheme.surfaceBright,
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      "This is your training catalog.",
                      style: context.titleLarge,
                    ),
                    SizedBox(height: 16),
                    Text(
                      "You can group exercises together into reusable blocks, called workouts. For example, create your personal warm-up routine once, and reuse it in every session.\n\nEasily create template sessions to give structure to your climbing. Add workouts for your warm-up, on-the-wall climbing, and strength training or flexibility.",
                      style: context.bodyMedium,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    ),
  );
  targets.add(
    TargetFocus(
      identify: "keyCatalogSearchFilter",
      keyTarget: onboardingKeys['catalogSearchFilter'],
      alignSkip: Alignment.bottomLeft,
      shape: ShapeLightFocus.RRect,
      radius: 25,
      contents: [
        TargetContent(
          align: ContentAlign.bottom,
          builder: (context, controller) {
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                color: context.colorScheme.surfaceBright,
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      "You can search or filter the list from here.",
                      style: context.titleLarge,
                    ),
                    SizedBox(height: 16),
                    Text(
                      "The app filters by label, for easy categorization.",
                      style: context.bodyMedium,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    ),
  );
  targets.add(
    TargetFocus(
      identify: "keyListItem",
      keyTarget: onboardingKeys['listItem'],
      alignSkip: Alignment.bottomLeft,
      shape: ShapeLightFocus.RRect,
      radius: 25,
      contents: [
        TargetContent(
          align: ContentAlign.bottom,
          builder: (context, controller) {
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                color: context.colorScheme.surfaceBright,
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      "Click on a workout to edit.",
                      style: context.titleLarge,
                    ),
                    SizedBox(height: 16),
                    Text(
                      "Any changes that you make to a workout (or exercise) can be synced to other sessions that already use that workout. \n\nThat way, you only have to edit your warm-up routine once, and not edit every session one by one.",
                      style: context.bodyMedium,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    ),
  );
  targets.add(
    TargetFocus(
      identify: "keyExerciseList",
      keyTarget: onboardingKeys['exerciseList'],
      alignSkip: Alignment.bottomLeft,
      shape: ShapeLightFocus.RRect,
      radius: 25,
      contents: [
        TargetContent(
          align: ContentAlign.top,
          padding: EdgeInsets.fromLTRB(8, 8, 8, 0),
          builder: (context, controller) {
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                color: context.colorScheme.surfaceBright,
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      "Exercises can be standalone, or part of a superset / circuit.",
                      style: context.titleLarge,
                    ),
                    SizedBox(height: 16),
                    Text(
                      "Slide the exercise left to remove or add the exercise to a superset. Supersets are grouped together by color.\n\nSwipe left to copy or to add the exercise to the catalog. If you made changes to an exercise and you wish to save those changes as a separate exercise, you can do so through 'Save to catalog'.",
                      style: context.bodyMedium,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    ),
  );
  return targets;
}
