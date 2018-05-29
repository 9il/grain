import std.stdio;
import std.typecons : tuple;

import mir.ndslice; // : sliced, map, slice;
import numir;

import grain.autograd;

enum files = [
    "train-images-idx3-ubyte",
    "train-labels-idx1-ubyte",
    "t10k-images-idx3-ubyte",
    "t10k-labels-idx1-ubyte"
    ];

struct Dataset {
    Slice!(Contiguous, [3], float*) inputs;
    Slice!(Contiguous, [1], int*) targets;
}

auto prepareDataset() {
    import std.file : exists, read, mkdir;
    import std.algorithm : canFind;
    import std.zlib : UnCompress;
    import std.net.curl : download;

    Dataset train, test;
    if (!exists("data")) {
        mkdir("data");
    }
    foreach (f; files) {
        auto gz = "data/" ~ f ~ ".gz";
        writeln("loading " ~ gz);
        if (!exists(gz)) {
            auto url = "http://yann.lecun.com/exdb/mnist/" ~ f ~ ".gz";
            download(url, gz);
        }
        auto unc = new UnCompress;
        auto decomp = cast(ubyte[]) unc.uncompress(gz.read);
        auto dataset = f.canFind("train") ? train : test;
        if (f.canFind("images")) {
            // skip header
            decomp = decomp[16..$];
            auto ndata = decomp.length / (28 * 28);
            auto imgs = decomp.sliced(ndata, 28, 28);
            // debug print
            writeln("first image:");
            foreach (i; 0 ..  imgs.length!1) {
                import std.format;
                imgs[0, i].format!"%(%3s %)".writeln;
            }
            // normalize 0 .. 255 to 0.0 .. 1.0
            dataset.inputs = imgs.map!(i => 1.0f * i / 255).slice;
        } else { // labels
            // skip header
            decomp = decomp[8..$];
            dataset.targets = decomp.sliced.as!int.slice;
            // debug print
            writeln("first label: ", dataset.targets[0]);
        }
    }
    return tuple!("train", "test")(train, test);
}


void main() {
    auto datasets = prepareDataset();
}

