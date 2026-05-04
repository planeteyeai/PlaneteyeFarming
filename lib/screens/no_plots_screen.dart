import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

class NoPlotsScreen extends StatelessWidget {
  final VoidCallback onAddPlot;
  final VoidCallback onLogout;

  const NoPlotsScreen({
    super.key,
    required this.onAddPlot,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),

              // Illustration
              Container(
                width: 120, height: 120,
                decoration: BoxDecoration(
                  color: AppColors.greenLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add_location_alt_outlined,
                    color: AppColors.primary, size: 56),
              ),
              const SizedBox(height: 28),

              const Text('No Plots Yet',
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textDark,
                      letterSpacing: -0.5)),
              const SizedBox(height: 12),
              const Text(
                "You're logged in! Add your first plot\nto start monitoring your fields.",
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMedium,
                    height: 1.5),
              ),

              const Spacer(),

              // Add plot button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onAddPlot,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(40)),
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    elevation: 8,
                  ),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Text('Add My First Plot',
                            style: TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 17)),
                        SizedBox(width: 10),
                        Icon(Icons.add_location_alt_outlined, size: 22),
                      ]),
                ),
              ),
              const SizedBox(height: 16),

              // Logout
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onLogout,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textMedium,
                    side: const BorderSide(color: AppColors.borderLight, width: 2),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(40)),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.logout, size: 18),
                        SizedBox(width: 8),
                        Text('Sign Out',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15)),
                      ]),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
