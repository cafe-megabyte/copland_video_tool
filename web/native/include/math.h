#ifndef COPLAND_WEB_MATH_H
#define COPLAND_WEB_MATH_H
#define isfinite(x) __builtin_isfinite(x)
double floor(double);
double ceil(double);
double nearbyint(double);
double pow(double, double);
double log(double);
double fmin(double, double);
double fmax(double, double);
long lrint(double);
#endif
