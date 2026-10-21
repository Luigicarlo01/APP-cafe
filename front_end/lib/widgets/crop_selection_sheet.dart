import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../screens/analysis_screen.dart';
@deprecated
class CropSelectionSheet extends StatefulWidget {
  final ScrollController scrollController;
  final LatLng selectedPoint;

  const CropSelectionSheet({
    super.key,
    required this.scrollController,
    required this.selectedPoint,
  });

  @override
  State<CropSelectionSheet> createState() => _CropSelectionSheetState();
}

class _CropSelectionSheetState extends State<CropSelectionSheet> {
  String? selectedCrop;

  final List<Map<String, String>> crops = [
    {"name": "Milho", "emoji": "🌽"},
    {"name": "Café", "emoji": "☕"},
    {"name": "Feijão", "emoji": "🫘"},
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 5,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey,
                borderRadius: BorderRadius.circular(8),
              ),
            ),

            const Text(
              "Culturas recomendadas",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 20),

            Expanded(
              child: GridView.builder(
                controller: widget.scrollController,
                itemCount: crops.length,
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.1,
                ),
                itemBuilder: (context, index) {
                  final crop = crops[index];
                  final isSelected = selectedCrop == crop["name"];

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        selectedCrop = crop["name"];
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color.fromARGB(30, 2, 141, 6)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? const Color.fromARGB(255, 2, 141, 6)
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            crop["emoji"]!,
                            style: const TextStyle(fontSize: 36),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            crop["name"]!,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: selectedCrop == null
                ? null
                : () {
                    Navigator.pop(context); // fecha o bottom sheet primeiro
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AnalysisScreen(
                          selectedPoint: widget.selectedPoint,
                          selectedCrop: selectedCrop!,
                        ),
                      ),
                    );
                  },
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      const Color.fromARGB(255, 2, 141, 6),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  "Continuar",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}