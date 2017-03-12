/* TODO(mtwilliams): Rather use `getconf LFS_CFLAGS`? */
#define _FILE_OFFSET_BITS 64

#include <assert.h>
#include <stdlib.h>
#include <stdbool.h>
#include <stdint.h>
#include <inttypes.h>
#include <string.h>
#include <stdio.h>

#include <errno.h>

#include <unistd.h>
#include <fcntl.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mman.h>

/* TODO(mtwilliams): Handle booleans better. */
#ifndef TRUE
#  define TRUE (true)
#endif
#ifndef FALSE
#  define FALSE (true)
#endif

/*
 * Utilities
 */

/* Quickly computes the base-2 logarithim of |n|. */
static uint64_t u_log2i(uint64_t n) {
  return n ? (64 - __builtin_clzll(n - 1)) : 0;
}

/* Returns the number of bytes required to hold |n| bits. */
static uint64_t u_bits_to_bytes(uint64_t n) {
  return (n + 7) / 8;
}

/* Returns the number of bits that can be held by |n| bytes.*/
static uint64_t u_bytes_to_bits(uint64_t n) {
  return n * 8;
}

/* Returns the greatest value in an |array| of |n| integers. */
static uint64_t u_highest_in_array(const uint64_t *array, const uint64_t n) {
  assert(array != NULL);
  uint64_t highest = 0;
  for (uint64_t i = 0; i < n; ++i)
    highest = (array[i] > highest) ? array[i] : highest;
  return highest;
}

/* OPTIMIZE(mtwilliams): Do we want to relax ordering? */

static uint64_t atomic_load_64(volatile uint64_t *P) {
  return __atomic_load_n(P, __ATOMIC_SEQ_CST);
}

static void atomic_store_64(volatile uint64_t *P, const uint64_t v) {
  __atomic_store_n(P, v, __ATOMIC_SEQ_CST);
}

static void *atomic_load_ptr(volatile void **P) {
  return (void *)__atomic_load_n(P, __ATOMIC_SEQ_CST);
}

static void atomic_store_ptr(volatile void **P, const void *v) {
  __atomic_store_n(P, (volatile void *)v, __ATOMIC_SEQ_CST);
}

