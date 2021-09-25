module plottingui;

private {
    import gio.Application : GioApplication = Application;
    import gtk.Application;
    import gtk.ApplicationWindow;
    import gtk.Button;
    import gtk.Widget;
    import gtk.DrawingArea;
    import cairo.Context;
    import cairo.Surface;
    import ggplotd.ggplotd;
    import ggplotd.axes: XAxis, YAxis;
}

class PlotWidget: DrawingArea {
    private:

    GGPlotD _plot;

    protected:

    bool drawHandler(Scoped!Context c, Widget w) {
        GtkAllocation size;
        getAllocation(size);
        Surface s = c.getTarget();

        c.setSourceRgba(1, 1, 1, 1);
        c.paint();

        s = plot.drawToSurface(s, size.width, size.height);
        return true;
    }

    public:

    this(GGPlotD plot) {
        this._plot = plot;
        addOnDraw(&drawHandler);
    }

    @property
    GGPlotD plot() {
        return this._plot;
    }

    @property
    void plot(GGPlotD plot) {
        this._plot = plot;
    }
}

class PlottingApp: ApplicationWindow {
    PlotWidget plot;

    this(Application app, GGPlotD toView) {
        super(app);
        setTitle("Chromatogram Plotter");
        setDefaultSize(250, 250);

        plot = new PlotWidget(toView);
        add(plot);
        plot.show();
    }
}

int runPlottingApp(string[] args, GGPlotD toView) {
    auto app = new Application("compbioproject.plottingui", GApplicationFlags.FLAGS_NONE);

    app.addOnActivate(delegate void(GioApplication gapp) {
        auto plotWindow = new PlottingApp(app, toView);
        plotWindow.showAll();
    });

    return app.run(args);
}
