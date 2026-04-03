import 'package:flash_forward/models/session.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flash_forward/presentation/screens/session_flow/session_select_screen.dart';
import 'package:flash_forward/presentation/screens/session_flow/session_active_screen.dart';
import 'package:flash_forward/providers/session_state_provider.dart';
import 'package:flash_forward/themes/app_text_theme.dart';

class StartSessionButton extends StatelessWidget {
  final VoidCallback onTap;

  const StartSessionButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
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
                onTap();
              },
              child: Text('Start session'),
            );
          },
        ),
      ),
    );
  }
}
