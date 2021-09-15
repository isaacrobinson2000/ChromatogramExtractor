module xml;

import std.range.primitives;
import std.uni;
import std.regex;
import std.array;
import std.conv;
import core.exception;


immutable NAME_START_CHAR = (
  r":|[A-Z]|_|[a-z]|"
~ r"[\u00C0-\u00D6]|[\u00D8-\u00F6]|"
~ r"[\u00F8-\u02FF]|[\u0370-\u037D]|"
~ r"[\u037F-\u1FFF]|[\u200C-\u200D]|"
~ r"[\u2070-\u218F]|[\u2C00-\u2FEF]|"
~ r"[\u3001-\uD7FF]|[\uF900-\uFDCF]|"
~ r"[\uFDF0-\uFFFD]|[\U00010000-\U000EFFFF]"
);

immutable VALID_START_CHAR = ctRegex!(NAME_START_CHAR);

immutable VALID_MID_CHAR = ctRegex!(
    NAME_START_CHAR ~ r"|\-|\.|[0-9]|\u00B7|[\u0300-\u036F]|[\u203F-\u2040]"
);

bool isStartNameChar(dchar c) {
    return !isWhite(c) && !(matchFirst(to!string(c), VALID_START_CHAR).empty);
}

bool isMidNameChar(dchar c) {
    return !isWhite(c) && !(matchFirst(to!string(c), VALID_MID_CHAR).empty);
}


enum XMLType {
    DOCUMENT_DECLARATION,
    DECLARATION,
    START_TAG,
    END_TAG,
    EMPTY_TAG,
    COMMENT,
    DATA,
    CDATA,
    NULL
}

class ParserError: Exception {
    this(string msg, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
    }
}

class XMLElement {
    XMLType elemType;
    string name = null;
    char[] data;
    string[string] attributes = null;

    this(XMLType elemType) {
        this.elemType = elemType;
    }
}

enum isReadable(E) = (isInputRange!E && is(ElementType!E == dchar));

class Reader(uint BUFFER_SIZE, E) if(isReadable!E) {
    private:

    E input;
    uint start = 0;
    uint _length = 0;
    dchar[BUFFER_SIZE] buffer;

    void get() {
        if(!input.empty) {
            buffer[(start + _length) % buffer.length] = input.front;
            input.popFront();
            _length++;
        }
    }

    public:

    this(E input) {
        this.input = input;
        // Initialize the buffer...
        for(int i = 0; i < buffer.length; i++) get();
    }

    bool next(size_t i) {
        bool result = true;
        while((i > 0) && ((result = next()) == true)) i--;
        return result;
    }

    bool next() {
        get();
        start = (start + 1) % buffer.length;
        _length -= (length != 0);
        return length != 0;
    }

    bool startsWith(string input) {
        if(input.length > _length) return false;

        for(int i = 0; i < input.length; i++)
            if(input[i] != this[i])
                return false;

        return true;
    }

    bool endsWith(string input) {
        if(input.length > _length) return false;

        for(int i = 1; i <= input.length; i++)
            if(input[$ - i] != this[$ - i])
                return false;

        return true;
    }

    @property
    uint length() const pure @safe {
        return _length;
    }

    alias opDollar = length;

    @property
    dchar front() {
        if(this._length == 0) throw new RangeError("Empty Reader!");
        return this[0];
    }

    dchar opIndex(uint i) const pure @safe {
        return buffer[(start + (i % _length)) % buffer.length];
    }

    override string toString() const pure @safe {
        char[] data;

        for(uint i = 0; i < length; i++) data ~= this[i];

        return "\"" ~ to!string(data) ~ "\"";
    }
}

unittest {
    // Test the ring reader above...
    auto reader = new Reader!(4, string)("Hello World!");
    assert(reader.length == 4);
    assert(reader.front == 'H');
    reader.next();
    assert(reader.length == 4);
    assert(reader.front == 'e');
    assert(reader.startsWith("ello"));
    assert(reader.endsWith("lo"));

    auto reader2 = new Reader!(6, string)("Hello");
    assert(reader2.length == 5);
}

