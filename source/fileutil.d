module fileutil;

import std.conv: to;
import core.exception: RangeError;
import std.stdio: File;
import std.traits: isStaticArray, isInstanceOf;
import std.range;
import sys = std.system;
import std.bitmanip: Endian, read, append;
import std.typecons: Nullable;

class StructValidationError: Exception {
    this(string msg, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
    }
}

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


template IOConstant(T, string varName, Endian e = sys.endian, T checkVal) {
    immutable string declaration = T.stringof ~ " " ~ varName ~ ";\n";

    void readFrom(S, R)(ref S storeTo, ref R readFrom) {
        static if(isStaticArray!T) {
            foreach(ref element; mixin("storeTo." ~ varName)) {
                element = read!(typeof(element), e, R)(readFrom);
            }
        }
        else {
            mixin("storeTo." ~ varName) = read!(T, e, R)(readFrom);
        }
        if(mixin("storeTo." ~ varName) != checkVal) throw new StructValidationError(
            varName ~ " doesn't match expected value " ~ to!string(checkVal)
        );
    }

    void writeTo(S, R)(ref S writeFrom, ref R writeTo) {
        mixin("writeFrom." ~ varName) = checkVal;

        static if(isStaticArray!T) {
            foreach(ref element; mixin("writeFrom." ~ varName)) {
                append!(typeof(element), e, R)(writeTo, element);
            }
        }
        else {
            append!(T, e, R)(writeTo, mixin("writeFrom." ~ varName));
        }
    }

    size_t ioSize(S)(ref S thisStruct) {
        return T.sizeof;
    }
}

template IOValue(T, string varName, Endian e = sys.endian) {
    immutable string declaration = T.stringof ~ " " ~ varName ~ ";\n";

    void readFrom(S, R)(ref S storeTo, ref R readFrom) {
        static if(isStaticArray!T) {
            foreach(ref element; mixin("storeTo." ~ varName)) {
                element = read!(typeof(element), e, R)(readFrom);
            }
        }
        else {
            mixin("storeTo." ~ varName) = read!(T, e, R)(readFrom);
        }
    }

    void writeTo(S, R)(ref S writeFrom, ref R writeTo) {
        static if(isStaticArray!T) {
            foreach(ref element; mixin("writeFrom." ~ varName)) {
                append!(typeof(element), e, R)(writeTo, element);
            }
        }
        else {
            append!(T, e, R)(writeTo, mixin("writeFrom." ~ varName));
        }
    }

    size_t ioSize(S)(ref S thisStruct) {
        return T.sizeof;
    }
}

template IOArray(T, string varName, Endian e = sys.endian, string getLength) {
    immutable string declaration = T.stringof ~ "[] " ~ varName ~ ";\n";

    void readFrom(S, R)(ref S storeTo, ref R readFrom) {
        with(storeTo) {
            mixin(varName ~ ".length") = mixin(getLength);
        }

        foreach(ref element; mixin("storeTo." ~ varName)) {
            element = read!(typeof(element), e, R)(readFrom);
        }
    }

    void writeTo(S, R)(ref S writeFrom, ref R writeTo) {
        with(writeFrom) {
            if(mixin(varName ~ ".length") != (mixin(getLength))) {
                throw new StructValidationError(
                    "Length of " ~ varName ~ " did not match length implied by other struct fields."
                );
            }
        }

        foreach(ref element; mixin("writeFrom." ~ varName)) {
            append!(typeof(element), e, R)(writeTo, element);
        }
    }

    size_t ioSize(S)(ref S thisStruct) {
        with(thisStruct) {
            if(mixin(varName ~ ".length") != (mixin(getLength))) {
                throw new StructValidationError(
                "Length of " ~ varName ~ " did not match length implied by other struct fields."
                );
            }

            return mixin(varName ~ ".length") * T.sizeof;
        }
    }
}

template IOIgnore(T, string varName, Endian e = sys.endian, string getLength) {
    immutable string declaration = T.stringof ~ " " ~ varName ~ ";\n";

    void readFrom(S, R)(ref S storeTo, ref R readFrom) {}
    void writeTo(S, R)(ref S writeFrom, ref R writeTo) {}

    size_t ioSize(S)(ref S thisStruct) {
        return 0;
    }
}

import std.typecons: Tuple;

template isIOValues(VALS...) {
    static if(VALS.length == 0) {
        enum bool isIOValues = true;
    }
    else {
        enum bool isIOValues = (
            (
                isInstanceOf!(IOValue, VALS[0])
                || isInstanceOf!(IOConstant, VALS[0])
                || isInstanceOf!(IOArray, VALS[0])
                || isInstanceOf!(IOIgnore, VALS[0])
            )
            && isIOValues!(VALS[1..$])
        );
    }
}

template IOStruct(VALS...) if(isIOValues!VALS) {

    struct IOStruct {
        static foreach(val; VALS) {
            mixin(val.declaration);
        }

        static IOStruct readFrom(R)(auto ref R r) if(isInputRange!R && is(ElementType!R : const ubyte)) {
            IOStruct s;

            static foreach(val; VALS) {
                val.readFrom!(typeof(s), R)(s, r);
            }

            return s;
        }

        void writeTo(R)(auto ref R r) if(isOutputRange!(R, ubyte)) {
            // Set length fields to match length of arrays they specify length for...
            static foreach(val; VALS) {
                val.writeTo!(typeof(this), R)(this, r);
            }
        }

        size_t size() {
            size_t l = 0;
            static foreach(val; VALS) l += val.ioSize(this);
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