import 'package:flutter/material.dart';

class GenotypePoint {
  final Offset position;
  final String genotype;
  final List<String> alternatives; // top2, top3... quantos o backend mandar
  final Color? color;

  const GenotypePoint({
    required this.position,
    required this.genotype,
    this.alternatives = const [],
    this.color,
  });
}