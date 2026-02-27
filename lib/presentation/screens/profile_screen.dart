import 'package:flash_forward/providers/auth_provider.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder:
          (context, authProvider, child) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: context.colorScheme.primary,
                      child: Text(
                        authProvider.userProfile?.firstName.isNotEmpty == true
                            ? authProvider.userProfile!.firstName[0]
                                .toUpperCase()
                            : 'U',
                        style: context.h2.copyWith(
                          color: context.colorScheme.onPrimary,
                        ),
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${authProvider.userProfile!.firstName} ${authProvider.userProfile!.lastName}',
                            style: context.titleLarge,
                          ),
                          authProvider.userProfile!.country == null
                              ? SizedBox.shrink()
                              : Text(authProvider.userProfile!.country!, style: context.bodyMedium,),
                      
                          Text(authProvider.userProfile!.email, style: context.bodyMedium,),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
    );
  }
}
