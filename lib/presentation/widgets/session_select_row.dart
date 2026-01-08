import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flash_forward/providers/preset_provider.dart';
import 'package:flash_forward/presentation/widgets/my_arrow_button.dart';
import 'package:flash_forward/providers/session_state_provider.dart';
import 'package:flash_forward/themes/app_shadow.dart';
import 'package:flash_forward/themes/app_text_styles.dart';

class SessionSelectRow extends StatelessWidget {
  const SessionSelectRow({required this.caseStatement, super.key});

  final String caseStatement;

  @override
  Widget build(BuildContext context) {
    return Consumer2<PresetProvider, SessionStateProvider>(
      builder: (context, presetData, sessionStateData, child) {
        int index = 0;
        int itemLength = 0;
        void Function() decrement = () {};
        void Function() increment = () {};

        switch (caseStatement) {
          case 'Week':
            {
              index = sessionStateData.weekIndex;
              itemLength = presetData.presetSessions.length;
              decrement = sessionStateData.decrementWeekIndex;
              increment = sessionStateData.incrementWeekIndex;
            }
          case 'Session':
            {
              index = sessionStateData.sessionIndex;
              itemLength = presetData.presetSessions.length;
              decrement = sessionStateData.decrementSessionIndex;
              increment = sessionStateData.incrementSessionIndex;
            }
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // TODO: replace sizedbox with expanded/flexbile widgets?
            SizedBox(width: 10),
            GestureDetector(
              onTap: () {
                if (index > 0) {
                  decrement();
                }
              },
              child: MyArrowButton(icon: Icons.arrow_back),
            ),
            GestureDetector(
              onTap: () {
                if (index > 0) {
                  decrement();
                }
              },
              child: SizedBox(
                width: 75,
                height: 100,
                child: () {
                  if (index > 0) {
                    return MyRowCard(title: index.toString());
                  }
                }(),
              ),
            ),

            // Only widget in the row that doesn't need to be tapped
            SizedBox(
              width: 90,
              height: 120,
              child: MyRowCard(title: (index + 1).toString()),
            ),
            GestureDetector(
              onTap: () {
                increment();
              },
              child: SizedBox(
                width: 75,
                height: 100,
                child: () {
                  if (index < itemLength - 1) {
                    return MyRowCard(title: (index + 2).toString());
                  }
                }(),
              ),
            ),
            GestureDetector(
              onTap: () {
                if (index < itemLength - 1) {
                  increment();
                }
              },
              child: MyArrowButton(icon: Icons.arrow_forward),
            ),
            SizedBox(width: 10),
          ],
        );
      },
    );
  }
}

class MyRowCard extends StatelessWidget {
  const MyRowCard({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            width: 0.25,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          color: Theme.of(context).colorScheme.surfaceBright,
          boxShadow: context.shadowLarge,
        ),
        child: Center(
          child: Text(title, textAlign: TextAlign.center, style: context.h2),
        ),
      ),
    );
  }
}
