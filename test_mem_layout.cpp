#if (__clang__) || (__GNUC__)
#if __aarch64__
#define X86 0
#define X64 1
#elif __x86_64__
#define X86 0
#define X64 1
#elif __i386__
#define X86 1
#define X64 0
#elif __arm__
#define X86 1
#define X64 0
#endif
#elif _MSC_VER
#if _M_X64
#define X86 0
#define X64 1
#elif _M_IX86
#define X86 1
#define X64 0
#endif
#endif

union LuaJitTValue {
    unsigned long long u64;
    double n;
#if X64
    void * gcr;
    long long it64;
    struct {
        int i;
        unsigned int it;
    };
#else
    struct {
        union{
            void * gcr;
            int i;
        };
        unsigned int it;
    };
#endif
#if X64
    long long ftsz;
#else
    struct {
        void * func;
        union {
            int ftsz;
            void* pcr;
        };
    } fr;
#endif
    struct {
        unsigned int lo;
        unsigned int hi;
    } u32;
};

#define GCHeader void* nextgc; unsigned char marked; unsigned char gct

struct LuaJitNode {
    LuaJitTValue val;
    LuaJitTValue key;
    void* next;
#if !X64
    void* freetop;
#endif
};

struct LuaJitTab {
    GCHeader;
    unsigned char nomm;
    char colo;
    void* array;
    void* gclist;
    void* metatable;
    void* node;
    unsigned int asize;
    unsigned int hmask;
#if X64
    void* freetop;
#endif
};

union Lua51Value {
    void* gc;
    double n;
    int b;
};

#define TValuefields Lua51Value value; int tt

struct Lua51TValue {
    TValuefields;
};

union Lua51TKey {
    struct {
        TValuefields;
        void* next;
    } nk;
    Lua51TValue tvk;
};

struct Lua51Node {
    Lua51TValue i_val;
    Lua51TKey i_key;
};

#define CommonHeader void* next; char tt; char marked

struct Lua51Table {
    CommonHeader;
    char flags;
    char lsizenode;
    Lua51Table* metatable;
    Lua51TValue* array;
    Lua51Node* node;
    Lua51Node* lastfree;
    void* gclist;
    int sizearray;
};

#include <iostream>

template<class Type>
void dump(const char* tag, const char* kind)
{
    Type v1;
    Type v2[2];
    std::cout << tag << " " << kind << " size:" << sizeof(v1) << ", " << kind << "[2] size:" << sizeof(v2) << std::endl;
}

int main() {
#if X86
    std::cout << "Compiled with x86!\n";
#else
    std::cout << "Compiled with x64!\n";
#endif
    std::cout<< "long long size:" << sizeof(long long)
        << ", int size:" << sizeof(int)
        << ", void* size:" << sizeof (void*)
        << ", char size:" << sizeof(char)
        << std::endl;

    dump<LuaJitTValue>("LuaJit", "TValue");
    dump<LuaJitNode>("LuaJit", "Node");
    dump<LuaJitTab>("LuaJit", "Table");

    std::cout << std::endl;
    dump<Lua51TValue>("Lua5.1", "TValue");
    dump<Lua51TKey>("Lua5.1", "TKey");
    dump<Lua51Node>("Lua5.1", "Node");
    dump<Lua51Table>("Lua5.1", "Table");
    return 0;
}
