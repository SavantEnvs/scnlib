// Known-answer probe: scans fixed inputs through the public API and prints the parsed values.
// mayhem/test.sh compares this output to exact expected text, so a neutered or no-op scn fails.
#include <scn/scan.h>

#include <cstdio>
#include <string>

int main()
{
    int failures = 0;

    if (auto r = scn::scan<int, double, std::string>("42 3.5 hello", "{} {} {}")) {
        auto [i, d, s] = r->values();
        std::printf("basic %d %.2f %s\n", i, d, s.c_str());
    }
    else {
        ++failures;
    }

    if (auto r = scn::scan<int, unsigned>("ff 0b101", "{:x} {:b}")) {
        auto [a, b] = r->values();
        std::printf("radix %d %u\n", a, b);
    }
    else {
        ++failures;
    }

    if (auto r = scn::scan<double>("1.5e3", "{}")) {
        std::printf("float %.1f\n", r->value());
    }
    else {
        ++failures;
    }

    if (auto r = scn::scan<std::string, char>("word:x", "{:[a-z]}{}")) {
        auto [w, c] = r->values();
        std::printf("class %s %c\n", w.c_str(), c);
    }
    else {
        ++failures;
    }

    auto bad = scn::scan<int>("abc", "{}");
    std::printf("reject %d\n", bad ? 0 : 1);

    auto overflow = scn::scan<signed char>("300", "{}");
    std::printf("overflow %d\n", overflow ? 0 : 1);

    return failures;
}