static uint64_t atomic_cmp_and_xchg_64(volatile uint64_t *P, const uint64_t expected, const uint64_t desired) {
  uint64_t original = expected;
  __atomic_compare_exchange_n(P, &original, desired, FALSE, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
  return original;
}

static void atomic_increment_64(volatile uint64_t *P) {
  __atomic_add_fetch(P, 1, __ATOMIC_SEQ_CST);
}

static void atomic_decrement_64(volatile uint64_t *P) {
  __atomic_sub_fetch(P, 1, __ATOMIC_SEQ_CST);
}

/*
 * Interface
 */

#define BITSET_VERSION ((uint64_t)1)

typedef struct bitset {
  /* Backing file. */
  char path[256];
  int fd;

  /* Where we've mapped the backing file in memory. */
  volatile void *base;

  /* Lock-free tracking of operations.
   * See `bitset_wait_for_operations_in_progress`. */
  struct {
    volatile uint64_t started;
    volatile uint64_t completed;
  } operations;

  /* An internal `lock' that must been owned by a thread to perform managerial
   * tasks. See `bitset_resize`. */
  volatile uint64_t locked;
} bitset_t;

typedef struct bitset_options {
  /* Minimum size of bitset in number of bits. */
  uint64_t size;
} bitset_options_t;

/* TODO(mtwilliams): Rename to something clearer. */
typedef struct bitset_meta_t {
  /* First four bytes are used as a canary to identify bitsets. */
  char magic[4];

  /* Not used yet. */
  uint64_t version;

  /* Size of bitset in number of bits. */
  uint64_t size;

  uint64_t bits[0];
} bitset_meta_t;

typedef enum bitset_error {
  /* Success! */
  BITSET_ERROR_NONE = 0,
  /* Not a bitset. */
  BITSET_ERROR_NOT_A_BITSET = 1,
  /* No longer supported. */
  BITSET_ERROR_UNSUPPORTED = 2,
  /* Don't have permissions to do that. */
  BITSET_ERROR_PERMISSIONS = 3,
  /* Out of memory. */
  BITSET_ERROR_OUT_OF_MEMORY = 4,
  /* Out of storage. */
  BITSET_ERROR_OUT_OF_STORAGE = 5,
  BITSET_ERROR_UNKNOWN = -1
} bitset_error_t;


/* OPTIMIZE(mtwilliams): Restrict pointers. */
/* OPTIMIZE(mtwilliams): Compact `states` into bitsets. */

/* */
static bitset_error_t bitset_open(const char *path, const bitset_options_t *options, bitset_t **bitset);

/* */
static void bitset_close(bitset_t *bitset, bool del);

/* Returns the number of bytes required to store a bitset on disk that can hold
 * |num_of_bits| bits. */
static uint64_t bitset_size_on_disk(uint64_t num_of_bits) {
  return sizeof(bitset_meta_t) + u_bits_to_bytes(num_of_bits);
}

/* Returns the number of bytes required to store a bitset in memory that can
 * hold |num_of_bits| bits. */
static uint64_t bitset_size_in_memory(uint64_t num_of_bits) {
  return bitset_size_on_disk(num_of_bits);
}

static bitset_error_t bitset_get(bitset_t *bitset, const uint64_t *bits, uint64_t *states, const uint64_t n);
static bitset_error_t bitset_set(bitset_t *bitset, const uint64_t *bits, const uint64_t n);

/* Grows or shrinks |bitset| to hold |bits| bits.*/
static bitset_error_t bitset_resize(bitset_t *bitset, const uint64_t bits);

/*
 * Implementation
 */

#define BITSET_BASE(bitset) \
  atomic_load_ptr(&(bitset)->base)

#define BITSET_META(bitset) \
  ((bitset_meta_t *)BITSET_BASE(bitset))

#define BITSET_OPERATION_START(bitset) \
  bitset_meta_t *meta = BITSET_BASE(bitset); \
  atomic_increment_64(&(bitset)->operations.started);

#define BITSET_OPERATION_COMPLETE(bitset) \
  atomic_increment_64(&(bitset)->operations.completed)

/* Grows |bitset| to hold the highest bit in |bits|.*/
static bitset_error_t bitset_grow_if_nessecary(bitset_t *bitset, const uint64_t *bits, const uint64_t n);

/* Waits until all operations currently in progress complete. */
static void bitset_wait_for_operations_in_progress(bitset_t *bitset);

static bitset_error_t bitset_create(const char *path, int fd, const bitset_options_t *options, bitset_t **bitset) {
  const uint64_t bits = (1 << (u_log2i(options->size) + 1));

  const uint64_t size_on_disk = bitset_size_on_disk(bits);
  const uint64_t size_in_mem = bitset_size_in_memory(bits);

  if (ftruncate(fd, size_on_disk) != 0)
    goto error;

  void *base = mmap(NULL, size_in_mem, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  if (base == MAP_FAILED)
    goto error;

  bitset_meta_t *meta = (bitset_meta_t *)base;
  meta->magic[0] = 'B';
  meta->magic[1] = 'I';
  meta->magic[2] = 'T';
  meta->magic[3] = 'S';
  meta->version = BITSET_VERSION;
  meta->size = bits;

  msync((void *)meta, sizeof(bitset_meta_t), MS_SYNC);

  *bitset = (bitset_t *)malloc(sizeof(bitset_t));
  strncpy(&(*bitset)->path[0], path, 256);
  (*bitset)->fd = fd;
  (*bitset)->base = base;
  (*bitset)->operations.started = 0;
  (*bitset)->operations.completed = 0;
  (*bitset)->locked = FALSE;

  return BITSET_ERROR_NONE;

error:
  close(fd);

  if (errno == EACCES)
    return BITSET_ERROR_PERMISSIONS;
  if (errno == ENOMEM)
    return BITSET_ERROR_OUT_OF_MEMORY;
  if (errno == EFBIG)
    return BITSET_ERROR_OUT_OF_STORAGE;

  return BITSET_ERROR_UNKNOWN;
}

static bitset_error_t bitset_open(const char *path, const bitset_options_t *options, bitset_t **bitset) {
  assert(path != NULL);
  assert(strlen(path) <= 255);
  assert(options != NULL);
  assert(bitset != NULL);

  /* TODO(mtwilliams): Acquire an exclusive lock on |fd|. */
  int fd = open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH);
  if (fd == -1)
    goto error;

  struct stat stat;
  if (fstat(fd, &stat) != 0) {
    close(fd);
    return BITSET_ERROR_UNKNOWN;
  }

  if (stat.st_size == 0)
    return bitset_create(path, fd, options, bitset);

  void *base = mmap(NULL, stat.st_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  if (base == MAP_FAILED)
    goto error;

  bitset_meta_t *meta = (bitset_meta_t *)base;

  if (memcmp(&meta->magic[0], "BITS", 4) != 0) {
    munmap(base, stat.st_size);
    close(fd);
    return BITSET_ERROR_NOT_A_BITSET;
  }

  if (meta->version != BITSET_VERSION) {
    munmap(base, stat.st_size);
    close(fd);
    return BITSET_ERROR_UNSUPPORTED;
  }

  *bitset = (bitset_t *)malloc(sizeof(bitset_t));
  strncpy(&(*bitset)->path[0], path, 256);
  (*bitset)->fd = fd;
  (*bitset)->base = base;
  (*bitset)->operations.started = 0;
  (*bitset)->operations.completed = 0;
  (*bitset)->locked = FALSE;

  return BITSET_ERROR_NONE;

error:
  if (errno == EACCES)
    return BITSET_ERROR_PERMISSIONS;
  if (errno == ENOMEM)
    return BITSET_ERROR_OUT_OF_MEMORY;
  if (errno == EDQUOT)
    return BITSET_ERROR_OUT_OF_STORAGE;
  if (errno == EFBIG)
    return BITSET_ERROR_OUT_OF_STORAGE;

  return BITSET_ERROR_UNKNOWN;
}

static void bitset_close(bitset_t *bitset, bool del) {
  assert(bitset != NULL);

  while (atomic_cmp_and_xchg_64(&bitset->locked, FALSE, TRUE) != FALSE);

  /* Wait until *all* operations are completed, so we don't lose data. */
  bitset_wait_for_operations_in_progress(bitset);

  const uint64_t size_in_mem =
    bitset_size_in_memory(((bitset_meta_t *)bitset->base)->size);

  if (!del) {
    /* Make sure all data hits our backing file. */
    msync((void *)bitset->base, size_in_mem, MS_SYNC);
  }

  munmap((void *)bitset->base, size_in_mem);
  close(bitset->fd);

  if (del) {
    remove(bitset->path);
  }

  free((void *)bitset);
}

static bitset_error_t bitset_get(bitset_t *bitset, const uint64_t *bits, uint64_t *states, const uint64_t n) {
  assert(bitset != NULL);
  assert(bits != NULL);
  assert(states != NULL);

  const bitset_error_t error = bitset_grow_if_nessecary(bitset, bits, n);
  if (error != BITSET_ERROR_NONE)
    return error;

  BITSET_OPERATION_START(bitset);

  for (uint64_t i = 0; i < n; ++i) {
    const uint64_t bit = bits[i];
    const uint64_t byte = bit/64;
  #if TRACE && VERBOSE
    printf("[GET]   byte=%llu bit=%llu\n", byte, bit%64);
  #endif
    states[i] = !!(meta->bits[bit/64] & (1 << (bit%64)));
  }

  BITSET_OPERATION_COMPLETE(bitset);

  return BITSET_ERROR_NONE;
}

static bitset_error_t bitset_set(bitset_t *bitset, const uint64_t *bits, const uint64_t n) {
  assert(bitset != NULL);
  assert(bits != NULL);

  const bitset_error_t error = bitset_grow_if_nessecary(bitset, bits, n);
  if (error != BITSET_ERROR_NONE)
    return error;

  BITSET_OPERATION_START(bitset);

  for (uint64_t i = 0; i < n; ++i) {
    const uint64_t bit = bits[i];
  #if TRACE && VERBOSE
    printf("[SET]   byte=%llu bit=%llu\n", bit/64, bit%64);
  #endif
    meta->bits[bit/64] |= (1 << (bit%64));
  }

  BITSET_OPERATION_COMPLETE(bitset);

  return BITSET_ERROR_NONE;
}

static bitset_error_t bitset_unset(bitset_t *bitset, const uint64_t *bits, const uint64_t n) {
  assert(bitset != NULL);
  assert(bits != NULL);

  const bitset_error_t error = bitset_grow_if_nessecary(bitset, bits, n);
  if (error != BITSET_ERROR_NONE)
    return error;

  BITSET_OPERATION_START(bitset);

  for (uint64_t i = 0; i < n; ++i) {
    const uint64_t bit = bits[i];
  #if TRACE && VERBOSE
    printf("[UNSET] byte=%llu bit=%llu\n", bit/64, bit%64);
  #endif
    meta->bits[bit/64] &= ~(1 << (bit%64));
  }

  BITSET_OPERATION_COMPLETE(bitset);

  return BITSET_ERROR_NONE;
}

static void bitset_wait_for_operations_in_progress(bitset_t *bitset) {
  assert(bitset != NULL);

  const uint64_t started = atomic_load_64(&bitset->operations.started);
  const uint64_t completed = atomic_load_64(&bitset->operations.completed);

#if TRACE
  uint64_t ops_in_progress;

  if (completed < started)
    ops_in_progress = (~(0ull) - completed) + started;
  else
    ops_in_progress = started - completed;

  printf("[LOCK] Waiting for %llu operations in progress.\n", ops_in_progress);
#endif

  if (completed < started) {
  #if TRACE
    printf("[LOCK] Counters overflowed!\n");
  #endif
    /* Counters overflowed. */
    while (TRUE) {
      const uint64_t n = atomic_load_64(&bitset->operations.completed);
      if ((n >= completed) && (n <= started))
        break;
    }
  } else {
    while (atomic_load_64(&bitset->operations.completed) < started);
  }

#if TRACE
  printf("[LOCK] Done waiting.\n");
#endif
}

static bitset_error_t bitset_resize(bitset_t *bitset, const uint64_t bits) {
  assert(bitset != NULL);

  if (BITSET_META(bitset)->size == bits) {
  #if TRACE
    printf("[RESIZE] Skipped. Exactly the same size?\n");
  #endif
    return BITSET_ERROR_NONE;
  }

  if (atomic_cmp_and_xchg_64(&bitset->locked, FALSE, TRUE) != FALSE) {
    /* Another thread is already growing this bitset so we'll wait. */
  #if TRACE
    printf("[RESIZE] Waiting on another thread...\n");
  #endif
    while (atomic_load_64(&bitset->locked));
  #if TRACE
    printf("[RESIZE] Other thread done, retrying...\n");
  #endif
    return bitset_resize(bitset, bits);
  }

  bitset_meta_t *const meta = BITSET_META(bitset);

  const bool shrinking = (meta->size > bits);
  const bool growing = (meta->size < bits);

#if TRACE
  if (growing)
    printf("[GROW]   bits=%llu bytes=%llu\n", bits, u_bits_to_bytes(bits));
  if (shrinking)
    printf("[SHRINK] bits=%llu bytes=%llu\n", bits, u_bits_to_bytes(bits));
#endif

  if (shrinking) {
  #if TRACE
    printf("[SHRINK] Advertising smaller size...\n");
  #endif
    /* We need to make sure no operation will try to read or write
     * out-of-bounds, so we advertise the new (smaller) size early. */
    meta->size = bits;
    msync((void *)meta, sizeof(bitset_meta_t), MS_SYNC);
    bitset_wait_for_operations_in_progress(bitset);
  }

  const uint64_t prev_size_on_disk =
    bitset_size_on_disk(BITSET_META(bitset)->size);
  const uint64_t prev_size_in_mem =
    bitset_size_in_memory(BITSET_META(bitset)->size);

  const uint64_t size_on_disk = bitset_size_on_disk(bits);
  const uint64_t size_in_mem = bitset_size_in_memory(bits);

#if TRACE
  printf("[RESIZE] Resizing backing file.\n");
#endif

  if (ftruncate(bitset->fd, size_on_disk) != 0)
    goto error;

  if (shrinking) {
    /* Don't bother to shrink the mapping. */
    goto success;
  }

#if TRACE
  printf("[RESIZE] Replacing mapping.\n");
#endif

  void *old_base_ptr =
    atomic_load_ptr(&bitset->base);

  void *new_base_ptr =
    mmap(NULL, size_in_mem, PROT_READ | PROT_WRITE, MAP_SHARED, bitset->fd, 0);

  if (new_base_ptr == MAP_FAILED)
    goto error;

  atomic_store_ptr(&bitset->base, new_base_ptr);

  /* We have to wait until *all* operations using the previous base pointer are
   * completed prior to unmapping the previous mapping.*/
  bitset_wait_for_operations_in_progress(bitset);

  munmap(old_base_ptr, prev_size_in_mem);

  /* Finally, we can advertise the new (larger) size. */
  BITSET_META(bitset)->size = bits;
  msync((void *)meta, sizeof(bitset_meta_t), MS_SYNC);

success:
#if TRACE
  printf("[RESIZE] Done.\n");
#endif
  atomic_store_64(&bitset->locked, FALSE);
  return BITSET_ERROR_NONE;

error:
  if (errno == ENOMEM)
    return BITSET_ERROR_OUT_OF_MEMORY;
  if (errno == EOVERFLOW)
    return BITSET_ERROR_OUT_OF_MEMORY;
  if (errno == EFBIG)
    return BITSET_ERROR_OUT_OF_STORAGE;

  return BITSET_ERROR_UNKNOWN;
}

static bitset_error_t bitset_grow_if_nessecary(bitset_t *bitset, const uint64_t *bits, const uint64_t n) {
  const uint64_t highest = u_highest_in_array(bits, n);

  if (highest < BITSET_META(bitset)->size)
    return BITSET_ERROR_NONE;

  const uint64_t size = (1ull << (u_log2i(highest) + 1ull));

#if TRACE
  const uint64_t old_size_in_bits = BITSET_META(bitset)->size;
  const uint64_t old_size_in_bytes = u_bits_to_bytes(old_size_in_bits);
  const uint64_t new_size_in_bits = size;
  const uint64_t new_size_in_bytes = u_bits_to_bytes(new_size_in_bits);

  printf("[BOUNDS] highest=%llu log2(highest)=%llu size=%llubits/%llubytes new_size=%llubits/%llubytes\n", highest, u_log2i(highest), old_size_in_bits, old_size_in_bytes, new_size_in_bits, new_size_in_bytes);
#endif

  return bitset_resize(bitset, size);
}

/*
 * NIF
 */

#include "erl_nif.h"

static ErlNifResourceType *bitset_nif_resource_type;

static ERL_NIF_TERM BITSET_NIF_OK;
static ERL_NIF_TERM BITSET_NIF_ERROR;

static ERL_NIF_TERM BITSET_NIF_NOT_A_BITSET;
static ERL_NIF_TERM BITSET_NIF_UNSUPPORTED;
static ERL_NIF_TERM BITSET_NIF_PERMISSIONS;
static ERL_NIF_TERM BITSET_NIF_OUT_OF_MEMORY;
static ERL_NIF_TERM BITSET_NIF_OUT_OF_STORAGE;

static ERL_NIF_TERM BITSET_NIF_UNKNOWN;

static ERL_NIF_TERM
bitset_nif_options_from_keyword(ErlNifEnv *env, const ERL_NIF_TERM keyword, bitset_options_t *options) {
  assert(options != NULL);

  ERL_NIF_TERM head, tail = keyword;
  while (enif_get_list_cell(env, tail, &head, &tail)) {
    int arity;
    ERL_NIF_TERM *tuple;

    if (!enif_get_tuple(env, head, &arity, &tuple))
      goto malformed;

  #ifndef NDEBUG
    if (arity != 2)
      goto malformed;
    if (!enif_is_atom(env, tuple[0]))
      goto malformed;
  #endif

    if (enif_is_identical(tuple[0], enif_make_atom(env, "size"))) {
      ErlNifSInt64 size;
      if (!enif_get_int64(env, tuple[1], &size))
        return enif_make_tuple2(env, BITSET_NIF_ERROR, enif_make_string(env, "Expected `size` to be an non-negative integer.", ERL_NIF_LATIN1));
      if (size < 0)
        return enif_make_tuple2(env, BITSET_NIF_ERROR, enif_make_string(env, "Expected `size` to be an non-negative integer.", ERL_NIF_LATIN1));
      options->size = size;
    } else {
      /* TODO(mtwilliams): Use `enif_get_atom` to provide a more helpful response. */
      return enif_make_tuple2(env, BITSET_NIF_ERROR, enif_make_string(env, "Unknown option provided.", ERL_NIF_LATIN1));
    }
  }

  return BITSET_NIF_OK;

malformed:
  goto malformed;
}

static ERL_NIF_TERM
bitset_nif_error_to_erlang(ErlNifEnv *env, const bitset_error_t error) {
  ERL_NIF_TERM erlang = BITSET_NIF_UNKNOWN;

  switch (error) {
    case BITSET_ERROR_NOT_A_BITSET: erlang = BITSET_NIF_NOT_A_BITSET; break;
    case BITSET_ERROR_UNSUPPORTED: erlang = BITSET_NIF_UNSUPPORTED; break;
    case BITSET_ERROR_PERMISSIONS: erlang = BITSET_NIF_PERMISSIONS; break;
    case BITSET_ERROR_OUT_OF_MEMORY: erlang = BITSET_NIF_OUT_OF_MEMORY; break;
    case BITSET_ERROR_OUT_OF_STORAGE: erlang = BITSET_NIF_OUT_OF_STORAGE; break;
  }

  return enif_make_tuple2(env, BITSET_NIF_ERROR, erlang);
}

static ERL_NIF_TERM
bitset_nif_open(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  switch (argc) {
    case 2:
      if (!enif_is_list(env, argv[1]))
        return enif_make_tuple2(env, BITSET_NIF_ERROR, enif_make_string(env, "Expected `options` to be a keyword list.", ERL_NIF_LATIN1));
    case 1:
      if (!enif_is_binary(env, argv[0]))
        return enif_make_tuple2(env, BITSET_NIF_ERROR, enif_make_string(env, "Expected `path` to be a string.", ERL_NIF_LATIN1));
  }

  char path[256] = { 0, }; {
    ErlNifBinary binary;
    enif_inspect_binary(env, argv[0], &binary);
    assert(binary.size <= 255);
    memcpy(&path[0], (const char *)binary.data, binary.size);
    path[binary.size] = '\0';
  }

  bitset_options_t options;
  options.size = 0;

  if (argc >= 2) {
    ERL_NIF_TERM result = bitset_nif_options_from_keyword(env, argv[1], &options);
    if (!enif_is_identical(BITSET_NIF_OK, result))
      return result;
  }

  bitset_t *bitset;
  bitset_error_t result = bitset_open(&path[0], &options, &bitset);
  if (result != BITSET_ERROR_NONE)
    return bitset_nif_error_to_erlang(env, result);

  void *boxed = enif_alloc_resource(bitset_nif_resource_type, sizeof(bitset_t *));
  *((bitset_t **)boxed) = bitset;

  return enif_make_tuple2(env, BITSET_NIF_OK, enif_make_resource(env, boxed));
}

static ERL_NIF_TERM
bitset_nif_do_close(ErlNifEnv *env, const ERL_NIF_TERM resource, bool del) {
  void *boxed;
  if (!enif_get_resource(env, resource, bitset_nif_resource_type, &boxed))
    return enif_make_badarg(env);
  bitset_close(*((bitset_t **)boxed), del);
  enif_release_resource(boxed);
  return BITSET_NIF_OK;
}

static ERL_NIF_TERM
bitset_nif_close(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  return bitset_nif_do_close(env, argv[0], false);
}

static ERL_NIF_TERM
bitset_nif_delete(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  return bitset_nif_do_close(env, argv[0], true);
}

#define BITSET_NIF_UNBOX(env, term) \
  bitset_t *bitset = bitset_nif_unbox((env), (term)); \
  if (!bitset) { return enif_make_badarg(env); }

static bitset_t *bitset_nif_unbox(ErlNifEnv *env, ERL_NIF_TERM term) {
  void *boxed;
  if (!enif_get_resource(env, term, bitset_nif_resource_type, &boxed))
    return NULL;
  return *((bitset_t **)boxed);
}

static bool bitset_nif_indicies_from_list(ErlNifEnv *env, ERL_NIF_TERM list, uint64_t **indicies, unsigned *count) {
  if (!enif_get_list_length(env, list, count))
    return false;

  *indicies = (uint64_t *)enif_alloc((*count) * sizeof(uint64_t));

  unsigned n = 0;
  ERL_NIF_TERM head, tail = list;
  while (enif_get_list_cell(env, tail, &head, &tail)) {
    ErlNifSInt64 index;
    if (!enif_get_int64(env, head, &index))
      goto badarg;
    if (index < 0)
      goto badarg;
    (*indicies)[n++] = index;
  }

  assert(n == (*count));
  return true;

badarg:
  enif_free((void *)indicies);
  return false;
}

static ERL_NIF_TERM
bitset_nif_list_from_states(ErlNifEnv *env, const uint64_t *states, const uint64_t n) {
  ERL_NIF_TERM *translated = (ERL_NIF_TERM *)enif_alloc(n * sizeof(ERL_NIF_TERM));

  for (uint64_t i = 0; i < n; ++i)
    translated[i] = enif_make_int(env, states[i]);

  ERL_NIF_TERM list = enif_make_list_from_array(env, &translated[0], n);
  enif_free((void *)translated);
  return list;
}

static ERL_NIF_TERM
bitset_nif_get(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  BITSET_NIF_UNBOX(env, argv[0]);

  uint64_t *bits;
  unsigned count;
  if (!bitset_nif_indicies_from_list(env, argv[1], &bits, &count))
    return enif_make_badarg(env);

  uint64_t *states = (uint64_t *)enif_alloc(count * sizeof(uint64_t));
  memset((void *)states, 0, count * sizeof(uint64_t));

  const bitset_error_t result = bitset_get(bitset, bits, states, count);

  if (result != BITSET_ERROR_NONE) {
    enif_free((void *)bits);
    enif_free((void *)states);
    return bitset_nif_error_to_erlang(env, result);
  } else {
    enif_free((void *)bits);
  }

  ERL_NIF_TERM translated = bitset_nif_list_from_states(env, states, count);
  enif_free((void *)states);
  return enif_make_tuple2(env, BITSET_NIF_OK, translated);
}

static ERL_NIF_TERM
bitset_nif_set(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  BITSET_NIF_UNBOX(env, argv[0]);

  uint64_t *bits;
  unsigned count;
  if (!bitset_nif_indicies_from_list(env, argv[1], &bits, &count))
    return enif_make_badarg(env);

  const bitset_error_t result = bitset_set(bitset, bits, count);

  enif_free((void *)bits);

  if (result != BITSET_ERROR_NONE)
    return bitset_nif_error_to_erlang(env, result);

  return BITSET_NIF_OK;
}

static ERL_NIF_TERM
bitset_nif_unset(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  BITSET_NIF_UNBOX(env, argv[0]);

  uint64_t *bits;
  unsigned count;
  if (!bitset_nif_indicies_from_list(env, argv[1], &bits, &count))
    return enif_make_badarg(env);

  const bitset_error_t result = bitset_unset(bitset, bits, count);

  enif_free((void *)bits);

  if (result != BITSET_ERROR_NONE)
    return bitset_nif_error_to_erlang(env, result);

  return BITSET_NIF_OK;
}

static ErlNifFunc bitset_nif_funcs[] = {
  {"open",   1, &bitset_nif_open,   ERL_NIF_DIRTY_JOB_IO_BOUND},
  {"open",   2, &bitset_nif_open,   ERL_NIF_DIRTY_JOB_IO_BOUND},
  {"close",  1, &bitset_nif_close,  ERL_NIF_DIRTY_JOB_IO_BOUND},
  {"delete", 1, &bitset_nif_delete, ERL_NIF_DIRTY_JOB_IO_BOUND},
  {"get",    2, &bitset_nif_get,    ERL_NIF_DIRTY_JOB_CPU_BOUND},
  {"set",    2, &bitset_nif_set,    ERL_NIF_DIRTY_JOB_CPU_BOUND},
  {"unset",  2, &bitset_nif_unset,  ERL_NIF_DIRTY_JOB_CPU_BOUND}
};

static int bitset_nif_load(ErlNifEnv *env, void **priv_data, ERL_NIF_TERM load_info) {
  bitset_nif_resource_type = enif_open_resource_type(env, NULL, "bitset", NULL, ERL_NIF_RT_CREATE, NULL);
  if (!bitset_nif_resource_type)
    return 1;

  BITSET_NIF_OK = enif_make_atom(env, "ok");
  BITSET_NIF_ERROR = enif_make_atom(env, "error");

  BITSET_NIF_NOT_A_BITSET = enif_make_atom(env, "not_a_bitset");
  BITSET_NIF_UNSUPPORTED = enif_make_atom(env, "unsupported");
  BITSET_NIF_PERMISSIONS = enif_make_atom(env, "permissions");
  BITSET_NIF_OUT_OF_MEMORY = enif_make_atom(env, "out_of_memory");
  BITSET_NIF_OUT_OF_STORAGE = enif_make_atom(env, "out_of_storage");

  BITSET_NIF_UNKNOWN = enif_make_atom(env, "unknown");

  return 0;
}

static int bitset_nif_upgrade(ErlNifEnv *env, void **priv_data, void** old_priv_data, ERL_NIF_TERM load_info) {
  return 0;
}

static void bitset_nif_unload(ErlNifEnv *env, void *priv_data) {
}

ERL_NIF_INIT(Elixir.GithubViz.Bitset, bitset_nif_funcs, &bitset_nif_load, NULL, &bitset_nif_upgrade, &bitset_nif_unload)
