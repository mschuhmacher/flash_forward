import 'package:flash_forward/models/exercise.dart';
import 'package:flutter/material.dart';

class NewExerciseScreen extends StatefulWidget {
  final Exercise? exercise;

  const NewExerciseScreen({super.key, this.exercise});

  @override
  State<NewExerciseScreen> createState() => _NewExerciseScreenState();
}

class _NewExerciseScreenState extends State<NewExerciseScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.exercise?.title ?? 'New Exercise')),
    );
  }
}
