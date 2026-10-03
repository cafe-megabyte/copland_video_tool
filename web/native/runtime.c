#include <stddef.h>
void *memcpy(void *to, const void *from, size_t count) {
    unsigned char *d = to; const unsigned char *s = from;
    for (size_t i = 0; i < count; ++i) d[i] = s[i];
    return to;
}
void *memset(void *to, int value, size_t count) {
    unsigned char *d = to;
    for (size_t i = 0; i < count; ++i) d[i] = (unsigned char)value;
    return to;
}
double floor(double x) { return __builtin_floor(x); }
double ceil(double x) { return __builtin_ceil(x); }
double nearbyint(double x) { return __builtin_nearbyint(x); }
long lrint(double x) { return (long)__builtin_nearbyint(x); }
double fmin(double a, double b) { return a < b ? a : b; }
double fmax(double a, double b) { return a > b ? a : b; }
