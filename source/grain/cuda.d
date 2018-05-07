module grain.cuda;

import std.traits : ReturnType, arity;
import std.stdio : writeln, writefln;
import std.string : toStringz, fromStringz;

import derelict.cuda;

// TODO: support multiple GPU devices (context)
CUcontext context;

static this() {
    DerelictCUDADriver.load();
    CUdevice device;

    // Initialize the driver API
    cuInit(0);
    // Get a handle to the first compute device
    cuDeviceGet(&device, 0);
    // Create a compute device context
    cuCtxCreate(&context, 0, device);
}

static ~this() {
    checkCudaErrors(cuCtxDestroy(context));
}


struct CuModule {
    CUmodule cuModule;

    this(string path) {
        import std.file : readText;
        auto ptxstr = readText(path);
        // JIT compile a null-terminated PTX string
        checkCudaErrors(cuModuleLoadData(&cuModule, cast(void*) ptxstr.toStringz));
    }

    ~this() {
        checkCudaErrors(cuModuleUnload(cuModule));
    }

    auto kernel(alias F)() {
        return Kernel!F(cuModule);
    }
}


class GlobalModule {
    private this() {}

    // Cache instantiation flag in thread-local bool
    // Thread local
    private static bool instantiated_;

    // Thread global
    private __gshared CuModule* instance_;

    static get()
    {
        if (!instantiated_)
        {
            synchronized(GlobalModule.classinfo)
            {
                instance_ = new CuModule("kernel/kernel.ptx");
                instantiated_ = true;
            }
        }

        return instance_;
    }
}


struct Kernel(alias F) if (is(ReturnType!F == void)) {
    enum name = __traits(identifier, F);
    CUfunction cuFunction;
    void*[arity!F] params;

    this(CUmodule m) {
        writeln("kernel: ", name);
        checkCudaErrors(cuModuleGetFunction(&cuFunction, m, name.toStringz));
    }

    auto kernelParams(T...)(T args) {
        void*[args.length] ret;
        foreach (i, a; args) {
            ret[i] = &a;
        }
        return ret;
    }

    // TODO: compile-time type check like d-nv
    // TODO: separate this to struct Launcher
    void launch(T...)(
        T args, uint[3] grid, uint[3] block,
        uint sharedMemBytes = 0,
        CUstream stream = null
        ) if (args.length == arity!F) {
        // Kernel launch
        checkCudaErrors(cuLaunchKernel(
                            cuFunction,
                            grid[0], grid[1], grid[2],
                            block[0], block[1], block[2],
                            sharedMemBytes, stream,
                            kernelParams(args).ptr, null));
    }
}


struct CuPtr(T) {
    CUdeviceptr ptr;
    size_t length;

    this(T[] host) {
        this.length = host.length;
        checkCudaErrors(cuMemAlloc(&ptr, T.sizeof * length));
        checkCudaErrors(cuMemcpyHtoD(ptr, &host[0], T.sizeof * length));
    }

    this(size_t n) {
        length = n;
        checkCudaErrors(cuMemAlloc(&ptr, T.sizeof * n));
    }

    ~this() {
        checkCudaErrors(cuMemFree(ptr));
    }

    auto toCPU(T[] host) {
        host.length = length;
        checkCudaErrors(cuMemcpyDtoH(&host[0], ptr, T.sizeof * length));
        return host;
    }

    auto toCPU() {
        auto host = new T[length];
        checkCudaErrors(cuMemcpyDtoH(&host[0], ptr, T.sizeof * length));
        return host;
    }
}

void checkCudaErrors(CUresult err) {
    const(char)* name, content;
    cuGetErrorName(err, &name);
    cuGetErrorString(err, &content);
    assert(err == CUDA_SUCCESS, name.fromStringz ~ ": " ~ content.fromStringz);
}

unittest
{
    import grain.kernel : saxpy;

    // Get a handle to the kernel function in kernel/kernel.d
    // See Makefile how to create kernel/kernel.ptx
    auto ksaxpy = GlobalModule.get().kernel!saxpy;

    // Populate input
    uint n = 16;
    auto hostA = new float[n];
    auto hostB = new float[n];
    auto hostC = new float[n];
    foreach (i; 0 .. n) {
        hostA[i] = i;
        hostB[i] = 2 * i;
        hostC[i] = 0;
    }

    // Device data
    auto devA = CuPtr!float(hostA);
    auto devB = CuPtr!float(hostB);
    auto devC = CuPtr!float(n);

    // Kernel launch
    ksaxpy.launch(devC.ptr, devA.ptr, devB.ptr, n, [1,1,1], [n,1,1]);

    // Validation
    devC.toCPU(hostC);
    foreach (i; 0 .. n) {
        writefln!"%f + %f = %f"(hostA[i], hostB[i], hostC[i]);
        assert(hostA[i] + hostB[i] == hostC[i]);
    }
}
