// Minimal C FFI over iroh for the mosaic mobile transport spike.
// See rust/src/lib.rs for semantics. All blocking; call off the main thread.

#ifndef MOSAIC_IROH_FFI_H
#define MOSAIC_IROH_FFI_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MosaicIrohEndpoint MosaicIrohEndpoint;
typedef struct MosaicIrohConnection MosaicIrohConnection;

MosaicIrohEndpoint *mosaic_iroh_endpoint_bind(
    bool enable_relay,
    bool accept_connections,
    char *err_buf,
    size_t err_cap);

char *mosaic_iroh_endpoint_id(const MosaicIrohEndpoint *endpoint);

char *mosaic_iroh_endpoint_route_json(const MosaicIrohEndpoint *endpoint);

int mosaic_iroh_endpoint_online(
    MosaicIrohEndpoint *endpoint,
    uint64_t timeout_ms,
    char *err_buf,
    size_t err_cap);

MosaicIrohConnection *mosaic_iroh_endpoint_accept(
    MosaicIrohEndpoint *endpoint,
    uint64_t timeout_ms,
    char *err_buf,
    size_t err_cap);

MosaicIrohConnection *mosaic_iroh_endpoint_connect(
    MosaicIrohEndpoint *endpoint,
    const char *endpoint_id,
    const char *relay_url,
    const char *const *direct_addrs,
    size_t direct_addr_count,
    uint64_t timeout_ms,
    char *err_buf,
    size_t err_cap);

intptr_t mosaic_iroh_connection_recv(
    MosaicIrohConnection *connection,
    uint8_t *buf,
    size_t cap,
    char *err_buf,
    size_t err_cap);

int mosaic_iroh_connection_send(
    MosaicIrohConnection *connection,
    const uint8_t *bytes,
    size_t len,
    char *err_buf,
    size_t err_cap);

void mosaic_iroh_connection_close(MosaicIrohConnection *connection);

void mosaic_iroh_endpoint_close(MosaicIrohEndpoint *endpoint);

void mosaic_iroh_string_free(char *string);

#ifdef __cplusplus
}
#endif

#endif // MOSAIC_IROH_FFI_H
