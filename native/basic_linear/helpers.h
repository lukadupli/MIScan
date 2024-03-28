#pragma once

#include <string>

const double EPSILON = 1e-6;
const double SIGNAL = 1ULL << 63;

bool eq(double a, double b);
double sq(double x);

class BasicLinearException{
private: 
    std::string _what;
public:
    BasicLinearException(std::string what) : _what(what){}
    std::string what();
};

inline void basicLinearAssert(bool expression){
    if(!expression) throw BasicLinearException("Can't compute this");
}