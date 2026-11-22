#ifndef RILL_SMC_H
#define RILL_SMC_H
#include <stdint.h>
#include <IOKit/IOKitLib.h>

/// Opens the AppleSMC user client. Returns 0 on failure. Reading keys needs no privileges.
io_connect_t smc_open(void);
void smc_close(io_connect_t conn);

/// Reads one key. On success returns 0 and fills type (4 chars, e.g. "flt "), bytes and size (<= 32).
/// Two round trips to the SMC: key info, then bytes.
int smc_read(io_connect_t conn, const char key[4], char type[5], uint8_t bytes[32], uint32_t *size);

/// The two halves of smc_read, so a caller that polls the same keys can look
/// up type and size once and spend one round trip per read afterwards.
int smc_key_info(io_connect_t conn, const char key[4], char type[5], uint32_t *size);
int smc_read_bytes(io_connect_t conn, const char key[4], uint32_t size, uint8_t bytes[32]);

/// Number of keys the SMC exposes, and the key at an index (for discovery).
uint32_t smc_key_count(io_connect_t conn);
int smc_key_at(io_connect_t conn, uint32_t index, char key[5]);
#endif
