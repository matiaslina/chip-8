import std.stdio;
import core.checkedint;

void main() {
    ubyte x = 128;
    ubyte y = 129;
    bool overflows;

    ubyte result = adds(x, y, overflows);

    writefln("%u + %u = %u, overflows: %b", x, y, result, overflows);
}
