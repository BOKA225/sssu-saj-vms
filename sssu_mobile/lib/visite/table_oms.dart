import 'package:flutter/services.dart';
import 'package:sssu_core/sssu_core.dart';

TableImcOms? _cache;
bool _chargee = false;

/// Tables OMS de l'IMC pour l'âge (5-19 ans), lues dans les ressources de
/// l'application si elles ont été fournies (voir assets/oms/LISEZMOI.txt).
Future<TableImcOms?> chargerTableOms() async {
  if (_chargee) return _cache;
  _chargee = true;
  try {
    _cache = TableImcOmsCsv.depuisCsv(
      garcons: await rootBundle.loadString('assets/oms/imc_age_garcons.csv'),
      filles: await rootBundle.loadString('assets/oms/imc_age_filles.csv'),
    );
  } catch (_) {
    _cache = null;
  }
  return _cache;
}
