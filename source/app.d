import std.stdio;
import chromatogram;
import fileutil;
import plotting;
import std.conv: to;

int main(string[] args) {
	if(args.length >= 2) {
		switch(args[1]) {
			case "info":
				if(args.length != 3) break;
				chromatagramInfo(new FileCharInputRange!(ubyte, ubyte, 1024)(File(args[2], "rb")));
				return 0;
			case "extract":
				if(args.length != 4) break;
				auto input = new FileCharInputRange!(char, dchar, 1024)(File(args[2], "r"));
				auto output = File(args[3], "w").lockingBinaryWriter();
				writeln("Extracting...");
				(ChromatogamExtactor!(typeof(input))).extractChromatograms(input, output);
				writeln("Done!");
				return 0;
			case "plotTo":
				if(show(args)) return 0;
				break;
			default:
				break;
		}

		writeln(HELP_MSG);
	}
	else {
		writeln(HELP_MSG);
	}

	return 0;
}

enum MATCH_TYPE = [
"I": &searchByIndex,
"N": &searchByName
];

bool show(string[] args) {
	if(args.length != 6) return false;

	auto input = new FileCharInputRange!(ubyte, ubyte)(File(args[2], "rb"));
	auto matchFunc = MATCH_TYPE[args[3]](to!string(args[4]));

	writeln("Plotting and Saving...");
	plotChromatogram(input, matchFunc, args[5]);
	writeln("Done!");
	return true;
}

enum HELP_MSG = "
Cromatogram Analyzer

Commands:
	- 'extract mzML_FILE OUTPUT': Extract chromatograms to a new chromato file.
	- 'info CHROMATO_FILE': Get info about the given extracted chromato file..
	- 'plotTo CHROMATO_FILE {N:match name, I:match index} MATCH_VAL DEST_PICTURE': Save a plot of the given chromatogram.
";
