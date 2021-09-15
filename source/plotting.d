module plotting;

import chromatogram;

private {
    import plot2kill.all, plot2kill.util;
}

alias ChromatoSearchFunction = bool delegate(ref ChromatogramData, size_t i);

ChromatoSearchFunction searchByIndex(size_t i) {
    return (ref ChromatogramData d, size_t j) => j == i;
}

ChromatoSearchFunction searchByName(string name) {
    return (ref ChromatogramData d, size_t i) => d.name == name;
}

void plotChromatogram(I)(I input, ChromatoSearchFunction isMatch) if(isBinaryInput!I) {
    auto reader = ChromatogramReader(input);

    ChromatogramData toPlot;

    foreach(i, cdata; enumerate(reader)) {
        if(isMatch(cdata, i)) {
            toPlot = cdata;
            break;
        }
    }

    auto scatter = ScatterPlot(toPlot.times, toPlot.intensities).toFigure();
    scatter.showAsMain();
}