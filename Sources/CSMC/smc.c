#include "smc.h"
#include <string.h>

// Layout shared with the AppleSMC kext (as used by smcFanControl and Stats).
typedef struct { char major, minor, build, reserved; uint16_t release; } SMCVers;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } SMCPLimit;
typedef struct { uint32_t dataSize, dataType; uint8_t dataAttributes; } SMCKeyInfo;
typedef struct {
    uint32_t key;
    SMCVers vers;
    SMCPLimit pLimitData;
    SMCKeyInfo keyInfo;
    uint8_t result, status, data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCParam;

enum { kHandleYPCEvent = 2, kReadBytes = 5, kReadIndex = 8, kReadKeyInfo = 9 };

static uint32_t fourcc(const char k[4]) {
    return ((uint32_t)(uint8_t)k[0] << 24) | ((uint32_t)(uint8_t)k[1] << 16) | ((uint32_t)(uint8_t)k[2] << 8) | (uint8_t)k[3];
}

static void unfourcc(uint32_t v, char out[5]) {
    out[0] = (char)(v >> 24); out[1] = (char)(v >> 16); out[2] = (char)(v >> 8); out[3] = (char)v; out[4] = 0;
}

static int call(io_connect_t conn, SMCParam *in, SMCParam *out) {
    size_t outSize = sizeof(SMCParam);
    kern_return_t kr = IOConnectCallStructMethod(conn, kHandleYPCEvent, in, sizeof(SMCParam), out, &outSize);
    return (kr == KERN_SUCCESS && out->result == 0) ? 0 : -1;
}

io_connect_t smc_open(void) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return 0;
    io_connect_t conn = 0;
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, &conn);
    IOObjectRelease(service);
    return kr == KERN_SUCCESS ? conn : 0;
}

void smc_close(io_connect_t conn) { if (conn) IOServiceClose(conn); }

int smc_read(io_connect_t conn, const char key[4], char type[5], uint8_t bytes[32], uint32_t *size) {
    SMCParam in, out;
    memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
    in.key = fourcc(key);
    in.data8 = kReadKeyInfo;
    if (call(conn, &in, &out) != 0) return -1;
    uint32_t dataSize = out.keyInfo.dataSize;
    uint32_t dataType = out.keyInfo.dataType;
    if (dataSize == 0 || dataSize > 32) return -1;

    memset(&in, 0, sizeof in);
    in.key = fourcc(key);
    in.keyInfo.dataSize = dataSize;
    in.data8 = kReadBytes;
    memset(&out, 0, sizeof out);
    if (call(conn, &in, &out) != 0) return -1;
    unfourcc(dataType, type);
    memcpy(bytes, out.bytes, dataSize);
    *size = dataSize;
    return 0;
}

uint32_t smc_key_count(io_connect_t conn) {
    char type[5]; uint8_t b[32]; uint32_t n = 0;
    if (smc_read(conn, "#KEY", type, b, &n) != 0 || n < 4) return 0;
    return ((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16) | ((uint32_t)b[2] << 8) | b[3];
}

int smc_key_at(io_connect_t conn, uint32_t index, char key[5]) {
    SMCParam in, out;
    memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
    in.data8 = kReadIndex;
    in.data32 = index;
    if (call(conn, &in, &out) != 0) return -1;
    unfourcc(out.key, key);
    return 0;
}
