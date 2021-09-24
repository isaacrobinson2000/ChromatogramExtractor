module fileutil;

import std.conv: to;
import core.exception: RangeError;
import std.stdio: File;
import std.traits: isStaticArray, isInstanceOf;
import std.range;
import sys = std.system;
import std.bitmanip: Endian, read, append;

class FileCharInputRange(T = ubyte, T_RETURN = T, uint SIZE = 4096) {
    private:
    File f;
    T[SIZE] buffer;
    size_t current = 0;
    bool started = false;
    size_t allocated = 0;

    public:

    this(File f) {
        this.f = f;
    }

    private void loadNext() {
        if(!f.eof) {
            auto subBuffer = f.rawRead(buffer);
            current = 0;
            allocated = subBuffer.length;
            started = true;
        }
        else {
            buffer[0] = buffer[current - 1];
            allocated = 0;
            current = 0;
            started = true;
        }
    }

    @property
    T_RETURN front() {
        if(!started) loadNext();
        return buffer[current];
    }

    @property
    bool empty() {
        if(!started) loadNext();
        return (allocated < buffer.length) && (current >= allocated);
    }

    void popFront() {
        if(this.empty) return;
        current++;
        if(current >= allocated) loadNext();
    }
}

template IOValue(T, string varName, Endian e = sys.endian, string lengthRef = "") {
    alias Type = T;
    immutable string name = varName;
    immutable Endian endian = e;
    immutable string lengthProp = lengthRef;
}

import std.typecons: Tuple;

template isIOValues(VALS...) {
    static if(VALS.length == 0) {
        enum bool isIOValues = true;
    }
    else {
        enum bool isIOValues = isInstanceOf!(IOValue, VALS[0]) && isIOValues!(VALS[1..$]);
    }
}

template IOStruct(VALS...) if(isIOValues!VALS) {

    struct IOStruct {
        static foreach(val; VALS) {
            static if(val.lengthProp.length == 0) {
                mixin(val.Type.stringof ~ " " ~ val.name ~ ";\n");
            }
            else {
                mixin(val.Type.stringof ~ "[] " ~ val.name ~ ";\n");
            }
        }

        static IOStruct readFrom(R)(auto ref R r) if(isInputRange!R && is(ElementType!R : const ubyte)) {
            IOStruct s;

            static foreach(val; VALS) {

                static if(val.lengthProp.length == 0) {
                    static if(isStaticArray!(val.Type)) {
                        foreach(ref element; mixin("s." ~ val.name)) {
                            element = read!(typeof(element), val.endian, R)(r);
                        }
                    }
                    else {
                        mixin("s." ~ val.name) = read!(val.Type, val.endian, R)(r);
                    }
                }
                else {
                    import std.stdio;
                    writeln("Loading " ~ val.name);
                    writeln(mixin("s." ~ val.lengthProp));
                    mixin("s." ~ val.name).length = mixin("s." ~ val.lengthProp);
                    foreach(ref element; mixin("s." ~ val.name)) {
                        element = read!(val.Type, val.endian, R)(r);
                    }
                }
            }

            return s;
        }

        void writeTo(R)(auto ref R r) if(isOutputRange!(R, ubyte)) {
            // Set length fields to match length of arrays they specify length for...
            static foreach(val; VALS) {
                static if(val.lengthProp.length != 0) {
                    if(mixin("this." ~ val.name).length > typeof(mixin("this." ~ val.lengthProp)).max) {
                        throw new RangeError("Array is larger then what can be stored!");
                    }
                    mixin("this." ~ val.lengthProp) = (
                        cast(typeof(mixin("this." ~ val.lengthProp))) mixin("this." ~ val.name).length
                    );
                }
            }

            // Write out all values
            static foreach(val; VALS) {
                static if(val.lengthProp.length == 0) {
                    static if(isStaticArray!(val.Type)) {
                        foreach(ref element; mixin("this." ~ val.name)) {
                             append!(typeof(element), val.endian, R)(r, element);
                        }
                    }
                    else {
                        append!(val.Type, val.endian, R)(r, mixin("this." ~ val.name));
                    }
                }
                else {
                    foreach(ref element; mixin("this." ~ val.name)) {
                        append!(val.Type, val.endian, R)(r, element);
                    }
                }
            }
        }

        size_t size() {
            size_t l = 0;

            static foreach(val; VALS) {
                static if(val.lengthProp.length == 0) {
                    l += val.Type.sizeof;
                }
                else {
                    l += val.Type.sizeof * mixin("this." ~ val.name).length;
                }
            }

            return l;
        }
    }
}

unittest {
    import std.stdio: writeln;
    import std.array;

    enum Endian e = Endian.littleEndian;

    alias Test = IOStruct!(
        IOValue!(ubyte[4], "magic", e),
        IOValue!(size_t, "length", e),
        IOValue!(int, "data", e, "length"),
    );

    auto buffer = appender!(const ubyte[])();

    static assert(is(typeof(Test.magic) == ubyte[4]));
    static assert(is(typeof(Test.length) == size_t));
    static assert(is(typeof(Test.data) == int[]));

    auto test = Test([1, 2, 3, 4], 3, [5, 6, 7, 8]);

    test.writeTo(buffer);
    assert(buffer.data == [1, 2, 3, 4, 4, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 6, 0, 0, 0, 7, 0, 0, 0, 8, 0, 0, 0]);

    auto test2 = Test.readFrom(buffer.data);
    assert(test2.magic == [1, 2, 3, 4]);
    assert(test2.length == 4);
    assert(test2.data == [5, 6, 7, 8]);
}