module chromatogram;

import std.stdio;
import xml;
import fileutil;
import core.exception;
import std.bitmanip: read, Endian;
import std.range;
import std.base64: Base64;
import std.conv: to;

static enum CHROMATOGRAM_LIST_TAG = "chromatogramList";
static enum CHROMATOGRAM_TAG = "chromatogram";
static enum DATA_ARRAY_TAG = "binaryDataArray";
static enum PARAM_TAG = "cvParam";
static enum BINARY_TAG = "binary";

// Chromatogram format for our output...

enum Endian CHROMATOGRAM_ENDIAN = Endian.littleEndian;
enum ubyte[8] MAGIC_VALUE = ['C', 'H', 'R', 'O', 'M', 'A', 'T', 'O'];
enum ubyte[4] GRAM_CHUNK = ['G', 'R', 'A', 'M'];

alias ChromatogramHeader = IOStruct!(
    IOValue!(ubyte[8], "magic", CHROMATOGRAM_ENDIAN),
    IOValue!(size_t, "first", CHROMATOGRAM_ENDIAN)
);

alias ChromatogramData = IOStruct!(
    IOValue!(byte[4], "magic", CHROMATOGRAM_ENDIAN),
    IOValue!(ushort, "nameSize", CHROMATOGRAM_ENDIAN),
    IOValue!(ubyte, "name", CHROMATOGRAM_ENDIAN, "nameSize"),
    IOValue!(size_t, "numEntries", CHROMATOGRAM_ENDIAN),
    IOValue!(size_t, "next", CHROMATOGRAM_ENDIAN),
    IOValue!(double, "times", CHROMATOGRAM_ENDIAN, "numEntries"),
    IOValue!(double, "intensities", CHROMATOGRAM_ENDIAN, "numEntries"),
);

class ChromatogramWriter(R) if(isOutputRange!(R, ubyte)) {
    private:

    R r;
    size_t offset;

    void writeHeader() {
        auto header = ChromatogramHeader(MAGIC_VALUE, 0);
        offset = header.size();
        header.first = offset;
        header.writeTo(r);
    }

    public:

    this(R r) {
        this(r);
    }

    this(ref R r) {
        this.r = r;
        writeHeader();
    }

    void put(ref ChromatogramData d) {
        offset += d.size();
        d.next = offset;
        d.writeTo(r);
    }
}

class ExtractionError: Exception {
    this(string msg, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
    }
}

template ChromatogamExtactor(E, uint BS = 8) {
    alias Parser = XMLParser!(E, BS);

    void extractChromatograms(R)(auto ref E e, auto ref R r) if(isReadable!E && isOutputRange!(R, ubyte)) {
        auto parser = Parser(e);
        auto chromatogramWriter = new ChromatogramWriter!R(r);

        parser.skipTo(CHROMATOGRAM_LIST_TAG);

        foreach(element; parser) {
            if(element.elemType == XMLType.START_TAG && element.name == CHROMATOGRAM_TAG) {
                extractChromatogram(parser, chromatogramWriter);
            }
            if(element.elemType == XMLType.END_TAG && element.name == CHROMATOGRAM_LIST_TAG) return;
        }
    }

    void extractChromatogram(R)(auto ref Parser p, ref ChromatogramWriter!R w) {
        auto data = ChromatogramData(GRAM_CHUNK);

        data.name = cast(ubyte[])(p.front.attributes.get("id", "Unknown"));
        data.numEntries = to!size_t(p.front.attributes.get("defaultArrayLength", "0"));

        foreach(element; p) {
            if(element.elemType == XMLType.START_TAG && element.name == DATA_ARRAY_TAG) {
                extractArray(p, data);
            }
            if(element.elemType == XMLType.END_TAG && element.name == CHROMATOGRAM_TAG) break;
        }

        if(data.intensities.length != data.times.length) {
            throw new ExtractionError("Chromatogram did not have intensities and times!");
        }

        w.put(data);
    }

    void extractArray(ref Parser p, ref ChromatogramData c) {
        byte isDouble = -1;
        byte compression = -1;
        byte isIntensity = -1;

        foreach(element; p) {
            if(element.elemType == XMLType.EMPTY_TAG && element.name == PARAM_TAG) {
                string val = element.attributes.get("accession", "");

                switch(val) {
                    case "MS:1000515":
                    case "MS:1000595":
                        isIntensity = val == "MS:1000515";
                        break;
                    case "MS:1000576":
                        compression = 0;
                        break;
                    case "MS:1000523":
                    case "MS:1000521":
                        isDouble = val == "MS:1000523";
                        break;
                    default:
                        break;
                }
            }

            if(element.elemType == XMLType.START_TAG && element.name == BINARY_TAG) {
                if(isIntensity < 0) return;
                if(isDouble < 0 || compression < 0) {
                    throw new ExtractionError("mzML does not specify required info for the binary array!");
                }

                char[] textData;

                while(!(element.elemType == XMLType.END_TAG && element.name == BINARY_TAG)) {
                    if(element.elemType == XMLType.END_TAG && element.name == DATA_ARRAY_TAG)
                        throw new ExtractionError("Binary tag not closed!");
                    if(element.elemType == XMLType.DATA) textData ~= element.data;

                    p.popFront();
                    if(p.empty) throw new ExtractionError("Reached end before finding binary end tag!");
                    element = p.front;
                }
                // Now decode and store...
                ubyte[] rawData = Base64.decode(textData);
                auto rawIter = chain(rawData);
                double[] result = new double[rawData.length / ((isDouble)? double.sizeof: float.sizeof)];

                foreach(ref value; result) {
                    if(isDouble) {
                        value = read!(double, CHROMATOGRAM_ENDIAN)(rawIter);
                    }
                    else {
                        value = read!(float, CHROMATOGRAM_ENDIAN)(rawIter);
                    }
                }

                if(isIntensity) {
                    c.intensities = result;
                }
                else {
                    c.times = result;
                }
            }

            if(element.elemType == XMLType.END_TAG && element.name == DATA_ARRAY_TAG) return;
        }
    }
}

enum isBinaryInput(E) = (isInputRange!E && is(ElementType!E: ubyte));

class ChromatogramReader(I) if(isBinaryInput!I) {
    private:

    I input;
    ChromatogramHeader h;
    ChromatogramData current;
    bool _empty;

    public:

    this(I input) {
        this.input = input;
        this.h = ChromatogramHeader.readFrom(input);
        this.popFront();
    }

    @property
    ChromatogramHeader header() {
        return h;
    }

    @property
    ChromatogramData front() {
        return current;
    }

    @property
    bool empty() {
        return this._empty && input.empty;
    }

    void popFront() {
        if(input.empty) _empty = true;
        if(this.empty) return;
        current = ChromatogramData.readFrom(input);
    }
}

enum Writer = (string s) => writeln(s);

void chromatagramInfo(I)(I input, void function(string) writer = Writer) if(isBinaryInput!I) {
    auto reader = new ChromatogramReader!I(input);
    size_t count, dataPoints;

    foreach(i, data; enumerate(reader)) {
        writer("Entry: " ~ to!string(i));
        writer("\tName: " ~ cast(string)(data.name));
        writer("\tSize: " ~ to!string(data.numEntries));
        writer("");
        count++;
        dataPoints += data.numEntries;
    }

    writer("Summary:");
    writer("\tCount: " ~ to!string(count));
    writer("\tTotal Data Points: " ~ to!string(dataPoints));
}






