import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:scidart/numdart.dart';

import 'polynomial.dart';

/// Performs cubic spline interpolation of given points according to this article: https://blog.timodenk.com/cubic-spline-interpolation/index.html
class CubicSpline{
  final List<Offset> points;
  late final List<Polynomial> poly;
  bool exists = true;

  bool _isGrowing(List<Offset> l){
    for(int i = 1; i < l.length; i++){
      if(l[i].dx < l[i - 1].dx) return false;
    }
    return true;
  }

  CubicSpline(this.points){
    if(!_isGrowing(points)){
      exists = false;
      return;
    }
    final n = points.length - 1;
    final mat = Array2d.fixed(4 * n, 4 * n, initialValue: 0);
    final known = Array.fixed(4 * n, initialValue: 0);

    // polynomials have to match their endpoints - 2n equations
    for(int i = 0; i < n; i++){
      for(int j = 0; j < 2; j++){
        for(int k = 0; k < 4; k++){
          mat[2 * i + j][4 * i + k] = pow(points[i + j].dx, k).toDouble();
        }
        known[2 * i + j] = points[i + j].dy;
      }
    }
    int d = 2 * n;

    // polynomials' derivatives have to match each other at endpoints - (n - 1) equations
    for(int i = 0; i < n - 1; i++){
      for(int j = 1; j < 4; j++){
        mat[i + d][4 * i + j] = j * pow(points[i + 1].dx, j - 1).toDouble();
        mat[i + d][4 * (i + 1) + j] = -j * pow(points[i + 1].dx, j - 1).toDouble();
      }
      // known = 0 already
    }
    d += n - 1;

    // second derivatives have to match each other at endpoints - (n - 1) equations
    for(int i = 0; i < n - 1; i++){
      for(int j = 2; j < 4; j++){
        mat[i + d][4 * i + j] = j * (j - 1) * pow(points[i + 1].dx, j - 2).toDouble();
        mat[i + d][4 * (i + 1) + j] = -j * (j - 1) * pow(points[i + 1].dx, j - 2).toDouble();
      }
      // known = 0 already
    }
    d += n - 1;

    // second derivative at first point is 0 - 1 equation:
    for(int j = 2; j < 4; j++){
      mat[d][j] = j * (j - 1) * pow(points[0].dx, j - 2).toDouble();
    }
    d++;
    // known = 0 already

    // second derivative at last point is 0 - 1 equation:
    for(int j = 2; j < 4; j++){
      mat[d][4 * (n - 1) + j] = j * (j - 1) * pow(points[n].dx, j - 2).toDouble();
    }
    // known = 0 already

    // total : 2n + (n - 1) + (n - 1) + 1 + 1 = 4n equations

    final sol = matrixSolve(mat, Array2d.fromVector(known, 4 * n));

    poly = List<Polynomial>.generate(n, (i){
      final sub = sol.sublist(4 * i, 4 * (i + 1));
      final coeff = List<double>.generate(4, (j) => sub[j].first);
      return Polynomial(coeff);
    });
  }

  double compute(double x){
    if(!exists) throw const FormatException("Given points are not valid: x-coordinates should be in ascending order");
    int i = lowerBound(points, Offset(x, double.infinity), compare: (a, b){
      if(a.dx == b.dx) return a.dy.compareTo(b.dy);
      return a.dx.compareTo(b.dx);
    });
    i--;

    // values that do not fall into given range of points will be evaluated on the leftmost or rightmost polynomial
    if(i < 0) i = 0;
    if(i == poly.length) i--;
    
    return poly[i].compute(x);
  }
}