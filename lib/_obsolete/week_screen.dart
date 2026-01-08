import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flash_forward/data/default_session_data.dart';
import 'package:flash_forward/providers/session_log_provider.dart';
import 'package:flash_forward/presentation/screens/session_select_screen.dart';
import 'package:flash_forward/_obsolete/my_app_bar.dart';
import 'package:flash_forward/presentation/widgets/session_select_row.dart';
import 'package:flash_forward/presentation/widgets/session_select_listview.dart';

class WeekScreen extends StatefulWidget {
  const WeekScreen({super.key});

  @override
  State<WeekScreen> createState() => _WeekScreenState();
}

class _WeekScreenState extends State<WeekScreen> {
  // grabs the sessionList from dummy_data.dart.
  final currentSessionList = kDefaultSessions;

  @override
  Widget build(BuildContext context) {
    return Consumer<SessionLogProvider>(
      builder: (context, trainingData, child) {
        return Scaffold(
          // Stful because of AppBar title
          appBar: MyAppBar(title: 'Week ${trainingData.weekIndex + 1}'),
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 20),
                SessionSelectRow(caseStatement: 'Week'),
                SizedBox(height: 50),
                SessionSelectListView(
                  item: currentSessionList,
                  setIndex: trainingData.setSessionIndex,
                  route: SessionSelectScreen(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
