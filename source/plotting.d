module plotting;

import chromatogram;

private {
    import std.array: array;
    import std.algorithm: map;
    import std.range: iota, enumerate, zip;
    import std.conv: to;

    import ggplotd.ggplotd;
    import ggplotd.geom;
    import ggplotd.aes;
    import ggplotd.axes: xaxisLabel, yaxisLabel;
    import ggplotd.theme: background;
}

alias ChromatoSearchFunction = bool delegate(ref ChromatogramData, size_t i);

ChromatoSearchFunction searchByIndex(string idx) {
    size_t i = to!size_t(idx);
    return (ref ChromatogramData d, size_t j) => j == i;
}

ChromatoSearchFunction searchByName(string name) {
    return (ref ChromatogramData d, size_t i) => d.name == name;
}

GGPlotD plotChromatogram(I)(I input, ChromatoSearchFunction isMatch) if(isBinaryInput!I) {
    auto reader = new ChromatogramReader!I(input);

    ChromatogramData toPlot;

    foreach(i, cdata; enumerate(reader)) {
        if(isMatch(cdata, i)) {
            toPlot = cdata;
            break;
        }
    }

    auto gg = zip(toPlot.times, toPlot.intensities).map!(
    (val) => aes!("x", "y", "colour", "size")(val[0], val[1], "blue", 0.8)
    ).array.geomLine.putIn(GGPlotD());

    gg.put(xaxisLabel("Time"));
    gg.put(yaxisLabel("Intensity"));
    gg.put(title("Chromatogram " ~ cast(string) toPlot.name));
    gg.put(background("white"));

    return gg;
}

void exportChromatogramPlot(I)(I input, ChromatoSearchFunction isMatch, string saveLoc) if(isBinaryInput!I) {
    plotChromatogram(input, isMatch).save(saveLoc);
}

