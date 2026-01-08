import 'package:flutter/material.dart';
import 'package:flash_forward/models/label.dart';

const Map<String, Label> kDefaultLabels = {
  'Warm-up': Label(name: 'Warm-up', icon: Icons.wb_sunny, color: Colors.amber),
  'Limit': Label(name: 'Limit', icon: Icons.trending_up, color: Colors.red),
  'Finger strength': Label(
    name: 'Finger strength',
    icon: Icons.fingerprint_outlined,
    color: Colors.yellow,
  ),
  'Power': Label(
    name: 'Power',
    icon: Icons.flare, // explosion-like icon replacement
    color: Colors.red,
  ),
  'Powerendurance': Label(
    name: 'Powerendurance',
    icon: Icons.bolt,
    color: Colors.orange,
  ),
  'Endurance': Label(name: 'Endurance', icon: Icons.loop, color: Colors.blue),
  'Strength': Label(
    name: 'Strength',
    icon: Icons.fitness_center,
    color: Colors.purple,
  ),
  'Technique': Label(
    name: 'Technique',
    icon: Icons.touch_app,
    color: Colors.green,
  ),
  'Skills': Label(name: 'Skills', icon: Icons.psychology, color: Colors.teal),
  'Flexibility': Label(
    name: 'Flexibility',
    icon: Icons.self_improvement,
    color: Colors.pink,
  ),
  'Daily maintenance': Label(
    name: 'Daily maintenance',
    icon: Icons.favorite,
    color: Colors.redAccent,
  ),
  'Other': Label(name: 'Other', icon: Icons.more_horiz, color: Colors.grey),
};
