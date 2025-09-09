import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Premium Features Widget for subscription management
class PremiumFeaturesWidget extends StatelessWidget {
  final bool isPremium;
  final VoidCallback onUpgrade;
  
  const PremiumFeaturesWidget({
    super.key,
    required this.isPremium,
    required this.onUpgrade,
  });
  
  @override
  Widget build(BuildContext context) {
    if (isPremium) {
      return _buildPremiumBadge();
    }
    
    return _buildUpgradePrompt();
  }
  
  Widget _buildPremiumBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.amber, Colors.orange],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star, color: Colors.white, size: 16),
          SizedBox(width: 4),
          Text(
            'PREMIUM',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildUpgradePrompt() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onUpgrade();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          border: Border.all(color: Colors.amber.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock, color: Colors.white.withOpacity(0.7), size: 16),
            const SizedBox(width: 4),
            Text(
              'Upgrade',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}