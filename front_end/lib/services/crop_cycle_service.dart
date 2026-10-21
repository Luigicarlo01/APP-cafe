
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

enum CropCycle {
    curto, medio, longo;
    String get label {
    switch (this) {
      case CropCycle.curto: return 'Curto';
      case CropCycle.medio: return 'Médio';
      case CropCycle.longo: return 'Longo';
      }
    }
}

class CropCycleService extends ChangeNotifier{
  static final CropCycleService _instance = CropCycleService._();
  factory CropCycleService () => _instance;
  CropCycleService._();
  CropCycle _cycle = CropCycle.medio;
  CropCycle get cycle => _cycle;

  void setCycle(CropCycle novo){
    if(novo == _cycle) return;

    _cycle = novo;
    notifyListeners();
  }
}