template XMLParser(E, uint BS = 8) if(BS >= 8 && isReadable!E) {
    interface ElementParser {
        XMLElement parse(Reader!(BS, E) reader);
        bool isType(Reader!(BS, E) reader);
    }

    enum string[string] ESCAPE_CONVERSIONS = [
        "&lt;": "<",
        "&gt;": ">",
        "&amp;": "&",
        "&quot;": "\"",
        "&apos;": "'"
    ];

    string parseEscapeChar(ref Reader!(BS, E) r) {
        foreach(conv; ESCAPE_CONVERSIONS.byKeyValue()) {
            if(r.startsWith(conv.key)) {
                r.next(conv.key.length);
                return conv.value;
            }
        }

        throw new ParserError("Unkown & escape sequence in the file!");
    }

    void eatWhile(Reader!(BS, E) r, bool function(dchar) cont) {
        while(cont(r.front)) {
            if(!r.next()) throw new ParserError("Unexpected end of file!");
        }
    }

    string getWhile(Reader!(BS, E) r, bool function(dchar) cont) {
        char[] data;

        while(cont(r.front)) {
            data ~= r.front;
            if(!r.next()) throw new ParserError("Unexpected end of file!");
        }

        return to!string(data);
    }

    void validate(Reader!(BS, E) r, bool function(dchar) check, string msg) {
        if(!check(r.front)) throw new ParserError(msg);
    }

    class DummyParser(
        XMLType elementType,
        string startChars,
        string endChars,
        dchar[] illegalChars
    ): ElementParser {
        private bool isIn(dchar value, dchar[] values) {
            foreach(c; values) if(value == c) return true;
            return false;
        }

        override XMLElement parse(Reader!(BS, E) reader) {
            // New xml element...
            auto element = new XMLElement(elementType);
            // Jump over start of the item...
            reader.next(startChars.length);

            while((element.data.length < endChars.length) || (element.data[($-endChars.length) .. $] != endChars)) {
                if(isIn(reader.front, illegalChars))
                    throw new ParserError("Illegal character: " ~ cast(char)reader.front);
                element.data ~= reader.front;
                if(!reader.next()) throw new ParserError("Unexpected end of input!");
            }

            element.data = element.data[0..($ - endChars.length)];
            return element;
        }

        override bool isType(Reader!(BS, E) reader) {
            return reader.startsWith(startChars);
        }
    }

    alias DocumentDeclParser = DummyParser!(XMLType.DOCUMENT_DECLARATION, "<?", "?>", ['<']);

    alias CDATAParser = DummyParser!(XMLType.CDATA, "<![CDATA[", "]]>", []);

    alias DeclarationParser = DummyParser!(XMLType.DECLARATION, "<!", "!>", ['<']);

    class StartTagParser: ElementParser {
        private void parseAttributes(Reader!(BS, E) reader, XMLElement element) {
            while(!reader.startsWith("/>") && !reader.startsWith(">")) {
                validate(reader, &isStartNameChar, "Invalid attribute name!");
                string attrName = getWhile(reader, &isMidNameChar);

                validate(reader, (dchar s) => s == '=', "Attribute does not have an equal sign!");
                reader.next();

                const dchar terminator = reader.front;
                if((terminator != '\'') && (terminator != '"'))
                    throw new ParserError("Attribute assignment must be followed by quotation marks!");
                reader.next();

                char[] attrValue;

                while(reader.front != terminator) {
                    if(reader.front == '<') throw new ParserError("< Illegal in an attribute value...");
                    if(reader.front != '&') {
                        attrValue ~= reader.front;
                        if(!reader.next()) throw new ParserError("Unexpected end of file!");
                    }
                    else {
                        attrValue ~= parseEscapeChar(reader);
                    }
                }
                reader.next();
                element.attributes[attrName] = cast(string) attrValue;

                eatWhile(reader, &isWhite);
            }
        }

        override XMLElement parse(Reader!(BS, E) reader) {
            auto elem = new XMLElement(XMLType.START_TAG);
            // Skip the opening '<'
            reader.next();

            // Eat up white spice while we can...
            eatWhile(reader, &isWhite);
            validate(reader, &isStartNameChar, "Start tag has no name, or an invalid name!");
            string name = getWhile(reader, &isMidNameChar);
            eatWhile(reader, &isWhite);
            elem.name = name;

            parseAttributes(reader, elem);

            // Check type of element...
            immutable isEmpty = reader.startsWith("/>");
            elem.elemType = (isEmpty)? XMLType.EMPTY_TAG: XMLType.START_TAG;
            reader.next((isEmpty)? 2: 1);

            return elem;
        }

        override bool isType(Reader!(BS, E) reader) {
            return reader.startsWith("<");
        }
    }

    class EndTagParser: ElementParser {
        override XMLElement parse(Reader!(BS, E) reader) {
            auto elem = new XMLElement(XMLType.END_TAG);
            // Jump over '</'
            reader.next(2);
            // Eat up whitespace...
            eatWhile(reader, &isWhite);
            // Check for valid attribute, extract it...
            validate(reader, &isStartNameChar, "End tag has no name, or an invalid name!");
            string name = getWhile(reader, &isMidNameChar);
            eatWhile(reader, &isWhite);

            // Validate we have reached the end....
            validate(reader, (dchar s) => s == '>', "Illegal end tag! Additional words after the name.");
            reader.next();

            elem.name = name;
            elem.data = cast(char[]) name;
            return elem;
        }

        override bool isType(Reader!(BS, E) reader) {
            return reader.startsWith("</");
        }
    }

    alias CommentParser = DummyParser!(XMLType.COMMENT, "<!--", "-->", []);

    class DataParser: ElementParser {
        private bool existsHandler(Reader!(BS, E) reader) {
            foreach(hndl; PARSER_LIST[0 .. ($ - 1)]) {
                if(hndl.isType(reader)) return true;
            }
            return false;
        }

        override XMLElement parse(Reader!(BS, E) reader) {
            auto element = new XMLElement(XMLType.DATA);

            while(!existsHandler(reader)) {
                element.data ~= (reader.front != '&')? to!string(reader.front): parseEscapeChar(reader);
                if(!reader.next()) return element;
            }

            return element;
        }

        override bool isType(Reader!(BS, E) reader) {
            return true;
        }
    }

    struct XMLParser {
        private:
        Reader!(BS, E) r;
        XMLElement current = null;

        public:
        this(E e) {
            r = new Reader!(BS, E)(e);
            current = new XMLElement(XMLType.NULL);
        }

        /// Compares a string to a wrap around buffer to see if they match...
        private bool strMatch(dchar[] buffer, size_t start, string toMatch) {
            for(size_t i = 0; i < toMatch.length; i++) {
                if(toMatch[i] != buffer[(start + i) % $]) return false;
            }
            return true;
        }

        /**
        Turn off xml parsing, and simply scan the file until the plain text provided is found/matched.
        Then resume XML parsing at the nearest valid element which is not data after the provided text.
        **/
        void skipTo(string toMatch) {
            dchar[] compChars = new dchar[toMatch.length];
            size_t start = 0;
            size_t i = 0;

            // Simple scan and search... Run through the file until we find the match string...
            while(i < toMatch.length || !strMatch(compChars, start, toMatch)) {
                compChars[start] = r.front;
                start = (start + 1) % compChars.length;
                i += i < toMatch.length;
                if(!r.next()) break;
            }

            // Now we have found the keyword or reached eof, search for the next parsable section which is a tag,
            // and restart the range there... Otherwise we end up reaching the end and resume the range there...
            while(!this.empty) {
                foreach(hdlr; PARSER_LIST[0..$-1]) {
                    if(hdlr.isType(r)) {
                        current = hdlr.parse(r);
                        return;
                    }
                }
                r.next();
            }

            current = new XMLElement(XMLType.NULL);
            return;
        }

        @property
        bool empty() {
            return (r.length == 0);
        }

        @property
        XMLElement front() {
            return current;
        }

        void popFront() {
            if(this.empty) {
                current = new XMLElement(XMLType.NULL);
                return;
            }
            foreach (hdlr; PARSER_LIST) {
                if (hdlr.isType(r)) {
                    current = hdlr.parse(r);
                    return;
                }
            }

            throw new ParserError("Unrecognized grammar...");
        }
    }

    ElementParser[] PARSER_LIST = [
        new DocumentDeclParser(),
        new CommentParser(),
        new CDATAParser(),
        new DeclarationParser(),
        new EndTagParser(),
        new StartTagParser(),
        new DataParser()
    ];
}
