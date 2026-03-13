import 'package:flash_forward/models/workout.dart';
import 'package:flutter/material.dart';

class NewWorkoutScreen extends StatefulWidget {
  final Workout? workout;

  const NewWorkoutScreen({super.key, this.workout});

  @override
  State<NewWorkoutScreen> createState() => _NewWorkoutScreenState();
}

class _NewWorkoutScreenState extends State<NewWorkoutScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.workout?.title ?? 'New Workout')),
    );
  }
}
