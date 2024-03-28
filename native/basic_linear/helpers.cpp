#include "helpers.h"

bool eq(double a, double b) { return (a - b) < EPSILON && (b - a) < EPSILON; }
double sq(double x) { return x * x; }

std::string BasicLinearException::what() { return _what; }