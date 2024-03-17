import 'dart:math';

class Polynomial{
  late final int degree;
  final List<double> coeff;

  double compute(double x){
    double res = 0.0;
    double xpow = 1.0;
    for(int i = 0; i <= degree; i++){
      res += coeff[i] * xpow;
      xpow *= x;
    }
    return res;
  }

  Polynomial(this.coeff){
    degree = coeff.length - 1;
  }
  Polynomial operator+(Polynomial other){
    final newCoeff = List<double>.generate(max(degree, other.degree) + 1, (int i){
      if(i > degree) return other.coeff[i];
      if(i > other.degree) return coeff[i];
      return coeff[i] + other.coeff[i];
    });
    return Polynomial(newCoeff);
  }
  Polynomial operator-(){
    return Polynomial(List<double>.generate(coeff.length, (i) => -coeff[i]));
  }
  Polynomial operator-(Polynomial other){
    return this + -other;
  }
  Polynomial operator*(Polynomial other){
    final newCoeff = List<double>.filled(degree + other.degree + 1, 0.0);
    for(int i = 0; i < coeff.length; i++){
      for(int j = 0; j < other.coeff.length; j++){
        newCoeff[i + j] += coeff[i] * other.coeff[j];
      }
    }
    return Polynomial(newCoeff);
  }

  @override
  String toString(){
    String s = "f(x) = ${coeff[0]}";
    for(int i = 1; i <= degree; i++){
      if(i == 1) {
        s += " + ${coeff[i]}x";
      } else{
        s += " + ${coeff[i]}x^$i";
      }
    }
    return s;
  }
}