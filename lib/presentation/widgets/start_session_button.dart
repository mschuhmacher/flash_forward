import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flash_forward/presentation/screens/session_select_screen.dart';
import 'package:flash_forward/presentation/screens/session_active_screen.dart';
import 'package:flash_forward/providers/session_state_provider.dart';
import 'package:flash_forward/themes/app_text_styles.dart';

class StartSessionButton extends StatelessWidget {
  final String routeName;

  const StartSessionButton({super.key, required this.routeName});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.only(left: 20.0, right: 20.0),
        child: Consumer<SessionStateProvider>(
          builder: (context, sessionStateData, child) {
            return ElevatedButton(
              style: ElevatedButton.styleFrom(textStyle: context.h4),
              onPressed: () {
                // reset blockIndex before navigating to workoutscreen
                sessionStateData.setWorkoutIndex(0);

                switch (routeName) {
                  case 'session_select_screen':
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SessionSelectScreen(),
                      ),
                    );
                    break;
                  case 'workout_screen':
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ActiveSessionScreen(),
                      ),
                    );
                    break;
                  default:
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Unknown route')),
                    );
                }
              },
              child: Text('Start session'),
            );
          },
        ),
      ),
    );
  }
}
